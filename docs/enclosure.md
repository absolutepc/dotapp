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

**Sizing (current CAD):** outer **Ø74**, board **51.7 × 47.15**, mini-HDMI adapter **26 mm** from PCB (board recessed so only the port face shows). Head Z ≈ **34 mm**.  
**Conflict:** earlier measured display **Ø83** does **not** fit Ø74 — CAD glass/AA are provisional (~68 / 71) until you pick a smaller panel or raise `outer_d`.

## Prototype (print before metal)

Two-piece PETG only to prove stack height and port XY — then lock dims into unibody toolpath.

| `part` in CAD | Role |
|---------------|------|
| `front` | Bezel + glass seat + LCD pocket (print, bond glass) |
| `back` | Recessed board + rear mini-HDMI/USB + mount boss |
| `board` | View: green PCB + flush port markers |
| `unibody` | Single-body preview of production aluminum puck |
| `preview` | Ghost assembly |

Model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

## Parts (measure before cutting)

| Part | Confirmed / CAD | Measure still |
|------|-----------------|---------------|
| Outer shell | **Ø74** | Finished OD after CNC |
| Driver board | **51.7 × 47.15 mm** | Thickness, hole pattern |
| Mini-HDMI adapter | **26 mm** from PCB | Plug face size (window XY) |
| Display (AA) | Was Ø83 — **won't fit Ø74** | Confirm actual panel AA |
| Cover glass | CAD `glass_od = 71` (provisional) | Final OD, AR face |
| USB-C | Flush exit | Opening + XY |

Goal overall head thickness: **~34 mm** with recessed 26 mm mini-HDMI (flush rear).

## HDMI / USB-C (flush exits)

Mini-HDMI переходник **26 мм** от платы уходит к задней стенке. Плата посажена с отступом `hdmi_adapter_len`, снаружи видно **только окно** разъёма.

| Item | CAD | Notes |
|------|-----|--------|
| Mini-HDMI window | 11.5 × 8.5 (+ inset) | Caliper your plug |
| Adapter length | **26 mm** from PCB | Inside tunnel; flush at z=0 |
| USB-C window | 9.2 × 3.6 (+ inset) | Same flush idea |
| External dongle solids | Not modeled | Exit markers only in preview |

In OpenSCAD, `part = board` shows green PCB recessed + thin blue/orange **exit markers**.

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
