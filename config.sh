# multi-tailnet config
#
# Copy and edit this file, or override values via environment variables.

# Namespace and veth configuration
NS="tailns"
VETH_HOST="veth-tail0"
VETH_NS="veth-tail1"
VETH_NET="192.168.101.0/24"
VETH_HOST_IP="192.168.101.1/24"
VETH_NS_IP="192.168.101.2/24"

# Tailscale binaries
TAILSCALE_BIN="/usr/sbin/tailscaled"
TAILSCALE_CLI="/usr/bin/tailscale"

# State and socket locations
STATE_DIR="/var/lib/tstail"
SOCKET="/run/tstail/tstail.socket"
TUN="tailscale0"

# Host interface that connects to the Internet (adjust)
HOST_IFACE="eth0"

# Subnets you want to reach via the SECOND tailnet (space-separated)
WORK_SUBNETS=("10.10.0.0/16" "10.20.0.0/16")

# Optional: per-namespace DNS servers (space-separated). Leave empty to skip.
DNS_SERVERS=()

# Firewall backend: auto | iptables | nftables | ufw
FIREWALL="auto"
