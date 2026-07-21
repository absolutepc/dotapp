# Wi-Fi: iPhone hotspot (recommended) + one-time setup AP

## Why

If the phone joins a Wi-Fi AP on the Pi, it often **loses mobile internet**.  
In the car you also do not carry a home router.

**Recommended:** Pi joins the **iPhone Personal Hotspot**. The phone keeps cellular data; the app talks to the Pi on the hotspot LAN.

## First connect (no Pi terminal) — step by step

iPhone **cannot** stay on Dot-Setup Wi‑Fi and run Personal Hotspot at the same time.  
Do one step at a time (the app wizard enforces this):

After Wi-Fi helpers are installed once (`install-wifi-provision.sh` / `install-pi.sh`):

1. Pi **automatically** opens Wi-Fi `Dot-Setup-XXXX` on boot until a phone hotspot is saved  
   (password default: `dotsetup1`)
2. **Step 1:** On the iPhone join `Dot-Setup-…` — do **not** enable Personal Hotspot yet
3. Open the **Dot** app → **Настройка Wi‑Fi (по шагам)**
4. **Step 2:** Look up hotspot **name + password** in Settings → Personal Hotspot (leave the toggle **off**), enter them in the app, tap **Отправить на Dot**
5. **Step 3:** Leave Dot-Setup Wi‑Fi, **then** enable Personal Hotspot; keep the phone unlocked ~10–15s
6. **Step 4:** Tap **Найти Dot** — gallery opens when Dot is on the hotspot LAN

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
- While in setup AP, the round HDMI shows SSID / password / QR (`setup-info` frame).
- Day-to-day discovery also tries `dot.local` / `<hostname>.local` (Avahi) plus the hotspot LAN.
- Join helper (`dot-wifi-join`) is **anti-flap**: if already connected with IP, it does not rescan / modify / reconnect.
- Apply uses a lock so API + systemd cannot start two joins at once.
- Tip: leave the iPhone unlocked; enable **Maximize Compatibility** on Personal Hotspot if Dot keeps dropping.
- App wizard saves credentials first (`apply_now: false`), then `POST /api/wifi/connect-hotspot` starts a **single** join after the user is ready.
- Legacy always-on AP: `scripts/setup-wifi-ap.sh` (phone loses internet while connected).
