#!/usr/bin/env bash
# Configure Raspberry Pi Zero 2W as Wi-Fi AP for iPhone connection.
# Run on the Pi: sudo bash scripts/setup-wifi-ap.sh [SSID_SUFFIX] [WPA_PASSWORD]
set -euo pipefail

SSID_SUFFIX="${1:-$(hostname | tail -c 5)}"
WPA_PASS="${2:-dotapp2024}"
SSID="Dot-${SSID_SUFFIX}"
AP_IP="192.168.4.1"

echo "Setting up AP: ${SSID}"

apt-get update
apt-get install -y hostapd dnsmasq

cat >/etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=${WPA_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

# Ensure hostapd uses our config (works even if package left an empty default)
if [[ -f /etc/default/hostapd ]]; then
  if grep -q '^DAEMON_CONF=' /etc/default/hostapd; then
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  elif grep -q '^#DAEMON_CONF=' /etc/default/hostapd; then
    sed -i 's|^#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >>/etc/default/hostapd
  fi
else
  echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >/etc/default/hostapd
fi

# Avoid dnsmasq conflicting with systemd-resolved / NM stub DNS on boot
mkdir -p /etc/dnsmasq.d
cat >/etc/dnsmasq.d/dot.conf <<EOF
interface=wlan0
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/dot.local/${AP_IP}
EOF

# Bookworm/Trixie may not ship ifupdown dirs — create them
mkdir -p /etc/network/interfaces.d
cat >/etc/network/interfaces.d/wlan0 <<EOF
auto wlan0
iface wlan0 inet static
    address ${AP_IP}
    netmask 255.255.255.0
EOF

# NetworkManager must not manage wlan0, or hostapd cannot bind it
if command -v nmcli >/dev/null 2>&1; then
  mkdir -p /etc/NetworkManager/conf.d
  cat >/etc/NetworkManager/conf.d/99-dot-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
  systemctl reload NetworkManager 2>/dev/null || true
  nmcli device set wlan0 managed no 2>/dev/null || true
fi

# Assign AP address now (also useful before reboot)
ip link set wlan0 up || true
ip addr replace ${AP_IP}/24 dev wlan0 || true

systemctl unmask hostapd
systemctl enable hostapd dnsmasq
systemctl restart hostapd dnsmasq || true

echo ""
echo "AP configured."
echo "  SSID:     ${SSID}"
echo "  Password: ${WPA_PASS}"
echo "  Pi IP:    ${AP_IP}:8080"
echo ""
echo "Check: ip addr show wlan0"
echo "Then connect iPhone and open http://${AP_IP}:8080/api/status"
echo "If needed: sudo reboot"
