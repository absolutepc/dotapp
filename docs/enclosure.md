# Dot enclosure — thin head (display + HDMI board)

Goal: a **thin round housing** for the **2.8″ round IPS** and **UEDX6911-HDMI** driver board.  
Raspberry Pi Zero 2W stays **remote** (glovebox / under dash) so the visible puck stays slim.

```
        ┌──────── front bezel (thin lip) ────────┐
        │     ⌀ ~70 mm active / glass ~73 mm     │
        │────────── display module ──────────────│
        │     FPC fold (gentle radius ≥ 3 mm)    │
        │──────── UEDX6911-HDMI (~66×58 mm) ─────│
        │     HDMI + USB-C exit at edge          │
        └──────────── back cover ────────────────┘
                         │
              slim HDMI + USB cables → Pi Zero
```

## Parts (measured / catalog)

| Part | Typical outline | Notes |
|------|-----------------|--------|
| Display | **73.03 × 76.48 mm** outer, **⌀ 70.13 mm** AA | VIEWE / UEDX48480028-Round-HMD family |
| Driver | **66 × 58 mm** PCB (UEDX6911) | Confirm with calipers — revisions differ |
| Stack target | **≤ 20–22 mm** overall depth | Side cable exits, not rear HDMI |

**Measure your boards** before printing: length, width, thickness, connector overhang, FPC exit side.

## Design principles

1. **Brand face** — round aperture matches AA; bezel lip ~1.5–2.5 mm of pure black plastic so “IPS grey” meets a dark ring (helps the bezel blend).
2. **Thin** — Pi not inside the head; only display + driver.
3. **Serviceable** — snap or 3–4 M2 screws; open without destroying FPC.
4. **Strain relief** — cable clamp for HDMI + USB; FPC cannot bend sharper than ~3 mm radius.
5. **Heat** — small rear vents or metal backplate behind LT6911 if sealed in a hot car.
6. **Mount** — flat back with 3M VHB / M4 boss / 17 mm ball socket (optional).

## Proposed dimensions (v1 parametric)

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `outer_d` | 82 mm | Outer diameter of round shell |
| `inner_glass_d` | 73.5 mm | Pocket for glass/module |
| `aa_d` | 70.2 mm | Visible aperture |
| `bezel_lip` | 2.0 mm | Black ring in front of glass |
| `board_w` / `board_h` | 66 / 58 mm | Driver pocket |
| `board_clear_z` | 9 mm | Height for PCB + connectors |
| `wall` | 1.6 mm | Shell wall (PETG/ABS) |
| `target_z` | ~20 mm | Overall thickness goal |

CAD: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad) (OpenSCAD → STL).

## BOM (enclosure)

- Front ring + back cover (3D print PETG, or CNC POM/aluminum later)
- 4× M2×6 screws + brass inserts (optional)
- Cable gland or printed strain clamp
- 3M VHB ring for glass (if module not friction-fit)
- Optional: 0.5 mm black foam between glass and bezel (kills light leak)

## Print / prototype plan

1. Caliper-measure display + UEDX6911 + connector stick-out.  
2. Edit parameters at top of `dot_case.scad`.  
3. Print **front** in black matte PETG (0.2 mm layers).  
4. Print **back** with vents.  
5. Dry-fit → adjust `board_*` and `inner_glass_d`.  
6. In car: VHB or ball mount on back.

## Electrical (unchanged)

See [wiring.md](wiring.md) and [car-power.md](car-power.md).  
Head only needs: HDMI in, USB-C (power/touch), optional 5V if you split power.

## Next hardware steps

- [ ] User caliper sheet filled (photo + numbers)  
- [ ] v1 STL printed and dry-fit  
- [ ] Decide mount: adhesive vs ball  
- [ ] Optional aluminum back for heat / premium feel  
