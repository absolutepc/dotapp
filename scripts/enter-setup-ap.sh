#!/usr/bin/env bash
# Enter one-time Wi-Fi setup AP mode (phone joins this network to configure hotspot).
# Run: sudo bash scripts/enter-setup-ap.sh [setup_password]
set -euo pipefail

SETUP_PASS="${1:-dotsetup1}"
SSID_SUFFIX="$(hostname 2>/dev/null | tr -cd 'A-Za-z0-9' | tail -c 5)"
SSID="Dot-Setup-${SSID_SUFFIX:-Pi}"
AP_IP="192.168.4.1"
STATE_DIR="/var/lib/dot"
mkdir -p "${STATE_DIR}"

echo "Entering setup AP mode: ${SSID}"

apt-get update -qq
apt-get install -y -qq hostapd dnsmasq network-manager >/dev/null

# Stop any client connection on wlan0
systemctl stop hostapd dnsmasq 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
nmcli device disconnect wlan0 2>/dev/null || true

# Let hostapd own wlan0
mkdir -p /etc/NetworkManager/conf.d
cat >/etc/NetworkManager/conf.d/99-dot-unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
systemctl reload NetworkManager 2>/dev/null || true
nmcli device set wlan0 managed no 2>/dev/null || true

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
wpa_passphrase=${SETUP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

if [[ -f /etc/default/hostapd ]]; then
  if grep -q '^DAEMON_CONF=' /etc/default/hostapd || grep -q '^#DAEMON_CONF=' /etc/default/hostapd; then
    sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
  else
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >>/etc/default/hostapd
  fi
else
  echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >/etc/default/hostapd
fi

mkdir -p /etc/dnsmasq.d
cat >/etc/dnsmasq.d/dot.conf <<EOF
interface=wlan0
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
domain=local
address=/dot.local/${AP_IP}
address=/setup.dot/${AP_IP}
EOF

ip link set wlan0 up || true
ip addr flush dev wlan0 2>/dev/null || true
ip addr replace ${AP_IP}/24 dev wlan0 || true

systemctl unmask hostapd
systemctl enable hostapd dnsmasq
systemctl restart dnsmasq hostapd

cat >"${STATE_DIR}/wifi-mode.json" <<EOF
{"mode":"setup_ap","ssid":"${SSID}","ip":"${AP_IP}","portal":"http://${AP_IP}/setup/"}
EOF

echo ""
echo "Setup AP ready."
echo "  1. On iPhone: join Wi-Fi  ${SSID}"
echo "  2. Password:              ${SETUP_PASS}"
echo "  3. Open Safari:           http://${AP_IP}/setup/"
echo "  4. Enter your iPhone Personal Hotspot name + password"
echo ""
