#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must run as root" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BIN="/usr/local/bin/multi-tailnet.sh"
CONFIG_DIR="/etc/multi-tailnet"
SYSTEMD_DIR="/etc/systemd/system"

install -m 0755 "${SCRIPT_DIR}/multi-tailnet.sh" "${INSTALL_BIN}"
install -d "${CONFIG_DIR}"
install -m 0644 "${SCRIPT_DIR}/config.sh" "${CONFIG_DIR}/config.sh"

install -m 0644 "${SCRIPT_DIR}/systemd/multi-tailnet-setup.service" "${SYSTEMD_DIR}/multi-tailnet-setup.service"
install -m 0644 "${SCRIPT_DIR}/systemd/multi-tailnet.service" "${SYSTEMD_DIR}/multi-tailnet.service"

systemctl daemon-reload

cat <<EOF_MSG
Installed:
- ${INSTALL_BIN}
- ${CONFIG_DIR}/config.sh
- ${SYSTEMD_DIR}/multi-tailnet-setup.service
- ${SYSTEMD_DIR}/multi-tailnet.service

Next steps:
1) Edit ${CONFIG_DIR}/config.sh
2) Set systemd config path:
   sudo systemctl edit multi-tailnet.service
   [Service]
   Environment="MULTI_TAILNET_CONFIG=${CONFIG_DIR}/config.sh"
3) Enable services:
   sudo systemctl enable --now multi-tailnet-setup.service
   sudo systemctl enable --now multi-tailnet.service
4) Login once:
   sudo ${INSTALL_BIN} login
EOF_MSG
