#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Must run as root" >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BIN="/usr/local/bin/mtail"
CONFIG_DIR="/etc/multi-tailnet"
SYSTEMD_DIR="/etc/systemd/system"
INSTANCES_DIR="${CONFIG_DIR}/instances"

if command -v mtail >/dev/null 2>&1; then
  cat <<EOF_WARN
Warning: "mtail" already exists in PATH.
This installer will overwrite: ${INSTALL_BIN}
Proceed? [y/N]
EOF_WARN
  read -r reply
  if [[ "${reply}" != "y" && "${reply}" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

install -m 0755 "${SCRIPT_DIR}/mtail" "${INSTALL_BIN}"
install -d "${CONFIG_DIR}"
install -m 0644 "${SCRIPT_DIR}/config.sh" "${CONFIG_DIR}/config.sh"
install -d "${INSTANCES_DIR}"

install -m 0644 "${SCRIPT_DIR}/systemd/mtail-setup@.service" "${SYSTEMD_DIR}/mtail-setup@.service"
install -m 0644 "${SCRIPT_DIR}/systemd/mtail@.service" "${SYSTEMD_DIR}/mtail@.service"

systemctl daemon-reload

cat <<EOF_MSG
Installed:
- ${INSTALL_BIN}
- ${CONFIG_DIR}/config.sh
- ${INSTANCES_DIR}/
- ${SYSTEMD_DIR}/mtail-setup@.service
- ${SYSTEMD_DIR}/mtail@.service

Next steps:
1) Create instance config (replace work):
  sudo cp ${CONFIG_DIR}/config.sh ${INSTANCES_DIR}/work.conf
2) Enable services:
  sudo systemctl enable --now mtail-setup@work.service
  sudo systemctl enable --now mtail@work.service
3) Login:
  sudo ${INSTALL_BIN} login --instance work
EOF_MSG
