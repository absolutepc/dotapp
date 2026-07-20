# Wi-Fi: iPhone hotspot (recommended) + one-time setup AP

## Why

If the phone joins a Wi-Fi AP on the Pi, it often **loses mobile internet**.  
In the car you also do not carry a home router.

**Recommended:** Pi joins the **iPhone Personal Hotspot**. The phone keeps cellular data; the app talks to the Pi on the hotspot LAN.

## First connect (no Pi terminal)

After Wi-Fi helpers are installed once (`install-wifi-provision.sh` / `install-pi.sh`):

1. Pi **automatically** opens Wi-Fi `Dot-Setup-XXXX` on boot until a phone hotspot is saved  
   (password default: `dotsetup1`)
2. On the iPhone: join `Dot-Setup-…`
3. Open the **Dot** app — it should find `192.168.4.1` and open **Настройка Wi‑Fi**
4. Enter **Personal Hotspot** name + password (Settings → Personal Hotspot / Режим модема)
5. Tap **Сохранить и подключить**
6. Leave Dot-Setup, **enable Personal Hotspot**, wait a few seconds
7. In the app tap **Найти Pi в сети модема** / **Найти автоматически**

You should **not** need SSH or `curl` on the Pi for a normal first connect.

Safari is optional; the same form still exists at `http://192.168.4.1/setup/`.

## Day-to-day

1. Enable **Personal Hotspot** on the iPhone  
2. Wait a few seconds for the Pi to join (`dot-wifi-boot` + NM autoconnect)  
3. Open the app → **Найти автоматически** (or use the Pi IP from `GET /api/wifi/status`)

## One-time install on the Pi (admin)

```bash
cd ~/dotapp
sudo bash scripts/install-wifi-provision.sh
# If packages hostapd/dnsmasq were already present, setup AP starts immediately.
# Otherwise reboot once after install.
```

Manual fallback (only if boot service did not start AP):

```bash
sudo systemctl start dot-wifi-boot
# or: sudo dot-enter-setup-ap
```

## Commands

| Action | Command |
|--------|---------|
| Install helpers + enable boot AP | `sudo bash scripts/install-wifi-provision.sh` |
| Enter setup AP again | `sudo dot-enter-setup-ap` or `POST /api/wifi/reprovision` |
| Wi-Fi status | `curl -s http://127.0.0.1:8080/api/wifi/status` |
| Force re-apply | `sudo dot-wifi-apply` (needs `wifi-request.json`) |

## Files

- Request (API → root helper): `/var/lib/dot/wifi-request.json`
- Status: `/var/lib/dot/wifi-status.json`
- Saved SSID (no password): `/var/lib/dot/wifi-client.json`
- NM profile name: `dot-phone-hotspot`
- Boot unit: `dot-wifi-boot.service`

## Notes

- Hotspot password must be at least **8 characters** (WPA).
- If you change the iPhone hotspot password, re-enter setup AP (app reprovision or `sudo dot-enter-setup-ap`) and save again.
- Legacy always-on AP: `scripts/setup-wifi-ap.sh` (phone loses internet while connected).
