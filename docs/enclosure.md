# Dot enclosure — CNC-style thin round head

Inspired by the machined “digital badge” process: round body, **front assembly = bezel + glass**, **HDMI + USB-C through the back** under the driver board. Pi Zero stays remote.

```
                    front assembly (one unit)
        ┌──── printed bezel + bonded glass ───┐
        │         round cover glass / AA      │
        │──────── LCD + FPC ──────────────────│
        │      UEDX6911 board (flat)          │
        │   connectors face REAR ↓            │
        │  ┌────┐        ┌──────┐             │
        │  │USB │        │ HDMI │  cutouts    │
        └──┴────┴────────┴──────┴─────────────┘
                    back
              cables → Pi Zero (remote)
```

## Front assembly (your reference frame)

What you see in the hand is **not a bezel alone** — it is the **front subassembly: printed frame + cover glass** (and the round panel behind the glass). In the reference project that whole front unit was made/printed as one face of the device.

Dot uses the same split:

| Piece | Role | Prototype | Production |
|-------|------|-----------|------------|
| **Front assembly** | Bezel frame + cover glass (bonded) + LCD pocket | Print frame, seat/glue glass | Same; optional CNC frame |
| **Back** | Board pocket, rear HDMI/USB, mount boss | PETG print | Aluminum CNC |

Front assembly details:

- Matte black outer frame with thin ring around AA  
- **Cover glass** seated flush in a glue/seat shelf (part of this unit, not a loose drop-in later)  
- LCD module retained behind the glass inside the same front shell  
- Outer rim light chamfer so the puck reads thin  
- No ports on the front

## Target overall look

- Round OD, slim stack (goal **16–20 mm** after measure)
- Front: black bezel **with glass** as one face
- Body/back: polished or anodized aluminum when ready
- Ports + optional center mount on the **rear**, under the board

## Parts (catalog baselines — verify with calipers)

| Part | Outline | Notes |
|------|---------|--------|
| Cover glass / AA | AA ⌀ ~70.13; glass OD ~73+ | Measure your panel glass |
| Display module | 73.03 × 76.48 mm outline | 2.8″ 480×480 under glass |
| UEDX6911 | ~66 × 58 mm PCB | Connector height toward rear |
| Ports | HDMI Type A + USB-C | Face the back; right-angle if needed |

## Stack (front → back)

1. **Front assembly** — bezel + cover glass (bonded) + LCD in pocket  
2. FPC fold (≥ 3 mm bend radius) into the body  
3. Driver PCB in the back, connectors toward rear  
4. **Back** — HDMI + USB-C windows under the board  
5. Optional rear boss (M4 / 17 mm ball / pin mount)

## CAD

Parametric model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

| `part` | Export |
|--------|--------|
| `front` | Bezel+glass frame (glass seat, glue shelf, LCD pocket) |
| `back` | Board pocket + rear HDMI/USB + mount boss |
| `preview` | Assembly ghost |

Key parameters: `outer_d`, `aa_d`, `glass_od`, `glass_thick`, `glue_w`, `hdmi_*`, `usbc_*`, `overall_z`.

## Prototype path

1. Measure **glass OD / thickness / AA** and LCD stack → set front params.  
2. Export **`part = "front"`** → print → **bond glass into seat** → fit LCD behind it.  
3. Measure board + rear connector stick-out → ports / `overall_z`.  
4. Export **`part = "back"`** → print → dry-fit board + cables.  
5. Then CNC aluminum back if needed.

## CNC path (metal back / production)

1. Lathe outer Ø + face flats  
2. Mill board pocket  
3. Mill HDMI + USB-C through back wall  
4. Drill screw circle + mount hole  
5. Deburr → finish → anodize  

Front assembly can stay printed black + glass even with a metal back.

## Mounting

- Center rear boss: M4 insert or 17 mm ball  
- Or flat back + 3M VHB  
- Pi + buck remote ([car-power.md](car-power.md))

## Checklist

- [ ] Calipers: glass OD/Z, AA, LCD Z, board, HDMI/USB stick-out  
- [ ] Print front → glue glass → LCD behind glass  
- [ ] Print back → ports under board  
- [ ] Confirm connector face = toward back  
- [ ] Optional CNC aluminum back  
