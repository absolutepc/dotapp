# Wiring: Raspberry Pi Zero 2W + UEDX6911-HDMI V2.0

## Components

| Part | Model |
|------|-------|
| SBC | Raspberry Pi Zero 2 W |
| Driver board | UEDX6911-HDMI V2.0 (LT6911C HDMI→MIPI) |
| Display | Round 2.8" 480×480 IPS, ST7701S |
| Cables | Mini-HDMI→HDMI, Micro-USB→USB-C |

## Connection diagram

```
Pi Zero 2W                    UEDX6911-HDMI V2.0
──────────                    ───────────────────
mini-HDMI ──── HDMI cable ──► HDMI IN
micro-USB OTG ── USB cable ──► USB-C (power + touch)
micro-USB PWR ◄── 5V 2.5A ──── Power supply
GND (common) ───────────────── GND

FPC ribbon: round display ────► 30-pin MIPI connector
```

## Steps

1. Connect FPC ribbon from round display to the 30-pin connector on UEDX6911 (gold contacts down, lock tab closed).
2. Connect Mini-HDMI on Pi to HDMI on driver board.
3. Connect Pi OTG micro-USB to driver board USB-C (powers the board and enables touch).
4. Power Pi via PWR micro-USB with a 5V 2.5A supply.
5. Copy [`config.txt.example`](config.txt.example) settings into `/boot/firmware/config.txt`.
6. Boot Pi and run the smoke test:

```bash
sudo apt install -y fbset fbi
tvservice -s
fbi -T 1 -a /opt/bmw-logo/assets/bmw/default.png
```

## Smoke test script

From the repo root on the Pi:

```bash
sudo bash scripts/hardware-test.sh
```

Expected: `480x480 @ 60Hz` reported by `tvservice`, test image visible on the round display.
