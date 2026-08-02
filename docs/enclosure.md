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

**Sizing driver:** measured display **Ø83 mm** (not the old “2.8″” label) and board **66 × 58 mm**. Outer shell in CAD is **Ø92** so both fit with wall + bezel. A **Ø74** shell is too small for this stack.

## Prototype (print before metal)

Two-piece PETG only to prove stack height and port XY — then lock dims into unibody toolpath.

| `part` in CAD | Role |
|---------------|------|
| `front` | Bezel + glass seat + LCD pocket (print, bond glass) |
| `back` | Board pocket + rear HDMI/USB + mount boss |
| `unibody` | Single-body preview of production aluminum puck |
| `preview` | Ghost assembly |

Model: [`hardware/enclosure/dot_case.scad`](../hardware/enclosure/dot_case.scad)

## Parts (measure before cutting)

| Part | Confirmed / CAD | Measure still |
|------|-----------------|---------------|
| Display (AA) | **Ø83 mm** (was mislabeled 2.8″) | Glass OD/thickness if separate cover |
| Cover glass | CAD `glass_od = 85` (target) | Final OD, AR face |
| Outer shell | CAD `outer_d = 92` | Finished OD after CNC |
| UEDX6911 board | **66 × 58 mm** (correct) | Thickness, rear HDMI/USB stick-out + XY |
| LCD stack height | — | Z behind glass |
| Ports | HDMI + USB-C on board | Centers vs board; shell size |
| **Adapters** | HDMI + USB-C dongles (CAD defaults) | Real W×H×stick-out — see below |

Goal overall head thickness after measure: **~16–20 mm** (adapters stick **out** the back; they do not add to head Z unless the shell sits inside the pocket).

## HDMI / USB-C adapters

Rear I/O is not bare cable-only: plan for **plug-in adapters** through the back wall.

| Item | CAD default (mm) | What to measure |
|------|------------------|-----------------|
| HDMI adapter body | 20 × 12, stick-out **28** | Your dongle L×W×H + how far it sits inboard |
| USB-C adapter body | 12.5 × 8, stick-out **22** | Same |
| Port windows | Sized to the **larger** of board shell vs adapter + clearance | Dry-fit through printed `back` |
| Keep-out behind head | `max(stick-outs)` ≈ **28 mm** | Must clear ball mount / grille / VHB pad |

In OpenSCAD: `part = board` or `preview` shows blue (HDMI) and orange (USB-C) adapter ghosts. Overwrite `hdmi_adapter_*` / `usbc_adapter_*` after calipers.

## Mounting

- Rear center boss: M4 insert or 17 mm ball — place so the ball/arm does **not** hit adapter stick-out (~28 mm keep-out)  
- Or flat back + 3M VHB for grille (leave cable/adapter channel)  
- Strain relief on the harness side (remote box), not only at the head  

## Checklist

- [ ] Calipers: glass, AA, LCD Z, board, HDMI/USB shells + **adapter** W×H×stick-out  
- [ ] PETG front → optical/glue bond glass → LCD  
- [ ] PETG back → dry-fit board + **both adapters** through rear windows  
- [ ] Confirm mount boss / ball clears adapter keep-out  
- [ ] Lock dims → CNC unibody + three-stage finish  
- [ ] Vehicle: 12V buck or USB-C 5V/3A; remote Pi box  
