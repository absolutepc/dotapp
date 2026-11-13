#!/usr/bin/env bash
# Boot straight to Dot logo: no desktop, soft-quiet console.
# Run on Pi: sudo bash scripts/setup-kiosk-boot.sh [username]
#
# Safe by default: does NOT use fbcon=map:99 (that black-screened this panel).
set -euo pipefail

PI_USER="${1:-${SUDO_USER:-pi}}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

_has_runtime() {
  local root="$1"
  [[ -d "${root}/firmware" ]] || return 1
  [[ -x "${root}/venv/bin/python" || -x "${root}/.venv/bin/python" ]] || return 1
  [[ -x "${root}/venv/bin/uvicorn" || -x "${root}/.venv/bin/uvicorn" ]] || return 1
  return 0
}

if [[ -n "${DOT_INSTALL:-}" ]]; then
  INSTALL_DIR="${DOT_INSTALL}"
elif _has_runtime "${REPO_ROOT}"; then
  INSTALL_DIR="${REPO_ROOT}"
elif _has_runtime /opt/dot; then
  INSTALL_DIR="/opt/dot"
elif [[ -d "${REPO_ROOT}/firmware" ]]; then
  INSTALL_DIR="${REPO_ROOT}"
else
  INSTALL_DIR="/opt/dot"
fi

echo "Kiosk boot setup for user: ${PI_USER}"
echo "Install dir: ${INSTALL_DIR}"

CONFIG="/boot/firmware/config.txt"
[[ -f "${CONFIG}" ]] || CONFIG="/boot/config.txt"
if [[ -f "${CONFIG}" ]]; then
  grep -qE '^[[:space:]]*disable_splash=1' "${CONFIG}" || echo "disable_splash=1" >>"${CONFIG}"
  grep -qE '^[[:space:]]*avoid_warnings=1' "${CONFIG}" || echo "avoid_warnings=1" >>"${CONFIG}"
fi

# Soft silence only
if [[ -f "${REPO_ROOT}/scripts/disable-splash.sh" ]]; then
  DOT_HARD_SILENCE=0 bash "${REPO_ROOT}/scripts/disable-splash.sh" || true
fi

# Strip dangerous hard-silence flag if present from older runs
CMDLINE="/boot/firmware/cmdline.txt"
[[ -f "${CMDLINE}" ]] || CMDLINE="/boot/cmdline.txt"
if [[ -f "${CMDLINE}" ]]; then
  python3 - "${CMDLINE}" <<'PY'
import sys
path = sys.argv[1]
tokens = open(path).read().strip().split()
tokens = [t for t in tokens if t != "fbcon=map:99" and not t.startswith("fbcon=map:")]
# Ensure a VT console exists for DRM bring-up on this panel
if not any(t.startswith("console=tty") and not t.startswith(("console=ttyS", "console=ttyAMA")) for t in tokens):
    tokens.append("console=tty3")
open(path, "w").write(" ".join(tokens) + "\n")
print("cmdline:", open(path).read().strip())
PY
fi

systemctl set-default multi-user.target
systemctl disable lightdm gdm gdm3 wayfire labwc 2>/dev/null || true
systemctl mask lightdm 2>/dev/null || true
systemctl disable getty@tty1 2>/dev/null || true
systemctl mask getty@tty1 2>/dev/null || true
for svc in plymouth-start plymouth-read-write plymouth-quit plymouth-quit-wait plymouth-reboot plymouth-halt plymouth-kexec; do
  systemctl disable "${svc}" 2>/dev/null || true
  systemctl mask "${svc}" 2>/dev/null || true
done
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_splash 1 2>/dev/null || true
fi

# Display + API units
if [[ -x "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" ]]; then
  bash "${INSTALL_DIR}/scripts/fix-systemd-paths.sh" "${PI_USER}" kiosk
else
  echo "WARNING: fix-systemd-paths.sh missing" >&2
fi

# Keep Wi‑Fi auto-join alive (kiosk must not strand the device)
if [[ -f /usr/local/sbin/dot-wifi-boot ]] || [[ -f "${INSTALL_DIR}/scripts/install-wifi-provision.sh" ]]; then
  systemctl enable NetworkManager 2>/dev/null || true
  systemctl enable dot-wifi-boot.service 2>/dev/null || true
  systemctl enable --now dot-wifi-watch.service 2>/dev/null || true
  systemctl enable --now dot-wifi-keepalive.timer 2>/dev/null || true
fi
# Preserve client role if profile exists
if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq dot-phone-hotspot; then
  echo client >/var/lib/dot/wifi-role
  rm -f /var/lib/dot/setup-ap-hold
  echo "wifi-role=client (hotspot profile present)"
fi

# Ensure HDMI 480×480 block is present (recovery may have commented it)
if [[ -x "${INSTALL_DIR}/scripts/fix-hdmi-480.sh" ]]; then
  if [[ -f "${CONFIG}" ]] && ! grep -qE '^[[:space:]]*hdmi_cvt=480[[:space:]]+480' "${CONFIG}" \
    && ! grep -qE '^[[:space:]]*hdmi_timings=480' "${CONFIG}"; then
    echo "Restoring HDMI 480×480 block…"
    bash "${INSTALL_DIR}/scripts/fix-hdmi-480.sh" || true
  fi
fi

echo ""
echo "Kiosk configured (SAFE quiet — no fbcon=map:99)."
echo "  systemctl get-default → $(systemctl get-default 2>/dev/null || true)"
echo "  wifi-role → $(tr -d '[:space:]' </var/lib/dot/wifi-role 2>/dev/null || echo '?')"
echo "  cmdline → $(tr -d '\n' <"${CMDLINE}" 2>/dev/null | head -c 200)…"
echo ""
echo "Before reboot, confirm display works NOW:"
echo "  sudo systemctl restart dot-display && show anim3"
echo "Then: sudo reboot"
echo ""
echo "If black screen returns: SD recovery cmdline WITHOUT fbcon=map:99"
