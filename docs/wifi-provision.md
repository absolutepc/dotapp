# Wi-Fi: iPhone hotspot (recommended) + one-time setup AP

## Why

If the phone joins a Wi-Fi AP on the Pi, it often **loses mobile internet**.  
In the car you also do not carry a home router.

**Recommended:** Pi joins the **iPhone Personal Hotspot**. The phone keeps cellular data; the app talks to the Pi on the hotspot LAN.

## One-time setup

On the Pi:

```bash
cd ~/dotapp
sudo bash scripts/install-wifi-provision.sh
sudo bash scripts/enter-setup-ap.sh
```

Then on the iPhone:

1. Join Wi-Fi `BMW-Setup-XXXX` (password default: `bmwsetup1`)
2. Open Safari: `http://192.168.4.1/setup/`
3. Enter your **Personal Hotspot** name + password  
   (Settings → Personal Hotspot / Режим модема)
4. Tap **Save & connect**

The Pi leaves the setup network and connects to your hotspot.  
After that, day-to-day use is:

1. Enable **Personal Hotspot** on the iPhone  
2. Wait a few seconds for the Pi to join  
3. Open the app and use the Pi IP from `GET /api/wifi/status` (field `ip`)

## Commands

| Action | Command |
|--------|---------|
| Install helpers | `sudo bash scripts/install-wifi-provision.sh` |
| Enter setup AP again | `sudo bmw-enter-setup-ap` |
| Wi-Fi status | `curl -s http://127.0.0.1:8080/api/wifi/status` |
| Force re-apply | `sudo bmw-wifi-apply` (needs `wifi-request.json`) |

## Files

- Request (API → root helper): `/var/lib/bmw-logo/wifi-request.json`
- Status: `/var/lib/bmw-logo/wifi-status.json`
- Saved SSID (no password): `/var/lib/bmw-logo/wifi-client.json`
- NM profile name: `bmw-phone-hotspot`

## Notes

- Hotspot password must be at least **8 characters** (WPA).
- If you change the iPhone hotspot password, run setup AP again and re-enter it.
- Legacy always-on AP: `scripts/setup-wifi-ap.sh` (phone loses internet while connected).
