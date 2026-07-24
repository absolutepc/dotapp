#!/usr/bin/env bash
# Install Wi-Fi provisioning (setup AP → phone hotspot client).
# Run: sudo bash scripts/install-wifi-provision.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="/var/lib/bmw-logo"
PI_USER="${SUDO_USER:-${1:-mercy119}}"
mkdir -p "${STATE_DIR}"

install -m 755 "${ROOT}/scripts/wifi-apply-client.sh" /usr/local/sbin/bmw-wifi-apply
install -m 755 "${ROOT}/scripts/enter-setup-ap.sh" /usr/local/sbin/bmw-enter-setup-ap

install -m 644 "${ROOT}/firmware/systemd/bmw-wifi-apply.service" /etc/systemd/system/bmw-wifi-apply.service
install -m 644 "${ROOT}/firmware/systemd/bmw-wifi-apply.path" /etc/systemd/system/bmw-wifi-apply.path

# Passwordless apply for the service account (API runs as PI_USER)
cat >/etc/sudoers.d/bmw-wifi-apply <<EOF
${PI_USER} ALL=(root) NOPASSWD: /usr/local/sbin/bmw-wifi-apply
${PI_USER} ALL=(root) NOPASSWD: /usr/local/sbin/bmw-enter-setup-ap
${PI_USER} ALL=(root) NOPASSWD: /bin/systemctl start bmw-wifi-apply.service
EOF
chmod 440 /etc/sudoers.d/bmw-wifi-apply

chown -R "${PI_USER}:${PI_USER}" "${STATE_DIR}"
chmod 755 "${STATE_DIR}"
touch "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"
chown "${PI_USER}:${PI_USER}" "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"
chmod 664 "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"

systemctl daemon-reload
systemctl enable --now bmw-wifi-apply.path

echo "Wi-Fi provisioning installed for user: ${PI_USER}"
echo "  Start setup AP:  sudo bmw-enter-setup-ap"
echo "  Portal:          http://192.168.4.1/setup/"
echo "  Status API:      http://127.0.0.1:8080/api/wifi/status"
