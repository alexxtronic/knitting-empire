// A hole in the ground (scripts/split_house.gd): while Nora is down in the Bretton Oaks basement the
// ground over it isn't drawn, so the camera can look down into the rooms. Shared by ground.gdshader,
// region_ground.gdshader and grass_blade.gdshader. The globals are in project.godot [shader_globals].
// ground_hole_a: the house's origin (x, z) and its turn (cos, sin); ground_hole_b and _c: the hole, two
// rects in the house's own space (x0, z0, x1, z1), all zero when there is none.
global uniform vec4 ground_hole_a;
global uniform vec4 ground_hole_b;
global uniform vec4 ground_hole_c;

bool in_ground_hole(vec2 p) {
	vec2 q = p - ground_hole_a.xy;
	vec2 l = vec2(q.x * ground_hole_a.z - q.y * ground_hole_a.w, q.x * ground_hole_a.w + q.y * ground_hole_a.z);
	return (l.x > ground_hole_b.x && l.x < ground_hole_b.z && l.y > ground_hole_b.y && l.y < ground_hole_b.w)
		|| (l.x > ground_hole_c.x && l.x < ground_hole_c.z && l.y > ground_hole_c.y && l.y < ground_hole_c.w);
}
