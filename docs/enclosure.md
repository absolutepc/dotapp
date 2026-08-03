# Dot enclosure — thin round head

Learnings applied from the reference digital-badge build (CNC puck process + product architecture):

| Learned | What we do on Dot |
|---------|-------------------|
| **CNC unibody aluminum** body, not a plastic toy shell | Production = one machined puck; PETG front/back only for fit prototypes |
| **Front = bezel + glass** as one face (optical bond) | Glass bonded to panel / seated in front pocket — not a floating bezel ring |
| **Three-stage metal finish** | Chem polish → hand polish → hard coat / anodize (not raw mill marks) |
| **Head vs remote box** | Round head = display + UEDX6911; Pi + buck = remote “power/control” box |
| **Rear I/O under the board** | HDMI + USB-C exit the **back**, under the HDMI board (your requirement) |
| Chamfered thin disc + rear mount boss | Same silhouette; center boss for ball / M4 |

```
   head (unibody aluminum puck)          remote box
  ┌─ bezel + optically bonded glass ─┐   ┌─────────────┐
  │         round IPS / AA           │   │ Pi Zero 2W  │
  │──────── LCD + FPC ───────────────│   │ + buck 12→5 │
  │      UEDX6911 (flat)             │←──│ HDMI + USB  │
  │   HDMI + USB-C face REAR ↓       │   └─────────────┘
  └──────────────────────────────────┘
```

## Architecture

Same split the reference product uses (display head + separate power/control box):

| Unit | Contains | Notes |
|------|----------|--------|
| **Head** | Glass + LCD + UEDX6911 in CNC unibody | Thin, visible, grille/badge mount |
| **Remote box** | Pi Zero 2W + buck / harness | Glovebox / under dash — see [car-power.md](car-power.md) |
| **Cables** | HDMI + USB (power/data) | Short, strain-relieved into rear ports |

Power targets aligned with that pattern: **12V automotive** via buck, or stable **USB-C 5V/3A** into the head board when bench-testing.

## Front face (bezel + glass)

Not “bezel only”. The held face is:

1. Thin black AA ring (machined lip or printed insert)  
2. **Cover glass** — prefer **optical bond** to the LCD (AR coating if the panel will sit outdoors / behind grille)  
3. LCD stack retained in the front pocket of the unibody  

Prototype: printed front frame with glass glue shelf → bond glass → seat LCD.  
Production: mill the glass/LCD pockets into the unibody; bond glass in place.

## Unibody CNC (production)

Aerospace-style billet aluminum (6061-T6 or similar):

1. **Lathe** — outer Ø, face flats, front chamfer (thin-in-hand look)  
2. **Mill front** — AA window / glass seat / LCD pocket  
3. **Mill back** — board pocket; **HDMI + USB-C** through rear wall under the board  
4. **Drill** — screw bosses or through-holes + center mount  
5. **Finish** — chemical polish → hand polish → durable coat / black anodize  
6. Deburr port edges; foam light-seal under AA lip  

Keep structural wall ≥ **1.2 mm**. Fixture: soft jaws / vacuum for thin discs.

**Sizing (current CAD):** PCB **51.7 × 47.15** fits **Ø74**.  
**I/O requirement:** HDMI + Power sit **under the board** and exit through the **rear face** (no side adapters).  
**Display:** measured Ø83 still does not fit Ø74 — glass/AA in CAD are provisional (~68 / 71).

## Prototype (print before metal)

| `part` in CAD | Role |
|---------------|------|
| `front` | Bezel + glass seat + LCD pocket |
| `back` | Board pocket; HDMI + Power under PCB → rear exits |
| `board` | View: green PCB + under-board connector ghosts |
| `unibody` | Production puck preview |
| `preview` | Ghost assembly |

Model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

## Parts (measure before cutting)

| Part | Confirmed / CAD | Measure still |
|------|-----------------|---------------|
| PCB | **51.7 × 47.15** | Must have **under-board** HDMI + Power |
| Outer shell | **Ø74** | Finished OD |
| Under-board Z | **10 mm** CAD | Real connector shell height |
| Mini-HDMI / Power openings | 11.5×8.5 / 9.2×3.6 | XY vs board |
| Display AA | Was Ø83 | Needs ≤~70 AA for Ø74, or larger shell |

## HDMI + Power (under the board)

Разъёмы **не сбоку** платы: корпуса коннекторов под PCB, окна только на **задней** стенке. Боковой mini-HDMI (+26 мм к ширине) для Ø74 не используем.

## Mounting

- Rear center boss: M4 insert or 17 mm ball  
- Or flat back + 3M VHB for grille  
- Strain relief on the harness side (remote box)

## Checklist

- [ ] Calipers: glass, AA, LCD Z, board, port XY / opening size  
- [ ] PETG front → optical/glue bond glass → LCD  
- [ ] PETG back → dry-fit board; confirm only port exits show on the outside  
- [ ] Lock dims → CNC unibody + three-stage finish  
- [ ] Vehicle: 12V buck or USB-C 5V/3A; remote Pi box  
