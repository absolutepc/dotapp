# Dot enclosure CAD

Production intent: **CNC unibody aluminum** head, **bezel + bonded glass**, rear  
mini-HDMI + USB-C with **flush exits** (adapter body inside). Pi + buck remote.

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Confirmed sizes

| Item | Value |
|------|--------|
| Outer shell | **Ø74 mm** |
| Driver board | **51.7 × 47.15 mm** (diag ~70 — fits Ø74) |
| Mini-HDMI adapter | **26 mm** from PCB → board recessed for flush exit |
| Head thickness (CAD) | **~34 mm** (`overall_z`) |
| Display AA | Was Ø83 — **does not fit Ø74**; CAD uses provisional ~68 mm AA |

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Check `hdmi_adapter_len = 26`, board W/H, `outer_d = 74`
3. `part = "board"` → recessed PCB + flush port exits  
4. `part = "front"` / `"back"` / `"unibody"` → print or CNC

## Measure (fill in)

| Item | mm | Note |
|------|-----|------|
| Outer OD | **74** | Hard target |
| Board L × W | **51.7 × 47.15** | Confirmed |
| Mini-HDMI from PCB | **26** | Recess depth |
| Mini-HDMI opening | ~11.5 × 8.5 | Caliper plug |
| USB-C opening | 9.2 × 3.6 | |
| Display AA | | Must be ≤ ~70 for Ø74 |
| Cover glass OD | ≤ 71 | CAD provisional |
| Connector centers vs board | | |
