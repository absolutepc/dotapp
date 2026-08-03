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
// Ø74 fits board 51.7×47.15 (diag ~70). Measured display Ø83 does NOT fit Ø74 —
// glass/AA below are nested for an Ø74 shell (use a ≤~70 AA panel, or raise outer_d).
outer_d = 74;
chamfer = 1.2;
wall = 1.2;             // ≥1.2 mm aluminum in production
// Head Z sized so mini-HDMI adapter (26 mm from PCB) can sit flush at the rear face.
overall_z = 34;

/* [Front — bezel + glass (optical bond target)] */
// Provisional nest inside Ø74 (not the earlier Ø83 panel).
aa_d = 68;
glass_od = 71;
glass_thick = 1.1;
glue_w = 1.0;
bezel_lip = 0.7;
lcd_pocket_z = 3.2;

/* [Driver board — connectors face rear] */
// Measured PCB: 51.7 × 47.15 mm (diag ~70 → fits Ø74 with wall 1.2).
board_w = 51.7;
board_h = 47.15;
board_thick = 1.6;
board_clear_z = 6;
board_corner_r = 2;
board_y_shift = 0;

/* [Rear ports — flush exits; mini-HDMI adapter body inside] */
// Mini-HDMI adapter protrudes 26 mm from the PCB toward the rear.
// Board seat is recessed so only the port opening shows on the outside.
hdmi_adapter_len = 26;  // from PCB to flush rear face
hdmi_w = 11.5;          // mini-HDMI opening (caliper your plug)
hdmi_h = 8.5;
hdmi_x = -10;
hdmi_y = -8;

usbc_w = 9.2;
usbc_h = 3.6;
usbc_x = 12;
usbc_y = -8;

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
// Rear depth: recess board so mini-HDMI (hdmi_adapter_len) ends flush at z=0.
function board_seat_z() = hdmi_adapter_len;
function back_z() = max(
    overall_z - front_z(),
    board_seat_z() + board_thick + 2
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

// Flush port windows — opening size only (no external adapter bodies in the model)
module rear_ports(through_z) {
    translate([hdmi_x, hdmi_y, -0.1])
        cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, through_z], center = true);
    translate([usbc_x, usbc_y, -0.1])
        cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, through_z], center = true);
}

// Clearance tunnels from flush rear face up to the recessed board / adapter
module port_tunnels() {
    translate([hdmi_x, hdmi_y, board_seat_z() / 2])
        cube([
            hdmi_w + 2 * port_inset,
            hdmi_h + 2 * port_inset,
            board_seat_z() + 0.2
        ], center = true);
    translate([usbc_x, usbc_y, board_seat_z() / 2])
        cube([
            usbc_w + 2 * port_inset,
            usbc_h + 2 * port_inset,
            board_seat_z() + 0.2
        ], center = true);
}

// Thin face markers so openings read in preview (not dongle bodies)
module ghost_port_exits() {
    color("royalblue", 0.85)
        translate([hdmi_x, hdmi_y, -0.15])
            cube([hdmi_w, hdmi_h, 0.3], center = true);
    color("orange", 0.85)
        translate([usbc_x, usbc_y, -0.15])
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
// z=0 outer back (flush mini-HDMI / USB-C exits); board recessed at board_seat_z().
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

        // Board seating pocket above the recessed plane
        translate([0, board_y_shift, seat])
            linear_extrude(height = z - seat + 0.1)
                board_2d();

        rear_ports(wall + 0.4);
        port_tunnels();

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
        translate([0, board_y_shift, board_seat_z() + 0.2])
            linear_extrude(height = board_thick)
                square([board_w, board_h], center = true);
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
    seat = board_seat_z();
    floor_top = lcd_z0;
    // Board pocket from recessed seat up, leave a solid floor under the LCD
    board_cavity_top = min(seat + board_clear_z + board_thick + 2, floor_top - 0.8);

    difference() {
        union() {
            chamfered_disc(outer_d, z, chamfer);
            translate([0, 0, -mount_boss_h + 0.01])
                cylinder(d = mount_boss_d, h = mount_boss_h);
        }

        // --- front: AA, glass seat, LCD ---
        translate([0, 0, glass_z0 + glass_thick - 0.05])
            cylinder(d = aa_d, h = bezel_lip + 0.2);
        translate([0, 0, glass_z0])
            cylinder(d = glass_od + 2 * tolerance, h = glass_thick + 0.05);
        translate([0, 0, lcd_z0 - 0.05])
            cylinder(d = lcd_d + 2 * tolerance, h = lcd_pocket_z + 0.15);

        // FPC stays inside the LCD pocket — no side wall cutout.

        // --- rear: recessed board + mini-HDMI tunnel (26 mm) ---
        translate([0, board_y_shift, seat])
            linear_extrude(height = max(0.2, board_cavity_top - seat + 0.2))
                board_2d();

        rear_ports(wall + 0.4);
        port_tunnels();

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
