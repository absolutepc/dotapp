// Dot enclosure — CNC-style round head
// Production intent: CNC unibody aluminum (chem polish → hand polish → coat)
// Prototype: split front/back PETG to prove glass bond + rear ports
// Architecture: thin head (display + driver PCB) + remote Pi/power box
// FRONT: bezel + optically bonded cover glass + LCD pocket
// BACK: HDMI + Power under the PCB, exits through the rear face (not the rim)
//
// part = "preview" | "front" | "back" | "board" | "unibody"
// Units: mm

/* [Which part] */
// board = back + green PCB + under-board port ghosts (view only, not for STL)
part = "board"; // ["preview", "front", "back", "board", "unibody"]

/* [Outer — unibody silhouette] */
// PCB 51.7×47.15 (diag ~70) fits Ø74 with wall 1.2.
// Requirement: HDMI + Power under the board (rear exits) — no side adapters.
// Note: a Ø83 display still does not fit Ø74; glass/AA below are provisional.
outer_d = 74;
chamfer = 1.2;
wall = 1.2;
overall_z = 20;

/* [Front — bezel + glass (optical bond target)] */
// Provisional nest inside Ø74 (raise outer_d if AA is still ~83).
aa_d = 68;
glass_od = 71;
glass_thick = 1.1;
glue_w = 1.0;
bezel_lip = 0.7;
lcd_pocket_z = 3.2;

/* [Driver board — connectors UNDER the PCB, facing rear] */
board_w = 51.7;
board_h = 47.15;
board_thick = 1.6;
board_corner_r = 1.5;
board_y_shift = 0;
// Clearance under the PCB for HDMI + Power shells (Z), before the rear face
under_board_z = 10;

/* [Rear ports — under the board, through the back face] */
hdmi_w = 11.5;          // mini-HDMI opening (caliper)
hdmi_h = 8.5;
hdmi_x = -10;
hdmi_y = -6;

power_w = 9.2;          // USB-C / power
power_h = 3.6;
power_x = 12;
power_y = -6;

port_inset = 0.4;

/* [Rear mount boss] */
mount_boss_d = 14;
mount_boss_h = 3.5;
mount_hole_d = 4.2;

/* [Fit] */
tolerance = 0.25;
screw_d = 2.2;
screw_circle = 28;

$fn = 128;

function glass_seat_z() = bezel_lip + glass_thick;
function front_z() = glass_seat_z() + lcd_pocket_z + 0.8;
function board_seat_z() = under_board_z; // PCB sits above under-board I/O
function back_z() = max(
    overall_z - front_z(),
    board_seat_z() + board_thick + 3
);
function unibody_z() = overall_z;

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

// HDMI + Power windows on the rear face (under the PCB footprint)
module under_board_ports(through_z) {
    translate([hdmi_x, board_y_shift + hdmi_y, -0.1])
        cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, through_z], center = true);
    translate([power_x, board_y_shift + power_y, -0.1])
        cube([power_w + 2 * port_inset, power_h + 2 * port_inset, through_z], center = true);
}

// Cavities under the PCB for connector shells (Z from face up to board seat)
module under_board_tunnels() {
    translate([hdmi_x, board_y_shift + hdmi_y, board_seat_z() / 2])
        cube([
            hdmi_w + 2 * port_inset,
            hdmi_h + 2 * port_inset,
            board_seat_z() + 0.2
        ], center = true);
    translate([power_x, board_y_shift + power_y, board_seat_z() / 2])
        cube([
            power_w + 2 * port_inset,
            power_h + 2 * port_inset,
            board_seat_z() + 0.2
        ], center = true);
}

module ghost_port_exits() {
    color("royalblue", 0.85)
        translate([hdmi_x, board_y_shift + hdmi_y, -0.15])
            cube([hdmi_w, hdmi_h, 0.3], center = true);
    color("orange", 0.85)
        translate([power_x, board_y_shift + power_y, -0.15])
            cube([power_w, power_h, 0.3], center = true);
}

// ---------- FRONT ----------
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

// ---------- BACK ----------
// z=0 = rear face (HDMI + Power exits under the board).
module back_v2() {
    z = back_z();
    seat = board_seat_z();
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

        translate([0, board_y_shift, seat])
            linear_extrude(height = z - seat + 0.1)
                board_2d();

        under_board_ports(wall + 0.4);
        under_board_tunnels();

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z + 0.2);
    }
}

module ghost_board() {
    seat = board_seat_z();
    color("lime", 0.55)
        translate([0, board_y_shift, seat + 0.15])
            linear_extrude(height = board_thick)
                square([board_w, board_h], center = true);
    // Connector shells under the PCB (not beside it)
    color("royalblue", 0.4)
        translate([hdmi_x, board_y_shift + hdmi_y, seat / 2])
            cube([hdmi_w, hdmi_h, max(0.5, seat - 0.4)], center = true);
    color("orange", 0.4)
        translate([power_x, board_y_shift + power_y, seat / 2])
            cube([power_w, power_h, max(0.5, seat - 0.4)], center = true);
}

module back_board_view() {
    color("gainsboro")
        back_v2();
    ghost_board();
    ghost_port_exits();
}

// ---------- UNIBODY ----------
module unibody() {
    z = unibody_z();
    glass_z0 = z - bezel_lip - glass_thick;
    lcd_z0 = glass_z0 - lcd_pocket_z;
    lcd_d = glass_od - 2 * glue_w;
    seat = board_seat_z();
    floor_top = lcd_z0;
    board_cavity_top = min(seat + board_thick + 4, floor_top - 0.8);

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

        translate([0, board_y_shift, seat])
            linear_extrude(height = max(0.2, board_cavity_top - seat + 0.2))
                board_2d();

        under_board_ports(wall + 0.4);
        under_board_tunnels();

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
