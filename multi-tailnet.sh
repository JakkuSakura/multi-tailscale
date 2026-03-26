#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG ======
NS="tailns"
VETH_HOST="veth-tail0"
VETH_NS="veth-tail1"
VETH_NET="192.168.101.0/24"
VETH_HOST_IP="192.168.101.1/24"
VETH_NS_IP="192.168.101.2/24"

TAILSCALE_BIN="/usr/sbin/tailscaled"
TAILSCALE_CLI="/usr/bin/tailscale"

STATE_DIR="/var/lib/tstail"
SOCKET="/run/tstail/tstail.socket"
TUN="tailscale0"

# Host interface that connects to the Internet (adjust)
HOST_IFACE="eth0"

# Subnets you want to reach via the SECOND tailnet (space-separated)
WORK_SUBNETS=("10.10.0.0/16" "10.20.0.0/16")

# ====== END CONFIG ======

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Must run as root" >&2
    exit 1
  fi
}

setup_netns() {
  ip netns add "${NS}" 2>/dev/null || true
  ip -n "${NS}" link set lo up

  ip link add "${VETH_HOST}" type veth peer name "${VETH_NS}" 2>/dev/null || true
  ip link set "${VETH_NS}" netns "${NS}"

  ip addr add "${VETH_HOST_IP}" dev "${VETH_HOST}" 2>/dev/null || true
  ip link set "${VETH_HOST}" up

  ip -n "${NS}" addr add "${VETH_NS_IP}" dev "${VETH_NS}" 2>/dev/null || true
  ip -n "${NS}" link set "${VETH_NS}" up

  sysctl -w net.ipv4.ip_forward=1 >/dev/null
  ip -n "${NS}" route add default via "${VETH_HOST_IP%/*}" 2>/dev/null || true
}

setup_routes() {
  for subnet in "${WORK_SUBNETS[@]}"; do
    ip route add "${subnet}" via "${VETH_NS_IP%/*}" 2>/dev/null || true
  done
}

setup_iptables() {
  if ! cmd_exists iptables; then
    echo "iptables not found. Install iptables or ask for nftables variant." >&2
    exit 1
  fi

  iptables -C FORWARD -i "${HOST_IFACE}" -o "${VETH_HOST}" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -i "${HOST_IFACE}" -o "${VETH_HOST}" -j ACCEPT
  iptables -C FORWARD -o "${HOST_IFACE}" -i "${VETH_HOST}" -j ACCEPT 2>/dev/null \
    || iptables -A FORWARD -o "${HOST_IFACE}" -i "${VETH_HOST}" -j ACCEPT

  iptables -t nat -C POSTROUTING -s "${VETH_NET}" -o "${HOST_IFACE}" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -s "${VETH_NET}" -o "${HOST_IFACE}" -j MASQUERADE

  ip netns exec "${NS}" iptables -t nat -C POSTROUTING -s "${VETH_NET}" -o "${TUN}" -j MASQUERADE 2>/dev/null \
    || ip netns exec "${NS}" iptables -t nat -A POSTROUTING -s "${VETH_NET}" -o "${TUN}" -j MASQUERADE
}

start_tailscaled() {
  mkdir -p "${STATE_DIR}" /run/tstail
  ip netns exec "${NS}" "${TAILSCALE_BIN}" \
    -tun "${TUN}" \
    --socket "${SOCKET}" \
    --state "${STATE_DIR}/tstail.state" \
    --statedir "${STATE_DIR}" \
    >/var/log/tstail.log 2>&1 &
  echo $! > /run/tstail/tstail.pid
}

login_second_tailnet() {
  "${TAILSCALE_CLI}" --socket "${SOCKET}" login --accept-routes
}

stop_tailscaled() {
  if [[ -f /run/tstail/tstail.pid ]]; then
    kill "$(cat /run/tstail/tstail.pid)" 2>/dev/null || true
    rm -f /run/tstail/tstail.pid
  fi
}

teardown() {
  stop_tailscaled
  for subnet in "${WORK_SUBNETS[@]}"; do
    ip route del "${subnet}" 2>/dev/null || true
  done
  ip link del "${VETH_HOST}" 2>/dev/null || true
  ip netns del "${NS}" 2>/dev/null || true
}

usage() {
  echo "Usage: $0 {up|login|down}"
}

main() {
  require_root
  case "${1:-}" in
    up)
      setup_netns
      setup_routes
      setup_iptables
      start_tailscaled
      echo "Second tailscaled started. Run: $0 login"
      ;;
    login)
      login_second_tailnet
      ;;
    down)
      teardown
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
