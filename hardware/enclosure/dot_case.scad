// Dot thin head enclosure — display + UEDX6911-HDMI
// OpenSCAD parametric model. Export STL: front / back separately.
//
// Usage:
//   1) Measure your glass + board, edit parameters below
//   2) Set part = "front" | "back" | "preview"
//   3) F6 → export STL
//
// Units: millimeters

/* [Which part] */
part = "preview"; // ["preview", "front", "back"]

/* [Outer shell] */
outer_d = 82;
wall = 1.6;
overall_z = 20;
bezel_lip = 2.0;
aa_d = 70.2;          // visible aperture (active area)
inner_glass_d = 73.5; // pocket for glass module outline
glass_pocket_z = 4.2; // depth for display module

/* [Driver board pocket] */
board_w = 66;
board_h = 58;
board_clear_z = 9;
board_corner_r = 2;

/* [Cable exit] */
cable_w = 18;
cable_h = 7;
cable_offset_z = 6; // from back toward front

/* [Fit] */
tolerance = 0.25;
screw_d = 2.2;
screw_boss_d = 6;

$fn = 96;

module round_shell_outer(h) {
    cylinder(d = outer_d, h = h);
}

module board_pocket(h) {
    translate([0, 0, 0])
        linear_extrude(height = h)
            offset(r = board_corner_r)
                square([board_w - 2 * board_corner_r + 2 * tolerance,
                        board_h - 2 * board_corner_r + 2 * tolerance], center = true);
}

module front() {
    z_front = bezel_lip + glass_pocket_z + 1.2;
    difference() {
        // body
        union() {
            round_shell_outer(z_front);
            // screw bosses
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([outer_d / 2 - wall - 3, 0, 0])
                        cylinder(d = screw_boss_d, h = z_front);
        }
        // viewing aperture
        translate([0, 0, -0.1])
            cylinder(d = aa_d, h = z_front + 0.2);
        // glass pocket (from behind the lip)
        translate([0, 0, bezel_lip])
            cylinder(d = inner_glass_d + 2 * tolerance, h = glass_pocket_z + 0.2);
        // screw holes
        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([outer_d / 2 - wall - 3, 0, -0.1])
                    cylinder(d = screw_d, h = z_front + 0.2);
    }
}

module back() {
    z_back = overall_z - (bezel_lip + glass_pocket_z);
    z_back = max(z_back, board_clear_z + wall + 1.5);
    difference() {
        union() {
            round_shell_outer(z_back);
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([outer_d / 2 - wall - 3, 0, 0])
                        cylinder(d = screw_boss_d, h = z_back);
        }
        // main cavity
        translate([0, 0, wall])
            cylinder(d = outer_d - 2 * wall, h = z_back);
        // board pocket (slightly deeper island)
        translate([0, 0, wall])
            board_pocket(board_clear_z + 0.5);
        // cable exit slot
        translate([outer_d / 2 - wall - 1, 0, cable_offset_z])
            rotate([0, 90, 0])
                cube([cable_h + 2 * tolerance, cable_w + 2 * tolerance, wall + 6], center = true);
        // vents
        for (y = [-12, 0, 12])
            translate([-10, y, -0.1])
                cube([20, 2.2, wall + 0.3]);
        // screw holes
        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([outer_d / 2 - wall - 3, 0, -0.1])
                    cylinder(d = screw_d, h = z_back + 0.2);
    }
}

module preview_stack() {
    color("gray") front();
    color("dimgray")
        translate([0, 0, -(overall_z - (bezel_lip + glass_pocket_z + 1.2))])
            back();
    // ghost display AA
    color("black", 0.35)
        translate([0, 0, bezel_lip + 0.2])
            cylinder(d = aa_d, h = 0.6);
    // ghost board
    color("green", 0.35)
        translate([0, 0, -(board_clear_z)])
            linear_extrude(height = 1.2)
                square([board_w, board_h], center = true);
}

if (part == "front") front();
else if (part == "back") back();
else preview_stack();
