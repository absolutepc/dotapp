// Dot enclosure — CNC-style round head
// Production intent: CNC unibody aluminum (chem polish → hand polish → coat)
// Prototype: split front/back PETG to prove glass bond + rear ports
// Architecture: thin head (display+UEDX6911) + remote Pi/power box
// FRONT: bezel + optically bonded cover glass + LCD pocket
// BACK / unibody rear: HDMI + USB-C under the board
//
// part = "preview" | "front" | "back" | "board" | "unibody"
// Units: mm
// Rear I/O: flush/recessed HDMI + USB-C — only the port exits are visible outside.

/* [Which part] */
// board = back + green PCB ghost (view only, not for STL)
part = "board"; // ["preview", "front", "back", "board", "unibody"]

/* [Outer — unibody silhouette] */
// PCB 51.7×47.15 + mini-HDMI 26 mm on the WIDTH → envelope 51.7×73.15 (diag ~89.6).
// That does NOT fit Ø74. Outer sized to clear the envelope + wall.
outer_d = 94;
chamfer = 1.4;
wall = 1.2;
overall_z = 18;

/* [Front — bezel + glass (optical bond target)] */
// Nested under Ø94. A measured Ø83 AA still needs glass_od ≲ 90.
aa_d = 83;
glass_od = 88;
glass_thick = 1.1;
glue_w = 1.0;
bezel_lip = 0.9;
lcd_pocket_z = 3.2;

/* [Driver board — in plane of the puck] */
// PCB size; mini-HDMI adapter adds to WIDTH (Y), not to thickness (Z).
board_w = 51.7;           // length (X)
board_h = 47.15;          // width (Y) without adapter
board_thick = 1.6;
board_clear_z = 8.5;
board_corner_r = 1.5;
// Shift PCB so (board + adapter) envelope is centered in the circle
hdmi_adapter_out = 26;    // protrudes from the +Y edge of the PCB
board_y_shift = -hdmi_adapter_out / 2;

/* [Ports] */
// Mini-HDMI plug faces outward at the adapter tip (side / rim of the puck).
hdmi_w = 11.5;
hdmi_h = 8.5;
hdmi_adapter_thick = 8;   // adapter body thickness (Z), caliper if needed

usbc_w = 9.2;
usbc_h = 3.6;
usbc_x = 12;
usbc_y = 0;               // on the PCB area
port_inset = 0.4;

/* [Rear mount boss] */
mount_boss_d = 14;
mount_boss_h = 3.5;
mount_hole_d = 4.2;

/* [Fit] */
tolerance = 0.25;
screw_d = 2.2;
screw_circle = 36;

$fn = 128;

function glass_seat_z() = bezel_lip + glass_thick;
function front_z() = glass_seat_z() + lcd_pocket_z + 0.8;
function back_z() = max(overall_z - front_z(), board_clear_z + wall + 2.5);
function unibody_z() = overall_z;
function envelope_h() = board_h + hdmi_adapter_out;
// Y of PCB +Y edge and adapter tip (envelope centered via board_y_shift)
function board_plus_y() = board_y_shift + board_h / 2;
function adapter_tip_y() = board_plus_y() + hdmi_adapter_out;

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

// Full XY footprint: PCB + mini-HDMI stub on +Y
module board_with_adapter_2d() {
    union() {
        board_2d();
        translate([0, board_h / 2 + hdmi_adapter_out / 2])
            square([
                max(hdmi_w, board_w * 0.35) + 2 * tolerance,
                hdmi_adapter_out + 2 * tolerance
            ], center = true);
    }
}

// USB-C through the rear face (under the PCB)
module usbc_rear_port(through_z) {
    translate([usbc_x, board_y_shift + usbc_y, -0.1])
        cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, through_z], center = true);
}

// Mini-HDMI exit: channel from PCB edge through the rim (only the opening shows outside)
module hdmi_side_port() {
    chan_y0 = board_plus_y();
    chan_y1 = outer_d / 2 + 1;
    translate([0, (chan_y0 + chan_y1) / 2, wall + hdmi_adapter_thick / 2])
        cube([
            hdmi_w + 2 * port_inset,
            chan_y1 - chan_y0,
            hdmi_adapter_thick + 2 * port_inset
        ], center = true);
}

module usbc_tunnel() {
    translate([usbc_x, board_y_shift + usbc_y, wall - 0.05])
        cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, board_clear_z], center = true);
}

module ghost_port_exits() {
    // Mini-HDMI opening marker at rim
    color("royalblue", 0.9)
        translate([0, outer_d / 2 - 0.2, wall + hdmi_adapter_thick / 2])
            cube([hdmi_w, 0.4, hdmi_h], center = true);
    color("orange", 0.85)
        translate([usbc_x, board_y_shift + usbc_y, -0.15])
            cube([usbc_w, usbc_h, 0.3], center = true);
}

// ---------- FRONT (prototype print; bond glass; seat LCD) ----------
module front() {
    z = front_z();
    glass_z0 = z - bezel_lip - glass_thick;
    lcd_z0 = glass_z0 - lcd_pocket_z;
    lcd_d = glass_od - 2 * glue_w;

    difference() {
        union() {
            chamfered_disc(outer_d, z, chamfer);
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([screw_circle, 0, 0])
                        cylinder(d = 6.5, h = max(1, lcd_z0 + 0.2));
        }

        translate([0, 0, glass_z0 + glass_thick - 0.05])
            cylinder(d = aa_d, h = bezel_lip + 0.2);

        translate([0, 0, glass_z0])
            cylinder(d = glass_od + 2 * tolerance, h = glass_thick + 0.05);

        translate([0, 0, lcd_z0 - 0.05])
            cylinder(d = lcd_d + 2 * tolerance, h = lcd_pocket_z + 0.15);

        // FPC stays inside the LCD pocket — no side wall cutout.

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = lcd_z0 + 0.2);
    }
}

module ghost_glass() {
    z = front_z();
    glass_z0 = z - bezel_lip - glass_thick;
    translate([0, 0, glass_z0])
        cylinder(d = glass_od, h = glass_thick);
}

// ---------- BACK (prototype) ----------
// z=0 outer back; board in XY with mini-HDMI stub on +Y (width + 26 mm).
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

        translate([0, board_y_shift, wall])
            linear_extrude(height = z - wall + 0.1)
                board_with_adapter_2d();

        usbc_rear_port(wall + 0.4);
        usbc_tunnel();
        hdmi_side_port();

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z + 0.2);
    }
}

module ghost_board() {
    color("lime", 0.55)
        translate([0, board_y_shift, wall + 0.2])
            linear_extrude(height = board_thick)
                square([board_w, board_h], center = true);
    // Mini-HDMI adapter stub (+Y): shows the +26 mm on width
    color("royalblue", 0.45)
        translate([0, board_plus_y() + hdmi_adapter_out / 2, wall + 0.2])
            linear_extrude(height = max(board_thick, hdmi_adapter_thick * 0.5))
                square([max(hdmi_w, board_w * 0.35), hdmi_adapter_out], center = true);
}

// View helper: back shell + green PCB + flush port exits only
module back_board_view() {
    color("gainsboro")
        back_v2();
    ghost_board();
    ghost_port_exits();
}

// ---------- UNIBODY (production aluminum puck) ----------
// z=0 = outer back (ports); z=unibody_z() = visible front face
// Front pockets milled from +Z; board + ports from -Z / through rear wall.
module unibody() {
    z = unibody_z();
    glass_z0 = z - bezel_lip - glass_thick;
    lcd_z0 = glass_z0 - lcd_pocket_z;
    lcd_d = glass_od - 2 * glue_w;
    floor_top = lcd_z0;
    board_cavity_top = min(wall + board_clear_z + 1, floor_top - 0.8);

    difference() {
        union() {
            chamfered_disc(outer_d, z, chamfer);
            translate([0, 0, -mount_boss_h + 0.01])
                cylinder(d = mount_boss_d, h = mount_boss_h);
        }

        translate([0, 0, glass_z0 + glass_thick - 0.05])
            cylinder(d = aa_d, h = bezel_lip + 0.2);
        translate([0, 0, glass_z0])
            cylinder(d = glass_od + 2 * tolerance, h = glass_thick + 0.05);
        translate([0, 0, lcd_z0 - 0.05])
            cylinder(d = lcd_d + 2 * tolerance, h = lcd_pocket_z + 0.15);

        translate([0, board_y_shift, wall])
            linear_extrude(height = max(0.2, board_cavity_top - wall + 0.2))
                board_with_adapter_2d();

        usbc_rear_port(wall + 0.4);
        usbc_tunnel();
        hdmi_side_port();

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);
    }
}

module preview_stack() {
    color("Black")
        translate([0, 0, back_z() + 0.4])
            front();
    color("AliceBlue", 0.35)
        translate([0, 0, back_z() + 0.4])
            ghost_glass();
    color("gainsboro")
        back_v2();
    ghost_board();
    ghost_port_exits();
}

if (part == "front") color("Black") front();
else if (part == "back") back_v2();
else if (part == "board") back_board_view();
else if (part == "unibody") color("Black") unibody();
else preview_stack();
