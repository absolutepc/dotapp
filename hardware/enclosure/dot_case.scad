// Dot enclosure — CNC-style round head
// Production intent: CNC unibody aluminum (chem polish → hand polish → coat)
// Prototype: split front/back PETG to prove glass bond + rear ports
// Architecture: thin head (display+UEDX6911) + remote Pi/power box
// FRONT: bezel + optically bonded cover glass + LCD pocket
// BACK / unibody rear: HDMI + USB-C under the board
//
// part = "preview" | "front" | "back" | "unibody"
// Units: mm

/* [Which part] */
part = "preview"; // ["preview", "front", "back", "unibody"]

/* [Outer — unibody silhouette] */
outer_d = 84;
chamfer = 1.6;
wall = 1.5;             // ≥1.2 mm aluminum in production
overall_z = 18;         // lock after measuring rear connector stick-out

/* [Front — bezel + glass (optical bond target)] */
aa_d = 70.2;
glass_od = 73.5;
glass_thick = 1.1;
glue_w = 1.2;           // seat shelf under glass rim (optical bond in production)
bezel_lip = 0.9;
lcd_pocket_z = 3.2;
fpc_slot_w = 22;
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

module rear_ports(through_z) {
    translate([hdmi_x, hdmi_y, -0.1])
        cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, through_z], center = true);
    translate([usbc_x, usbc_y, -0.1])
        cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, through_z], center = true);
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

        translate([0, -(glass_od / 2) + 2, lcd_z0 - 0.1])
            cube([fpc_slot_w, 12, fpc_slot_h + lcd_pocket_z], center = true);

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
// z=0 outer back; z=back_z() mates to front
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

        rear_ports(wall + 0.3);
        translate([hdmi_x, hdmi_y, wall - 0.05])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, board_clear_z], center = true);
        translate([usbc_x, usbc_y, wall - 0.05])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, board_clear_z], center = true);

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);

        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z + 0.2);
    }
}

// ---------- UNIBODY (production aluminum puck) ----------
// z=0 = outer back (ports); z=unibody_z() = visible front face
// Front pockets milled from +Z; board + ports from -Z / through rear wall.
module unibody() {
    z = unibody_z();
    glass_z0 = z - bezel_lip - glass_thick;
    lcd_z0 = glass_z0 - lcd_pocket_z;
    lcd_d = glass_od - 2 * glue_w;
    // Mid floor thickness between LCD pocket and board cavity
    floor_top = lcd_z0;
    board_cavity_h = board_clear_z + 1.0;
    // Keep a solid floor: board cavity rises from wall up, stops below floor_top
    board_cavity_top = min(wall + board_cavity_h, floor_top - 0.8);

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

        // FPC channel toward rim
        translate([0, -(glass_od / 2) + 2, lcd_z0 - 0.1])
            cube([fpc_slot_w, 12, fpc_slot_h + lcd_pocket_z], center = true);

        // --- rear: board pocket under floor ---
        translate([0, 0, wall])
            cylinder(d = outer_d - 2 * wall, h = max(0.2, board_cavity_top - wall));

        translate([0, board_y_shift, wall])
            linear_extrude(height = max(0.2, board_cavity_top - wall + 0.2))
                board_2d();

        // HDMI + USB-C through rear wall (under board)
        rear_ports(wall + 0.3);
        translate([hdmi_x, hdmi_y, wall - 0.05])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, board_clear_z], center = true);
        translate([usbc_x, usbc_y, wall - 0.05])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, board_clear_z], center = true);

        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);
    }
}

module preview_stack() {
    color("DimGray")
        translate([0, 0, back_z() + 0.4])
            front();
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
else if (part == "unibody") unibody();
else preview_stack();
