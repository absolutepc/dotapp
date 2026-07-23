# Dot enclosure CAD

CNC-style **thin round head**: 2.8″ display + UEDX6911, **HDMI + USB-C on the back** under the board.

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Set caliper values (`hdmi_*`, `usbc_*`, `board_*`, `overall_z`)
3. `part = "front"` → F6 → STL  
4. `part = "back"` → F6 → STL  

Print PETG black matte for fit; aluminum CNC for final (see enclosure.md).

## Measure (fill in)

| Item | mm |
|------|-----|
| Glass outer | |
| AA diameter | |
| Module thickness | |
| Board L × W × H | |
| HDMI shell toward rear | |
| USB-C shell toward rear | |
| Connector center positions vs board | |
