shader_type spatial;
// The blue line on the ground to the objective she's tracking (scripts/objectives.gd). A flat ribbon
// a hand's breadth over the ground; UV.x is metres along the route, UV.y 0..1 across it.
// It draws over grass and the fog of war: its own depth test is against the depth buffer with room
// to spare (`hide_gap`), so blades and low things round it don't hide it but a wall or a tree in
// front does.
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled, shadows_disabled, depth_draw_never, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 colour : source_color = vec4(0.22, 0.58, 1.0, 0.95);
uniform vec4 glint : source_color = vec4(0.86, 0.95, 1.0, 1.0);
uniform float total = 10.0; // the route's length, m
uniform float hide_gap = 0.9; // m: anything nearer the camera than this in front of the line hides it
uniform float speed = 1.6; // m/s the chevrons flow toward the goal

varying float along;
varying float across;

void vertex() {
	along = UV.x;
	across = UV.y;
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 v = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	float scene_z = -v.z / v.w;
	float frag_z = -VERTEX.z;
	float hidden = smoothstep(hide_gap, hide_gap + 0.4, frag_z - scene_z);
	float x = abs(across * 2.0 - 1.0); // 0 on the middle line, 1 at the edges
	// chevrons pointing along the route, flowing on
	float c = fract((along - x * 0.35) * 0.9 - TIME * speed * 0.9);
	float chev = smoothstep(0.0, 0.12, c) * (1.0 - smoothstep(0.38, 0.5, c));
	float edge = 1.0 - smoothstep(0.72, 1.0, x);
	float rim = smoothstep(0.55, 0.8, x) * edge;
	float ends = smoothstep(0.4, 1.6, along) * (1.0 - smoothstep(total - 1.2, total, along));
	ALBEDO = mix(colour.rgb, glint.rgb, max(chev * 0.6, rim * 0.45));
	ALPHA = colour.a * edge * ends * mix(0.55, 1.0, chev) * (1.0 - hidden * 0.9);
}
