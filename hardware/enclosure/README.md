# Dot enclosure CAD

Production intent from the reference badge build: **CNC unibody aluminum** head  
(chem polish → hand polish → coat), **bezel + bonded glass** face, rear HDMI/USB  
under the driver board. Pi + buck stay in a remote box.

Prototype with split PETG (`front` / `back`), then lock dims into `unibody`.

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Set calipers (`glass_od`, `glass_thick`, `aa_d`, `hdmi_*`, `usbc_*`, `overall_z`)
3. `part = "front"` → print → bond glass → seat LCD  
4. `part = "back"` → print → dry-fit ports  
5. `part = "unibody"` → production-shaped single puck (CNC target)

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
