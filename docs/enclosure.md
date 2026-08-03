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

**Sizing (current CAD):** PCB **51.7 × 47.15** + mini-HDMI **+26 mm to width** → footprint **51.7 × 73.15** (diag ≈ **89.6 mm**). Outer shell **Ø94**.  
**Ø74 does not fit** this stack (width alone is already 73.15 mm before corners/walls).

## Prototype (print before metal)

Two-piece PETG only to prove stack height and port XY — then lock dims into unibody toolpath.

| `part` in CAD | Role |
|---------------|------|
| `front` | Bezel + glass seat + LCD pocket |
| `back` | Board + mini-HDMI stub pocket; USB-C rear; HDMI at rim |
| `board` | View: green PCB + blue +26 mm adapter on width |
| `unibody` | Production puck preview |
| `preview` | Ghost assembly |

Model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

## Parts (measure before cutting)

| Part | Confirmed / CAD | Measure still |
|------|-----------------|---------------|
| PCB | **51.7 × 47.15** | Thickness, hole pattern |
| Mini-HDMI | **+26 mm on width** (not Z) | Plug face; body thickness |
| Envelope | **51.7 × 73.15** | — |
| Outer shell | **Ø94** | Finished OD |
| Display AA | Was Ø83 | Glass OD under Ø94 |

## HDMI / USB-C

Mini-HDMI переходник удлиняет **ширину** платы: 47.15 + 26 = **73.15 мм**. В превью — синий выступ с края PCB; выход разъёма у **обода** корпуса. USB-C — в задней стенке.

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
