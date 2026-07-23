// Dot enclosure v2 — CNC-style round head
// Display in front; UEDX6911 flat; HDMI + USB-C through the BACK under the board.
//
// part = "preview" | "front" | "back"
// Units: mm

/* [Which part] */
part = "preview"; // ["preview", "front", "back"]

/* [Outer — badge aesthetic] */
outer_d = 84;
chamfer = 2.2;          // front rim chamfer (reference look)
wall = 1.5;
overall_z = 18;         // thin target — raise if connectors need more

/* [Display] */
aa_d = 70.2;            // visible aperture
inner_glass_d = 73.5;   // glass / module pocket
bezel_lip = 1.8;        // black ring in front of glass
glass_pocket_z = 4.0;

/* [Driver board — connectors face rear] */
board_w = 66;
board_h = 58;
board_thick = 1.6;
board_clear_z = 8.5;    // air above PCB for chips; connectors go into back wall
board_corner_r = 2;
board_y_shift = 0;      // shift pocket if ports not centered

/* [Rear ports — under the board] */
// Positions are on the back face, XY centered on enclosure; tweak after measuring.
hdmi_w = 15.5;
hdmi_h = 6.2;
hdmi_x = -12;           // left of center
hdmi_y = -8;

usbc_w = 9.2;
usbc_h = 3.6;
usbc_x = 14;
usbc_y = -8;

port_inset = 0.35;      // clearance around metal shells

/* [Rear mount boss] */
mount_boss_d = 14;
mount_boss_h = 3.5;
mount_hole_d = 4.2;     // M4 clearance / ball stud

/* [Fit] */
tolerance = 0.3;
screw_d = 2.2;
screw_circle = 34;      // radius to screw bosses

$fn = 128;

function front_z() = bezel_lip + glass_pocket_z + 1.0;
function back_z() = max(overall_z - front_z(), board_clear_z + wall + 2.5);

module chamfered_disc(d, h, ch) {
    // Cylinder with front (z=h) outer chamfer
    hull() {
        translate([0, 0, 0]) cylinder(d = d, h = max(0.2, h - ch));
        translate([0, 0, h - 0.01]) cylinder(d = d - 2 * ch, h = 0.01);
    }
}

module board_2d() {
    offset(r = board_corner_r)
        square([
            board_w - 2 * board_corner_r + 2 * tolerance,
            board_h - 2 * board_corner_r + 2 * tolerance
        ], center = true);
}

module screw_bosses(h) {
    for (a = [45, 135, 225, 315])
        rotate([0, 0, a])
            translate([screw_circle, 0, 0])
                cylinder(d = 6.5, h = h);
}

module screw_holes(h) {
    for (a = [45, 135, 225, 315])
        rotate([0, 0, a])
            translate([screw_circle, 0, -0.1])
                cylinder(d = screw_d, h = h + 0.2);
}

// ---------- FRONT ----------
module front() {
    z = front_z();
    difference() {
        union() {
            chamfered_disc(outer_d, z, chamfer);
            screw_bosses(z);
        }
        // AA window
        translate([0, 0, -0.1])
            cylinder(d = aa_d, h = z + 0.2);
        // glass pocket behind lip
        translate([0, 0, bezel_lip])
            cylinder(d = inner_glass_d + 2 * tolerance, h = glass_pocket_z + 0.3);
        screw_holes(z);
    }
}

// ---------- BACK (ports through rear wall) ----------
module back() {
    z = back_z();
    difference() {
        union() {
            cylinder(d = outer_d, h = z);
            screw_bosses(z);
            // center mount boss on outer back (z=0 is mating face to front)
            translate([0, 0, -mount_boss_h])
                cylinder(d = mount_boss_d, h = mount_boss_h + 0.01);
        }

        // main cavity from mating face
        translate([0, 0, wall])
            cylinder(d = outer_d - 2 * wall, h = z);

        // board pocket (board sits above rear wall; connectors enter cutouts)
        translate([0, board_y_shift, wall])
            linear_extrude(height = board_clear_z + 0.6)
                board_2d();

        // --- HDMI + USB-C through BACK (z ≈ 0 face is toward front; outer back is z=0 of boss)
        // Cut from outside back: in this model mating face is z=z (top when printing
        // inner-up). Flip convention: we cut from z=-mount through wall.
        // Simpler: cutouts along -Z from z=0 plane of the back part (outer skin at z=0).
        // Rebuild: treat z=0 as OUTER back, z=z as rim toward front.
    }
}

// Remodel back with clear outer/inner orientation:
// z=0 = outer back (ports visible), z=back_z = rim that meets the front.
module back_v2() {
    z = back_z();
    difference() {
        union() {
            cylinder(d = outer_d, h = z);
            // mount boss on outer back
            translate([0, 0, -mount_boss_h + 0.01])
                cylinder(d = mount_boss_d, h = mount_boss_h);
            for (a = [45, 135, 225, 315])
                rotate([0, 0, a])
                    translate([screw_circle, 0, 0])
                        cylinder(d = 6.5, h = z);
        }

        // cavity from inside (toward front)
        translate([0, 0, wall])
            cylinder(d = outer_d - 2 * wall, h = z + 0.1);

        // board pocket under the cavity floor+wall — board lies parallel to back
        translate([0, board_y_shift, wall])
            linear_extrude(height = board_clear_z + 1)
                board_2d();

        // Port windows through outer back wall (under the board)
        translate([hdmi_x, hdmi_y, -0.1])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, wall + 0.3], center = true);
        translate([usbc_x, usbc_y, -0.1])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, wall + 0.3], center = true);

        // deepen port channels into board pocket so shells seat
        translate([hdmi_x, hdmi_y, wall - 0.05])
            cube([hdmi_w + 2 * port_inset, hdmi_h + 2 * port_inset, board_clear_z], center = true);
        translate([usbc_x, usbc_y, wall - 0.05])
            cube([usbc_w + 2 * port_inset, usbc_h + 2 * port_inset, board_clear_z], center = true);

        // mount through-hole
        translate([0, 0, -mount_boss_h - 0.1])
            cylinder(d = mount_hole_d, h = mount_boss_h + wall + 0.3);

        // micro vents (optional, keep clean look — short slots)
        for (x = [-16, 0, 16])
            translate([x, 18, -0.05])
                cube([8, 1.6, wall + 0.2], center = true);

        // screws
        for (a = [45, 135, 225, 315])
            rotate([0, 0, a])
                translate([screw_circle, 0, -0.1])
                    cylinder(d = screw_d, h = z + 0.2);
    }
}

module preview_stack() {
    // Front at top
    color("silver")
        translate([0, 0, back_z() + 0.5])
            front();
    color("gainsboro")
        back_v2();
    // ghost AA
    color("black", 0.4)
        translate([0, 0, back_z() + 0.5 + bezel_lip])
            cylinder(d = aa_d, h = 0.5);
    // ghost board
    color("green", 0.45)
        translate([0, board_y_shift, wall + 1])
            linear_extrude(height = board_thick)
                square([board_w, board_h], center = true);
    // ghost ports
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
