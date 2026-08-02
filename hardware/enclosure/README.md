# Dot enclosure CAD

Production intent from the reference badge build: **CNC unibody aluminum** head  
(chem polish → hand polish → coat), **bezel + bonded glass** face, rear HDMI/USB  
under the driver board. Pi + buck stay in a remote box.

Prototype with split PETG (`front` / `back`), then lock dims into `unibody`.

- Spec: [docs/enclosure.md](../../docs/enclosure.md)
- Model: [`dot_case.scad`](dot_case.scad)

## Confirmed sizes

| Item | Value |
|------|--------|
| Display (AA) | **Ø83 mm** (label “2.8″” was wrong) |
| Driver board | **66 × 58 mm** |
| Outer shell (CAD) | **Ø92 mm** — clears Ø83 panel + 66×58 board + walls |

A **Ø74** outer cannot fit this display or a centered 66×58 board.

## Export

1. Open in [OpenSCAD](https://openscad.org/)
2. Set calipers (`glass_od`, `glass_thick`, `aa_d`, `hdmi_*`, `usbc_*`, `overall_z`) if your stack differs
3. `part = "board"` → PCB seat (green) + flush port **exits** only (blue/orange markers)  
4. `part = "front"` → print → bond glass → seat LCD  
5. `part = "back"` → print → dry-fit board; outside should show only HDMI/USB-C openings  
6. `part = "unibody"` → production-shaped single puck (CNC target)

## Measure (fill in)

| Item | mm | Note |
|------|-----|------|
| Display AA | **83** | Confirmed |
| Cover glass OD | ~85 target | Must clear AA + glue shelf |
| Cover glass thickness | | |
| Outer OD | **92** CAD | Adjust after CNC finish |
| Board L × W | **66 × 58** | Confirmed |
| LCD thickness behind glass | | |
| HDMI exit opening | 15.5 × 6.2 | Flush — body inside |
| USB-C exit opening | 9.2 × 3.6 | Flush — body inside |
| Connector centers vs board | | |
