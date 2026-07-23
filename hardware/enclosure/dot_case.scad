// Dot enclosure v2 — CNC-style round head
// FRONT: separate printed black bezel (reference “digital badge” face)
// BACK: board pocket; HDMI + USB-C through rear under UEDX6911
//
// part = "preview" | "front" | "back"
// Units: mm

/* [Which part] */
part = "preview"; // ["preview", "front", "back"]

/* [Outer] */
outer_d = 84;
chamfer = 1.6;          // light outer rim chamfer (thin-in-hand)
wall = 1.5;
overall_z = 18;         // raise if rear connectors need more depth

/* [Front bezel — printed black face] */
// Reference: thin matte black ring around a dark round AA; separate part.
aa_d = 70.2;            // visible aperture (match measured AA)
inner_glass_d = 73.5;   // glass / module pocket ID
bezel_lip = 1.6;        // black ring thickness in front of glass (print face)
glass_pocket_z = 3.8;   // depth behind lip for module
bezel_face_flat = 0.6;  // short flat before chamfer so ring reads “printed plate”

/* [Driver board — connectors face rear] */
board_w = 66;
board_h = 58;
board_thick = 1.6;
board_clear_z = 8.5;
board_corner_r = 2;
board_y_shift = 0;

/* [Rear ports — under the board] */
hdmi_w = 15.5;
hdmi_h = 6.2;
hdmi_x = -12;
hdmi_y = -8;

usbc_w = 9.2;
usbc_h = 3.6;
usbc_x = 14;
usbc_y = -8;

port_inset = 0.35;

/* [Rear mount boss] */
mount_boss_d = 14;
mount_boss_h = 3.5;
mount_hole_d = 4.2;

/* [Fit] */
tolerance = 0.3;
screw_d = 2.2;
screw_circle = 34;

$fn = 128;

function front_z() = bezel_lip + glass_pocket_z + bezel_face_flat;
function back_z() = max(overall_z - front_z(), board_clear_z + wall + 2.5);

module chamfered_disc(d, h, ch) {
    hull() {
        cylinder(d = d, h = max(0.2, h - ch));
        translate([0, 0, h - 0.01])
            cylinder(d = d - 2 * ch, h = 0.01);
    }
}

module board_2d() {
    offset(r = board_corner_r)
        square([
            board_w - 2 * board_corner_r + 2 * tolerance,
            board_h - 2 * board_corner_r + 2 * tolerance
        ], center = true);
}

// ---------- FRONT (print matte black — badge face) ----------
// z=0 mates to back; z=front_z() is the visible face.
module front() {
    z = front_z();
    difference() {
        union() {
            // Outer shell with soft chamfer (reads thin like the reference puck)
            chamfered_disc(outer_d, z, chamfer);
            // Screw bosses toward the back (do not break the clean front face)
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([screw_circle, 0, 0])
                        cylinder(d = 6.5, h = z - 0.4);
        }

        // AA window through the black bezel
        translate([0, 0, -0.1])
            cylinder(d = aa_d, h = z + 0.2);

        // Glass / module pocket behind the lip
        translate([0, 0, -0.05])
            cylinder(
                d = inner_glass_d + 2 * tolerance,
                h = glass_pocket_z + 0.1
            );

        // Slight countersink on the visible lip so the glass sits flush/shadowed
        translate([0, 0, z - bezel_lip - 0.01])
            cylinder(d1 = aa_d, d2 = aa_d + 0.8, h = bezel_lip + 0.02);

        // Screw holes from mating face
        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z - bezel_lip);
    }
}

// ---------- BACK ----------
// z=0 = outer back (ports visible); z=back_z() mates to front.
module back_v2() {
    z = back_z();
    difference() {
        union() {
            cylinder(d = outer_d, h = z);
            translate([0, 0, -mount_boss_h + 0.01])
                cylinder(d = mount_boss_d, h = mount_boss_h);
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([screw_circle, 0, 0])
                        cylinder(d = 6.5, h = z);
        }

        translate([0, 0, wall])
            cylinder(d = outer_d - 2 * wall, h = z + 0.1);

        translate([0, board_y_shift, wall])
            linear_extrude(height = board_clear_z + 1)
                board_2d();

        // HDMI + USB-C through outer back, under the board
        translate([hdmi_x, hdmi_y, -0.1])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, wall + 0.3], center = true);
        translate([usbc_x, usbc_y, -0.1])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, wall + 0.3], center = true);

        translate([hdmi_x, hdmi_y, wall - 0.05])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, board_clear_z], center = true);
        translate([usbc_x, usbc_y, wall - 0.05])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, board_clear_z], center = true);

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);

        for (x = [-16, 0, 16])
            translate([x, 18, -0.05])
                cube([8, 1.6, wall + 0.2], center = true);

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z + 0.2);
    }
}

module preview_stack() {
    color("DimGray")
        translate([0, 0, back_z() + 0.4])
            front();
    color("gainsboro")
        back_v2();
    color("black", 0.55)
        translate([0, 0, back_z() + 0.4 + glass_pocket_z])
            cylinder(d = aa_d, h = bezel_lip);
    color("green", 0.45)
        translate([0, board_y_shift, wall + 1])
            linear_extrude(height = board_thick)
                square([board_w, board_h], center = true);
    color("royalblue", 0.7)
        translate([hdmi_x, hdmi_y, wall / 2])
            cube([hdmi_w, hdmi_h, wall + 1], center = true);
    color("orange", 0.7)
        translate([usbc_x, usbc_y, wall / 2])
            cube([usbc_w, usbc_h, wall + 1], center = true);
}

if (part == "front") front();
else if (part == "back") back_v2();
else preview_stack();
