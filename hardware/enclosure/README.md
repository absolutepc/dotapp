# Dot enclosure CAD

Round head split like the reference badge:

1. **`front`** — matte black bezel + AA window (print first; this is the face in your photo)
2. **`back`** — board pocket, **HDMI + USB-C on the rear** under UEDX6911

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Set calipers (`aa_d`, `inner_glass_d`, `hdmi_*`, `usbc_*`, `overall_z`)
3. `part = "front"` → F6 → STL → **black matte PETG/resin**
4. `part = "back"` → F6 → STL

Print front face-up or on the mating face; sand the visible ring lightly for a uniform matte look.

## Measure (fill in)

| Item | mm |
|------|-----|
| Glass outer | |
| AA diameter | |
| Module thickness | |
| Bezel lip (desired black ring) | |
| Board L × W × H | |
| HDMI shell toward rear | |
| USB-C shell toward rear | |
| Connector center positions vs board | |
