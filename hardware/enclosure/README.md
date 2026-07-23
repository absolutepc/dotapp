# Dot enclosure CAD

Process / look reference: [Vusi Studios reel](https://www.instagram.com/reel/DZIhncvRAz_/) (digital badge).  
Round head split like that badge:

1. **`front`** — **bezel + glass assembly** (printed frame with glass seat/glue shelf + LCD pocket)
2. **`back`** — board pocket, **HDMI + USB-C on the rear** under UEDX6911

The reference face in-hand is not a bezel alone: glass is bonded into that front unit.

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Set calipers (`glass_od`, `glass_thick`, `aa_d`, `hdmi_*`, `usbc_*`, `overall_z`)
3. `part = "front"` → F6 → STL → print → **bond cover glass** → seat LCD
4. `part = "back"` → F6 → STL

## Measure (fill in)

| Item | mm |
|------|-----|
| Cover glass OD | |
| Cover glass thickness | |
| AA diameter | |
| LCD thickness behind glass | |
| Board L × W × H | |
| HDMI shell toward rear | |
| USB-C shell toward rear | |
| Connector centers vs board | |
