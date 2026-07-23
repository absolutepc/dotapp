// Dot enclosure v2 — CNC-style round head
// Look/process ref: https://www.instagram.com/reel/DZIhncvRAz_/ (@vusistudios digital badge)
// FRONT ASSEMBLY: printed bezel + cover glass seat (+ LCD pocket)
// BACK: board pocket; HDMI + USB-C through rear under UEDX6911 (Dot-specific)
//
// part = "preview" | "front" | "back"
// Units: mm

/* [Which part] */
part = "preview"; // ["preview", "front", "back"]

/* [Outer] */
outer_d = 84;
chamfer = 1.6;
wall = 1.5;
overall_z = 18;

/* [Front assembly — bezel + glass] */
// Reference face = black frame with glass already in it (one subassembly).
aa_d = 70.2;            // visible aperture through glass
glass_od = 73.5;        // cover glass outer diameter
glass_thick = 1.1;      // cover glass thickness
glue_w = 1.2;           // radial glue / seat shelf under glass rim
bezel_lip = 0.9;        // black frame in front of glass (thin ring)
lcd_pocket_z = 3.2;     // LCD module depth behind glass
fpc_slot_w = 22;        // FPC exit toward board (rear of front shell)
fpc_slot_h = 1.2;

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
tolerance = 0.25;
screw_d = 2.2;
screw_circle = 34;

$fn = 128;

function glass_seat_z() = bezel_lip + glass_thick;
function front_z() = glass_seat_z() + lcd_pocket_z + 0.8;
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

// ---------- FRONT ASSEMBLY (print frame; bond glass; seat LCD) ----------
// z=0 mates to back; z=front_z() is the visible face.
// Stack (visible → back): bezel lip → cover glass → glue shelf → LCD → FPC
// Glue shelf = glass pocket wider than LCD pocket (rim left under glass).
module front() {
    z = front_z();
    glass_z0 = z - bezel_lip - glass_thick;
    lcd_z0 = glass_z0 - lcd_pocket_z;
    lcd_d = glass_od - 2 * glue_w; // shelf width under glass = glue_w

    difference() {
        union() {
            chamfered_disc(outer_d, z, chamfer);
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([screw_circle, 0, 0])
                        cylinder(d = 6.5, h = max(1, lcd_z0 + 0.2));
        }

        // AA through bezel lip (in front of glass)
        translate([0, 0, glass_z0 + glass_thick - 0.05])
            cylinder(d = aa_d, h = bezel_lip + 0.2);

        // Cover glass seat (glass belongs in this front assembly)
        translate([0, 0, glass_z0])
            cylinder(d = glass_od + 2 * tolerance, h = glass_thick + 0.05);

        // LCD pocket behind glass — smaller OD leaves glue/seat shelf
        translate([0, 0, lcd_z0 - 0.05])
            cylinder(d = lcd_d + 2 * tolerance, h = lcd_pocket_z + 0.15);

        // FPC exit toward the back / board
        translate([0, -(glass_od / 2) + 2, lcd_z0 - 0.1])
            cube([fpc_slot_w, 12, fpc_slot_h + lcd_pocket_z], center = true);

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = lcd_z0 + 0.2);
    }
}

// Ghost glass for preview (not exported)
module ghost_glass() {
    z = front_z();
    glass_z0 = z - bezel_lip - glass_thick;
    translate([0, 0, glass_z0])
        cylinder(d = glass_od, h = glass_thick);
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
    // glass as part of front assembly
    color("AliceBlue", 0.35)
        translate([0, 0, back_z() + 0.4])
            ghost_glass();
    color("gainsboro")
        back_v2();
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
