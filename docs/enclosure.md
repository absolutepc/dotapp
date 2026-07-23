# Dot enclosure — CNC-style thin round head

Inspired by the machined “digital badge” process: round billet body, **printed/machined front bezel** around the glass, **HDMI + USB-C through the back** under the driver board. Pi Zero stays remote.

```
                    front (visible)
        ┌──── black bezel ring (printed) ─────┐
        │         round IPS glass / AA        │
        │──────────── FPC ────────────────────│
        │      UEDX6911 board (flat)          │
        │   connectors face REAR ↓            │
        │  ┌────┐        ┌──────┐             │
        │  │USB │        │ HDMI │  cutouts    │
        └──┴────┴────────┴──────┴─────────────┘
                    back
              cables → Pi Zero (remote)
```

## Front part (your reference frame)

The black circular face with the dark round screen is a **separate front piece** — in the reference project it was printed on a machine (FDM/SLA or plastic CNC), not the aluminum rear stack.

Dot mirrors that split:

| Piece | Role | Prototype | Production |
|-------|------|-----------|------------|
| **Front** | Matte black bezel + AA window + glass pocket | PETG / resin print | Optional: CNC plastic or anodized Al + black lip |
| **Back** | Board pocket, rear HDMI/USB, mount boss | PETG print | Aluminum CNC (lathe + mill) |

Target front look:

- Thin **matte black** ring around the active area (not a thick phone-style chin)
- Glass sits in a pocket behind a short lip (`bezel_lip`)
- Outer rim can keep a light chamfer so the puck reads thin in hand
- No ports on the front — only AA + bezel

## Target overall look

- Round OD, slim stack (goal **16–20 mm** after measure)
- Front: black printed bezel (reference)
- Body/back: polished or anodized aluminum when ready
- Ports + optional center mount on the **rear**, under the board

## Parts (catalog baselines — verify with calipers)

| Part | Outline | Notes |
|------|---------|--------|
| Display | 73.03 × 76.48 mm, AA ⌀ 70.13 | 2.8″ 480×480 |
| UEDX6911 | ~66 × 58 mm PCB | Measure connector height toward rear |
| Ports | HDMI Type A + USB-C | Face the back cover; short right-angle adapters if needed |

## Stack (front → back)

1. **Front bezel** (printed) — AA window + glass lip  
2. Glass + LCD module  
3. FPC fold (≥ 3 mm bend radius)  
4. Driver PCB, connectors toward rear  
5. **Back** — HDMI + USB-C windows under the board  
6. Optional rear boss (M4 / 17 mm ball / pin mount)

## CAD

Parametric model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

| `part` | Export |
|--------|--------|
| `front` | Black bezel face + glass pocket (print this first) |
| `back` | Board pocket + rear HDMI/USB + mount boss |
| `preview` | Assembly ghost |

Key parameters: `outer_d`, `aa_d`, `bezel_lip`, `hdmi_*`, `usbc_*`, `board_*`, `overall_z`.

## Prototype path (match reference workflow)

1. Measure glass OD, AA, module thickness → set `aa_d`, `inner_glass_d`, `bezel_lip`.  
2. Export **`part = "front"`** → print matte black PETG/resin → dry-fit glass.  
3. Measure board + rear connector stick-out → set `overall_z`, port XY.  
4. Export **`part = "back"`** → print → dry-fit board + cables.  
5. Only then CNC aluminum back (and optional metal front).

## CNC path (metal back / production)

1. Lathe outer Ø + face flats  
2. Mill board pocket  
3. Mill HDMI + USB-C through back wall  
4. Drill M2 screw circle + mount hole  
5. Deburr → finish → anodize  

Front can stay printed black even with a metal back (same as the reference badge face).

## Mounting

- Center rear boss: M4 insert or 17 mm ball  
- Or flat back + 3M VHB  
- Pi + buck remote ([car-power.md](car-power.md))

## Checklist

- [ ] Calipers: glass, AA, module Z, board, HDMI/USB stick-out  
- [ ] Print front bezel → glass fit + black ring look  
- [ ] Print back → ports under board  
- [ ] Confirm connector face = toward back  
- [ ] Optional CNC aluminum back  
- [ ] Foam light-seal under bezel lip  
