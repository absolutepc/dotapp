#!/usr/bin/env bash
# Configure Raspberry Pi Zero 2W as Wi-Fi AP for iPhone connection.
# Run on the Pi: sudo bash scripts/setup-wifi-ap.sh [SSID_SUFFIX] [WPA_PASSWORD]
set -euo pipefail

SSID_SUFFIX="${1:-$(hostname | tail -c 5)}"
WPA_PASS="${2:-bmwlogo2024}"
SSID="BMW-Logo-${SSID_SUFFIX}"
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

sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

cat >/etc/dnsmasq.d/bmw-logo.conf <<EOF
interface=wlan0
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/bmw-logo.local/${AP_IP}
EOF

cat >/etc/network/interfaces.d/wlan0 <<EOF
auto wlan0
iface wlan0 inet static
    address ${AP_IP}
    netmask 255.255.255.0
EOF

systemctl unmask hostapd
systemctl enable hostapd dnsmasq

echo ""
echo "AP configured."
echo "  SSID:     ${SSID}"
echo "  Password: ${WPA_PASS}"
echo "  Pi IP:    ${AP_IP}:8080"
echo "Reboot to apply: sudo reboot"
