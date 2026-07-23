# Dot enclosure — CNC-style thin round head

Inspired by premium machined “digital badge” pucks: **thin round aluminum**, chamfered face, display in front, **HDMI + USB-C through the back** under the driver board. Pi Zero stays remote.

```
                    front (visible)
        ┌──── chamfered bezel / AA window ────┐
        │         round IPS glass             │
        │──────────── FPC ────────────────────│
        │      UEDX6911 board (flat)          │
        │   connectors face REAR ↓            │
        │  ┌────┐        ┌──────┐             │
        │  │USB │        │ HDMI │  cutouts    │
        └──┴────┴────────┴──────┴─────────────┘
                    back
              cables → Pi Zero (remote)
```

## Target look (from your reference)

- Round billet / turned OD, **chamfered outer rim**
- Very thin stack (goal **16–20 mm** overall after measure)
- Polished or anodized aluminum (prototype: black PETG)
- Rear face mostly clean; ports + optional center mount boss
- Not a side-exit brick — **ports on the back**, under the board

## Parts (catalog baselines — verify with calipers)

| Part | Outline | Notes |
|------|---------|--------|
| Display | 73.03 × 76.48 mm, AA ⌀ 70.13 | 2.8″ 480×480 |
| UEDX6911 | ~66 × 58 mm PCB | Measure connector height toward rear |
| Ports | HDMI Type A + USB-C | Face the back cover; short right-angle adapters if needed |

## Stack (front → back)

1. Bezel lip / chamfer (brand face, black ring around AA)  
2. Glass + LCD module pocket  
3. FPC fold (≥ 3 mm bend radius)  
4. Driver PCB, copper toward rear  
5. Back plate with **HDMI + USB-C windows** aligned to connectors  
6. Optional rear boss (M4 / 17 mm ball / pin mount)

## CAD

Parametric model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

| `part` | Export |
|--------|--------|
| `front` | Face + glass pocket + chamfer |
| `back` | Board pocket + rear HDMI/USB cutouts + mount boss |
| `preview` | Assembly ghost |

Key parameters: `outer_d`, `aa_d`, `hdmi_*`, `usbc_*`, `board_*`, `overall_z`.

## CNC path (production intent)

Same process language as your reference reel:

1. **Lathe / turn** outer Ø + front chamfer + face flat  
2. **Mill** glass pocket (front) and board pocket (back)  
3. **Mill** HDMI + USB-C rectangles through back wall  
4. **Drill** M2 screw circle + optional center mount hole  
5. Deburr → bead-blast / polish → anodize black (preferred for Dot)

Fixture: soft jaws or vacuum for thin discs; keep wall ≥ 1.2 mm aluminum.

## Prototype (print before metal)

1. Measure glass, board, **rear connector stick-out** (critical for `overall_z`).  
2. Edit `.scad` → export front/back STL.  
3. Print black matte PETG → dry-fit.  
4. Only then cut aluminum.

## Mounting

- Center rear boss: M4 threaded insert or 17 mm ball socket  
- Or flat back + 3M VHB for grille  
- Keep Pi + buck remote ([car-power.md](car-power.md))

## Checklist

- [ ] Calipers: glass, board, HDMI height, USB-C height, FPC side  
- [ ] Confirm connector face = toward back (or order/use right-angle plugs)  
- [ ] PETG v1 dry-fit  
- [ ] CNC aluminum v1  
- [ ] Anodize + foam light-seal under bezel  
