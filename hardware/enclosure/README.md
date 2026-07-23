# Dot enclosure (CAD)

Parametric OpenSCAD model for a **thin round head**: 2.8″ display + UEDX6911 board.

- Spec / stack-up: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Quick start

1. Install [OpenSCAD](https://openscad.org/)
2. Open `dot_case.scad`, set your caliper values
3. `part = "front"` → render → STL  
4. `part = "back"` → render → STL  
5. Print in **black matte PETG**, 0.2 mm layers, ≥3 perimeters

## Measure before v1 print

| Item | Your mm |
|------|---------|
| Glass outer diameter / WxH | |
| Active area diameter | |
| Display module thickness | |
| UEDX6911 L × W × H (with HDMI/USB) | |
| FPC exit side | |
