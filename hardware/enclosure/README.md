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
3. `part = "board"` → PCB seat (green) + **HDMI/USB-C adapter ghosts** (blue/orange)  
4. Set `hdmi_adapter_*` / `usbc_adapter_*` to your real dongle calipers  
5. `part = "front"` → print → bond glass → seat LCD  
6. `part = "back"` → print → dry-fit board **and adapters** through rear windows  
7. `part = "unibody"` → production-shaped single puck (CNC target)

## Measure (fill in)

| Item | mm | Note |
|------|-----|------|
| Display AA | **83** | Confirmed |
| Cover glass OD | ~85 target | Must clear AA + glue shelf |
| Cover glass thickness | | |
| Outer OD | **92** CAD | Adjust after CNC finish |
| Board L × W | **66 × 58** | Confirmed |
| LCD thickness behind glass | | |
| HDMI shell toward rear | | |
| USB-C shell toward rear | | |
| HDMI adapter W×H×stick-out | defaults 20×12×28 | Overwrite in SCAD |
| USB-C adapter W×H×stick-out | defaults 12.5×8×22 | Overwrite in SCAD |
| Connector centers vs board | | |
