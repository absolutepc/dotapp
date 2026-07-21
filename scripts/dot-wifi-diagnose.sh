#!/usr/bin/env bash
# Quick diagnostics for Dot ↔ iPhone hotspot auto-join.
set -euo pipefail

echo "=== Dot Wi-Fi status ==="
echo "hostapd:     $(systemctl is-active hostapd 2>/dev/null || echo missing)"
echo "keepalive:   $(systemctl is-active dot-wifi-keepalive.timer 2>/dev/null || echo missing)"
echo "unmanaged:   $([[ -f /etc/NetworkManager/conf.d/99-dot-unmanaged.conf ]] && echo YES || echo no)"
echo
echo "=== NM connections ==="
nmcli -t -f NAME,TYPE,AUTOCONNECT connection show 2>/dev/null | grep -E 'wifi|802-11' || true
echo
if nmcli -t -f NAME connection show 2>/dev/null | grep -Fxq dot-phone-hotspot; then
  echo "=== dot-phone-hotspot ==="
  nmcli -f connection.autoconnect,connection.autoconnect-retries,802-11-wireless.ssid,802-11-wireless.powersave \
    connection show dot-phone-hotspot 2>/dev/null || true
else
  echo "NO profile dot-phone-hotspot — finish in-app Wi-Fi wizard first"
fi
echo
echo "=== device ==="
nmcli -t -f DEVICE,STATE,CONNECTION device 2>/dev/null || true
ip -4 addr show wlan0 2>/dev/null || true
echo
echo "=== recent join / keepalive ==="
tail -n 15 /var/log/dot-wifi-join.log 2>/dev/null || echo "(no join log)"
tail -n 10 /var/log/dot-wifi-keepalive.log 2>/dev/null || echo "(no keepalive log)"
echo
echo "=== status files ==="
python3 - <<'PY' 2>/dev/null || true
import json
from pathlib import Path
for name in ("wifi-status.json", "wifi-mode.json", "wifi-client.json", "wifi-pending.json"):
    p = Path("/var/lib/dot") / name
    print(f"{name}:", p.read_text().strip() if p.exists() else "(missing)")
PY
