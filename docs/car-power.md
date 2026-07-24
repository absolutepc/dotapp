# Car installation — power and mounting

## 12V → 5V power

| Component | Spec |
|-----------|------|
| Buck converter | 12V→5V, **3A** minimum |
| Fuse | 5A inline on +12V |
| Input cap | 1000–2200 µF electrolytic |
| Trigger | ACC / ignition relay |

### Wiring

```
Car +12V (ACC) ── fuse 5A ── relay ── buck IN+
Car GND ───────────────────────────── buck IN-
buck OUT+ 5V ── Pi PWR micro-USB
buck OUT+ 5V ── UEDX6911 USB-C (optional second feed)
buck OUT- ──── common GND with Pi and display board
```

### Notes

- Use a relay or delayed-off module so the Pi shuts down cleanly when the engine stops (optional UPS HAT or script on GPIO).
- Verify voltage under cranking: buck should hold ≥4.8V at 2A load.
- Total draw: Pi Zero 2W ~0.7A + display ~0.3A peak ≈ **1A typical, 2A peak**.

## System split (head + remote box)

Same pattern as the reference digital emblem: thin visible **head**, separate **power/control** box.

| Unit | What | Power |
|------|------|--------|
| Head | Display + UEDX6911 in CNC puck | USB-C 5V/3A into board, or feed from remote buck |
| Remote box | Pi Zero 2W + buck / harness | 12V ACC → buck 5V (below) |

## Mounting checklist

- [ ] Round Dot **head** enclosure (display + UEDX6911) — see [enclosure.md](enclosure.md)
- [ ] Pi Zero remote box (glovebox); HDMI + USB strain relief into rear head ports
- [ ] FPC ribbon strain relief — no sharp bends (<3 mm radius)
- [ ] Mount: 3M VHB and/or ball socket on back of head
- [ ] Buck converter not touching plastic — mount on metal/bracket for heat sink

## Acceptance tests in vehicle

1. Cold start: logo appears within 30 s of ACC ON.
2. 30 min idle animation @ 60 fps: Pi CPU temp < 70°C ( `vcgencmd measure_temp` ).
3. Engine crank: no reboot (monitor `dmesg`).
4. iPhone connects to AP within 5 m of grille.
5. Switch logo from app while engine running.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Pi reboots on start | Larger input cap; higher-current buck |
| Display flicker | Shorter HDMI cable; check 5V at USB-C ≥4.8V |
| Wi-Fi unreachable in car | External antenna on Pi Zero 2W; channel 6 AP |
| Overheat in summer | Vent holes; reduce backlight via driver board if available |
