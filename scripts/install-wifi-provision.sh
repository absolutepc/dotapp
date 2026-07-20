#!/usr/bin/env bash
# Install Wi-Fi provisioning (setup AP → phone hotspot client).
# Run: sudo bash scripts/install-wifi-provision.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="/var/lib/dot"
PI_USER="${SUDO_USER:-${1:-mercy119}}"

# Migrate legacy data dir
if [[ -d /var/lib/bmw-logo && ! -d "${STATE_DIR}" ]]; then
  mv /var/lib/bmw-logo "${STATE_DIR}"
fi
mkdir -p "${STATE_DIR}"

# Remove legacy helpers/units
systemctl disable --now bmw-wifi-apply.path bmw-wifi-apply.service 2>/dev/null || true
rm -f /etc/systemd/system/bmw-wifi-apply.path /etc/systemd/system/bmw-wifi-apply.service
rm -f /usr/local/sbin/bmw-wifi-apply /usr/local/sbin/bmw-enter-setup-ap /etc/sudoers.d/bmw-wifi-apply

install -m 755 "${ROOT}/scripts/wifi-apply-client.sh" /usr/local/sbin/dot-wifi-apply
install -m 755 "${ROOT}/scripts/enter-setup-ap.sh" /usr/local/sbin/dot-enter-setup-ap

install -m 644 "${ROOT}/firmware/systemd/dot-wifi-apply.service" /etc/systemd/system/dot-wifi-apply.service
install -m 644 "${ROOT}/firmware/systemd/dot-wifi-apply.path" /etc/systemd/system/dot-wifi-apply.path

# Passwordless apply for the service account (API runs as PI_USER)
cat >/etc/sudoers.d/dot-wifi-apply <<EOF
${PI_USER} ALL=(root) NOPASSWD: /usr/local/sbin/dot-wifi-apply
${PI_USER} ALL=(root) NOPASSWD: /usr/local/sbin/dot-enter-setup-ap
${PI_USER} ALL=(root) NOPASSWD: /bin/systemctl start dot-wifi-apply.service
EOF
chmod 440 /etc/sudoers.d/dot-wifi-apply

chown -R "${PI_USER}:${PI_USER}" "${STATE_DIR}"
chmod 755 "${STATE_DIR}"
touch "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"
chown "${PI_USER}:${PI_USER}" "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"
chmod 664 "${STATE_DIR}/wifi-status.json" "${STATE_DIR}/wifi-mode.json"

systemctl daemon-reload
systemctl enable --now dot-wifi-apply.path

echo "Wi-Fi provisioning installed for user: ${PI_USER}"
echo "  Start setup AP:  sudo dot-enter-setup-ap"
echo "  Portal:          http://192.168.4.1/setup/"
echo "  Status API:      http://127.0.0.1:8080/api/wifi/status"
