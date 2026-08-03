# Dot enclosure CAD

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Confirmed sizes

| Item | Value |
|------|--------|
| PCB | **51.7 × 47.15 mm** |
| Mini-HDMI adapter | **+26 mm on width** → envelope **51.7 × 73.15** (diag ≈ **89.6 mm**) |
| Outer shell (CAD) | **Ø94 mm** — clears envelope + wall |
| **Ø74** | **Does not fit** this envelope |

## Export

1. OpenSCAD → `part = "board"` → green PCB + blue mini-HDMI stub (+26 mm on width)  
2. `front` / `back` / `unibody` for print or CNC  

## Measure

| Item | mm |
|------|-----|
| Board L × W | 51.7 × 47.15 |
| Mini-HDMI out (width) | 26 |
| Envelope W | 73.15 |
| Outer OD | 94 CAD |
| Mini-HDMI opening | ~11.5 × 8.5 |
| USB-C | 9.2 × 3.6 |
