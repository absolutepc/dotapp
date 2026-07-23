#!/usr/bin/env bash
# One-command Dot install on Raspberry Pi.
#
# Usage (from the repo checkout):
#   cd ~/dotapp
#   sudo bash scripts/bootstrap-pi.sh
#
# Options:
#   sudo bash scripts/bootstrap-pi.sh [username] [desktop|kiosk]
#   sudo bash scripts/bootstrap-pi.sh --user mercy119 --mode kiosk
#   sudo bash scripts/bootstrap-pi.sh --pull          # git pull first
#   sudo bash scripts/bootstrap-pi.sh --desktop       # keep graphical desktop
#   sudo bash scripts/bootstrap-pi.sh --no-setup-ap   # skip starting Dot-Setup now
#   sudo bash scripts/bootstrap-pi.sh --no-hdmi       # do not edit config.txt
#   sudo bash scripts/bootstrap-pi.sh --no-kiosk-boot # skip quiet kiosk boot tweaks
#
# What it does:
#   1) optional git pull
#   2) HDMI 480×480 lines in /boot/firmware/config.txt (if missing)
#   3) firmware + venv + systemd (install-pi.sh)
#   4) Wi‑Fi helpers + Setup AP / client role (install-wifi-provision.sh)
#   5) kiosk quiet boot (setup-kiosk-boot.sh) when mode=kiosk
#   6) start Dot-Setup AP for first pairing (unless --no-setup-ap)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PI_USER="${SUDO_USER:-mercy119}"
MODE="kiosk"
DO_PULL=0
DO_HDMI=1
DO_SETUP_AP=1
DO_KIOSK_BOOT=1

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# Parse args (positional + flags)
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage ;;
    --pull) DO_PULL=1; shift ;;
    --desktop) MODE="desktop"; shift ;;
    --kiosk) MODE="kiosk"; shift ;;
    --no-setup-ap) DO_SETUP_AP=0; shift ;;
    --no-hdmi) DO_HDMI=0; shift ;;
    --no-kiosk-boot) DO_KIOSK_BOOT=0; shift ;;
    --user)
      PI_USER="${2:?}"
      shift 2
      ;;
    --mode)
      MODE="${2:?}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}" "$@"

if [[ $# -ge 1 && "$1" != "" ]]; then
  PI_USER="$1"
fi
if [[ $# -ge 2 && "$2" != "" ]]; then
  MODE="$2"
fi

if [[ "${MODE}" != "desktop" && "${MODE}" != "kiosk" ]]; then
  echo "MODE must be desktop or kiosk (got: ${MODE})" >&2
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo:" >&2
  echo "  sudo bash scripts/bootstrap-pi.sh" >&2
  exit 1
fi

echo "════════════════════════════════════════"
echo " Dot one-command setup"
echo "════════════════════════════════════════"
echo "  repo:   ${ROOT}"
echo "  user:   ${PI_USER}"
echo "  mode:   ${MODE}"
echo "  pull:   ${DO_PULL}"
echo "  hdmi:   ${DO_HDMI}"
echo "  setup:  ${DO_SETUP_AP}"
echo ""

# --- 0) optional update ---
if [[ "${DO_PULL}" -eq 1 ]]; then
  if [[ -d "${ROOT}/.git" ]]; then
    echo "→ git pull…"
    # Stay on current branch; fetch + pull
    sudo -u "${PI_USER}" git -C "${ROOT}" fetch --all --prune || true
    sudo -u "${PI_USER}" git -C "${ROOT}" pull --ff-only || \
      echo "WARN: git pull failed — continuing with local tree" >&2
  else
    echo "WARN: ${ROOT} is not a git checkout — skip --pull" >&2
  fi
fi

# --- 1) HDMI config for 480×480 round panel ---
apply_hdmi_config() {
  local config="/boot/firmware/config.txt"
  [[ -f "${config}" ]] || config="/boot/config.txt"
  if [[ ! -f "${config}" ]]; then
    echo "WARN: no config.txt found — skip HDMI block" >&2
    return 0
  fi
  if grep -qE '^[[:space:]]*hdmi_cvt=480[[:space:]]+480' "${config}"; then
    echo "→ HDMI 480×480 already present in ${config}"
    return 0
  fi
  echo "→ Appending HDMI 480×480 block to ${config}"
  cp -a "${config}" "${config}.bak.dot.$(date +%Y%m%d%H%M%S)"
  cat >>"${config}" <<'EOF'

# --- Dot round 480x480 @ 60Hz (UEDX6911-HDMI) ---
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=87
hdmi_cvt=480 480 60 4 0 0 0
hdmi_drive=2
config_hdmi_boost=7
max_usb_current=1
framebuffer_width=480
framebuffer_height=480
gpu_mem=128
# --- end Dot HDMI ---
EOF
  echo "  Saved backup next to config.txt; reboot needed for HDMI timing."
}

if [[ "${DO_HDMI}" -eq 1 ]]; then
  apply_hdmi_config
fi

# --- 2) firmware + Wi‑Fi (install-pi already calls install-wifi-provision) ---
echo "→ install-pi.sh (${PI_USER}, ${MODE})…"
bash "${ROOT}/scripts/install-pi.sh" "${PI_USER}" "${MODE}"

# Ensure Wi‑Fi helpers are current even if install-pi skipped/failed soft
echo "→ install-wifi-provision.sh…"
bash "${ROOT}/scripts/install-wifi-provision.sh" "${PI_USER}"

# Extra helpers used day-to-day
if [[ -f "${ROOT}/scripts/refresh-previews.sh" ]]; then
  install -m 755 "${ROOT}/scripts/refresh-previews.sh" /usr/local/sbin/dot-refresh-previews
fi
if [[ -f "${ROOT}/scripts/dot-wifi-diagnose.sh" ]]; then
  install -m 755 "${ROOT}/scripts/dot-wifi-diagnose.sh" /usr/local/sbin/dot-wifi-diagnose
fi

# --- 3) quiet kiosk boot (car / logo-only) ---
if [[ "${MODE}" == "kiosk" && "${DO_KIOSK_BOOT}" -eq 1 ]]; then
  echo "→ setup-kiosk-boot.sh…"
  bash "${ROOT}/scripts/setup-kiosk-boot.sh" "${PI_USER}" || \
    echo "WARN: kiosk boot setup had warnings — check output above" >&2
fi

# --- 4) first-pair Setup AP ---
if [[ "${DO_SETUP_AP}" -eq 1 ]]; then
  ROLE="$(tr -d '[:space:]' </var/lib/dot/wifi-role 2>/dev/null || echo setup)"
  if [[ "${ROLE}" == "client" ]]; then
    echo "→ wifi-role=client — leave hotspot client as-is (no Setup AP)"
  else
    echo "→ starting Dot-Setup AP for first pairing…"
    echo "setup" >/var/lib/dot/wifi-role
    /usr/local/sbin/dot-enter-setup-ap || \
      systemctl start dot-wifi-boot.service || true
  fi
fi

# --- summary ---
HOSTNAME_NOW="$(hostname 2>/dev/null || echo pi)"
SSID_HINT="Dot-Setup-$(echo "${HOSTNAME_NOW}" | tr -cd 'A-Za-z0-9' | tail -c 4)"
echo ""
echo "════════════════════════════════════════"
echo " Dot setup finished"
echo "════════════════════════════════════════"
echo "  API:      systemctl status dot-api --no-pager"
echo "  Display:  systemctl status dot-display --no-pager"
echo "  Diagnose: sudo dot-wifi-diagnose"
echo ""
echo "First pairing on iPhone:"
echo "  1) Join Wi‑Fi ${SSID_HINT} (password: dotsetup1)"
echo "  2) Open the Dot app → Wi‑Fi wizard"
echo "  3) Enter Personal Hotspot name/password, then enable hotspot"
echo ""
echo "If HDMI was just added to config.txt:"
echo "  sudo reboot"
echo ""
echo "Re-run anytime after git pull:"
echo "  cd ${ROOT} && sudo bash scripts/bootstrap-pi.sh --pull"
echo ""
