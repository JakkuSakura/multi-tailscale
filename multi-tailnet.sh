#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${MULTI_TAILNET_CONFIG:-${SCRIPT_DIR}/config.sh}"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

# Defaults (if not set by config)
NS="${NS:-tailns}"
VETH_HOST="${VETH_HOST:-veth-tail0}"
VETH_NS="${VETH_NS:-veth-tail1}"
VETH_NET="${VETH_NET:-192.168.101.0/24}"
VETH_HOST_IP="${VETH_HOST_IP:-192.168.101.1/24}"
VETH_NS_IP="${VETH_NS_IP:-192.168.101.2/24}"

TAILSCALE_BIN="${TAILSCALE_BIN:-/usr/sbin/tailscaled}"
TAILSCALE_CLI="${TAILSCALE_CLI:-/usr/bin/tailscale}"

STATE_DIR="${STATE_DIR:-/var/lib/tstail}"
SOCKET="${SOCKET:-/run/tstail/tstail.socket}"
TUN="${TUN:-tailscale0}"

HOST_IFACE="${HOST_IFACE:-eth0}"
WORK_SUBNETS=(${WORK_SUBNETS[@]:-"10.10.0.0/16" "10.20.0.0/16"})
FIREWALL="${FIREWALL:-auto}"
DNS_SERVERS=(${DNS_SERVERS[@]:-})

log() { echo "[multi-tailnet] $*"; }
err() { echo "[multi-tailnet] ERROR: $*" >&2; }

cmd_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_run_dir() {
  mkdir -p /run/tstail
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    err "Must run as root"
    exit 1
  fi
}

detect_firewall() {
  if [[ "${FIREWALL}" != "auto" ]]; then
    return 0
  fi

  if cmd_exists ufw && ufw status 2>/dev/null | head -n1 | grep -qi "active"; then
    FIREWALL="ufw"
    return 0
  fi

  if cmd_exists nft; then
    FIREWALL="nftables"
    return 0
  fi

  if cmd_exists iptables; then
    FIREWALL="iptables"
    return 0
  fi

  err "No supported firewall backend found (ufw, nftables, iptables)."
  exit 1
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

setup_dns() {
  if [[ "${#DNS_SERVERS[@]}" -eq 0 ]]; then
    return 0
  fi

  local netns_dir="/etc/netns/${NS}"
  local resolv_file="${netns_dir}/resolv.conf"

  ensure_run_dir
  mkdir -p "${netns_dir}"
  : > "${resolv_file}"
  for dns in "${DNS_SERVERS[@]}"; do
    echo "nameserver ${dns}" >> "${resolv_file}"
  done
  echo "options edns0 trust-ad" >> "${resolv_file}"
  echo "multi-tailnet" > /run/tstail/dns-configured
}

teardown_dns() {
  if [[ ! -f /run/tstail/dns-configured ]]; then
    return 0
  fi

  local netns_dir="/etc/netns/${NS}"
  local resolv_file="${netns_dir}/resolv.conf"

  rm -f "${resolv_file}" /run/tstail/dns-configured
  rmdir "${netns_dir}" 2>/dev/null || true
}

setup_iptables() {
  if ! cmd_exists iptables; then
    err "iptables not found. Install iptables or choose nftables/ufw."
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

teardown_iptables() {
  if ! cmd_exists iptables; then
    return 0
  fi

  iptables -D FORWARD -i "${HOST_IFACE}" -o "${VETH_HOST}" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -o "${HOST_IFACE}" -i "${VETH_HOST}" -j ACCEPT 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s "${VETH_NET}" -o "${HOST_IFACE}" -j MASQUERADE 2>/dev/null || true

  ip netns exec "${NS}" iptables -t nat -D POSTROUTING -s "${VETH_NET}" -o "${TUN}" -j MASQUERADE 2>/dev/null || true
}

nft_ensure_table_chain() {
  local table="$1"
  local chain="$2"
  local type="$3"
  local hook="$4"
  local prio="$5"

  nft list table inet "${table}" >/dev/null 2>&1 || nft add table inet "${table}"

  if ! nft list chain inet "${table}" "${chain}" >/dev/null 2>&1; then
    nft add chain inet "${table}" "${chain}" "{ type ${type} hook ${hook} priority ${prio}; }"
  fi
}

nft_add_rule_once() {
  local table="$1"
  local chain="$2"
  local rule="$3"

  if ! nft list chain inet "${table}" "${chain}" | grep -F -- "${rule}" >/dev/null 2>&1; then
    nft add rule inet "${table}" "${chain}" ${rule}
  fi
}

setup_nftables() {
  if ! cmd_exists nft; then
    err "nft not found. Install nftables or choose iptables/ufw."
    exit 1
  fi

  nft_ensure_table_chain "multi_tailnet" "forward" "filter" "forward" 0
  nft_ensure_table_chain "multi_tailnet" "postrouting" "nat" "postrouting" 100

  nft_add_rule_once "multi_tailnet" "forward" "iifname \"${HOST_IFACE}\" oifname \"${VETH_HOST}\" accept"
  nft_add_rule_once "multi_tailnet" "forward" "iifname \"${VETH_HOST}\" oifname \"${HOST_IFACE}\" accept"
  nft_add_rule_once "multi_tailnet" "postrouting" "ip saddr ${VETH_NET} oifname \"${HOST_IFACE}\" masquerade"

  ip netns exec "${NS}" nft list table inet multi_tailnet >/dev/null 2>&1 || \
    ip netns exec "${NS}" nft add table inet multi_tailnet
  if ! ip netns exec "${NS}" nft list chain inet multi_tailnet postrouting >/dev/null 2>&1; then
    ip netns exec "${NS}" nft add chain inet multi_tailnet postrouting "{ type nat hook postrouting priority 100; }"
  fi
  if ! ip netns exec "${NS}" nft list chain inet multi_tailnet postrouting | grep -F -- "ip saddr ${VETH_NET} oifname \"${TUN}\" masquerade" >/dev/null 2>&1; then
    ip netns exec "${NS}" nft add rule inet multi_tailnet postrouting ip saddr "${VETH_NET}" oifname "${TUN}" masquerade
  fi
}

teardown_nftables() {
  if ! cmd_exists nft; then
    return 0
  fi

  nft delete table inet multi_tailnet >/dev/null 2>&1 || true
  ip netns exec "${NS}" nft delete table inet multi_tailnet >/dev/null 2>&1 || true
}

ufw_add_nat_block() {
  local rules_file="/etc/ufw/before.rules"
  local marker_begin="# multi-tailnet begin"
  local marker_end="# multi-tailnet end"

  if ! grep -qF "${marker_begin}" "${rules_file}"; then
    awk -v begin="${marker_begin}" -v end="${marker_end}" -v net="${VETH_NET}" -v iface="${HOST_IFACE}" '
      BEGIN { in_nat=0 }
      $0 ~ /^\*nat/ { in_nat=1 }
      in_nat && $0 ~ /^COMMIT/ {
        print begin
        print "-A POSTROUTING -s " net " -o " iface " -j MASQUERADE"
        print end
        in_nat=0
      }
      { print }
    ' "${rules_file}" > "${rules_file}.tmp"
    mv "${rules_file}.tmp" "${rules_file}"
  fi
}

ufw_remove_nat_block() {
  local rules_file="/etc/ufw/before.rules"
  local marker_begin="# multi-tailnet begin"
  local marker_end="# multi-tailnet end"

  if grep -qF "${marker_begin}" "${rules_file}"; then
    awk -v begin="${marker_begin}" -v end="${marker_end}" '
      $0 == begin { skip=1; next }
      $0 == end { skip=0; next }
      !skip { print }
    ' "${rules_file}" > "${rules_file}.tmp"
    mv "${rules_file}.tmp" "${rules_file}"
  fi
}

setup_ufw() {
  if ! cmd_exists ufw; then
    err "ufw not found. Install ufw or choose nftables/iptables."
    exit 1
  fi

  ufw route allow in on "${HOST_IFACE}" out on "${VETH_HOST}" >/dev/null 2>&1 || true
  ufw route allow in on "${VETH_HOST}" out on "${HOST_IFACE}" >/dev/null 2>&1 || true

  ufw_add_nat_block

  ufw reload >/dev/null 2>&1 || true
}

teardown_ufw() {
  if ! cmd_exists ufw; then
    return 0
  fi

  ufw --force delete route allow in on "${HOST_IFACE}" out on "${VETH_HOST}" >/dev/null 2>&1 || true
  ufw --force delete route allow in on "${VETH_HOST}" out on "${HOST_IFACE}" >/dev/null 2>&1 || true

  ufw_remove_nat_block
  ufw reload >/dev/null 2>&1 || true
}

setup_firewall() {
  ensure_run_dir
  detect_firewall
  echo "${FIREWALL}" > /run/tstail/firewall-backend
  case "${FIREWALL}" in
    iptables)
      setup_iptables
      ;;
    nftables)
      setup_nftables
      ;;
    ufw)
      setup_ufw
      ;;
    *)
      err "Unsupported FIREWALL backend: ${FIREWALL}"
      exit 1
      ;;
  esac
}

teardown_firewall() {
  if [[ -f /run/tstail/firewall-backend ]]; then
    FIREWALL="$(cat /run/tstail/firewall-backend)"
  else
    detect_firewall
  fi

  case "${FIREWALL}" in
    iptables)
      teardown_iptables
      ;;
    nftables)
      teardown_nftables
      ;;
    ufw)
      teardown_ufw
      ;;
    *)
      return 0
      ;;
  esac
}

start_tailscaled_background() {
  mkdir -p "${STATE_DIR}" /run/tstail
  ip netns exec "${NS}" "${TAILSCALE_BIN}" \
    -tun "${TUN}" \
    --socket "${SOCKET}" \
    --state "${STATE_DIR}/tstail.state" \
    --statedir "${STATE_DIR}" \
    >/var/log/tstail.log 2>&1 &
  echo $! > /run/tstail/tstail.pid
}

run_tailscaled_foreground() {
  mkdir -p "${STATE_DIR}" /run/tstail
  exec ip netns exec "${NS}" "${TAILSCALE_BIN}" \
    -tun "${TUN}" \
    --socket "${SOCKET}" \
    --state "${STATE_DIR}/tstail.state" \
    --statedir "${STATE_DIR}"
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
  teardown_firewall
  teardown_dns
  rm -f /run/tstail/firewall-backend 2>/dev/null || true
  for subnet in "${WORK_SUBNETS[@]}"; do
    ip route del "${subnet}" 2>/dev/null || true
  done
  ip link del "${VETH_HOST}" 2>/dev/null || true
  ip netns del "${NS}" 2>/dev/null || true
}

usage() {
  echo "Usage: $0 {setup|run|up|login|down}"
}

main() {
  require_root
  case "${1:-}" in
    setup)
      setup_netns
      setup_routes
      setup_dns
      setup_firewall
      ;;
    run)
      run_tailscaled_foreground
      ;;
    up)
      setup_netns
      setup_routes
      setup_dns
      setup_firewall
      start_tailscaled_background
      log "Second tailscaled started. Run: $0 login"
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
