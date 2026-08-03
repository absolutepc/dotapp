# Dot enclosure CAD

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Confirmed approach

| Item | Value |
|------|--------|
| PCB | **51.7 × 47.15 mm** (diag ~70 → fits **Ø74**) |
| I/O | **HDMI + Power under the board**, exits through the **rear face** |
| Not used | Side mini-HDMI (+26 mm on width) — that blocked Ø74 |
| Outer shell | **Ø74** |
| Under-board clearance | **10 mm** (`under_board_z`) for connector shells |

## Export

1. OpenSCAD → `part = "board"` → green PCB; blue/orange shells **under** it; exits on the back  
2. `front` / `back` / `unibody` for print or CNC  

Need a driver board whose mini-HDMI and power connectors face **down/rear**, not out the PCB edge.
