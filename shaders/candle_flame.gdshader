// A candle's flame (Catalog._candle_flame): a small upright quad turned to the camera, drawn
// additively. A teardrop with a faint blue root just above the wick, a white-gold heart, a warm
// orange skin and a red tip; it sways in the draught, stretches and settles, and now and then
// gutters. `seed` (per candle) keeps every flame in its own time.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 3.4;
uniform vec4 col_core : source_color = vec4(1.0, 0.96, 0.84, 1.0);
uniform vec4 col_body : source_color = vec4(1.0, 0.62, 0.2, 1.0);
uniform vec4 col_tip : source_color = vec4(0.85, 0.22, 0.05, 1.0);
uniform vec4 col_root : source_color = vec4(0.25, 0.4, 1.0, 1.0);
instance uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float noise1(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

void vertex() {
	// upright, turned to the camera (as BILLBOARD_FIXED_Y does), keeping the node's scale
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float t = TIME + seed * 13.0;
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y); // x -1..1 across, y 0 at the wick .. 1 at the top
	// the draught: a slow sway and a quicker shiver, bending the top more than the root
	float sway = (noise1(t * 0.9) - 0.5) * 0.5 + (noise1(t * 4.3 + 7.0) - 0.5) * 0.18;
	// now and then it gutters: shorter and leaning for a moment
	float gutter = smoothstep(0.82, 0.97, noise1(t * 0.35 + 3.0));
	float stretch = 1.0 + (noise1(t * 2.7) - 0.5) * 0.18 - gutter * 0.25;
	float y = p.y / stretch;
	float x = p.x - (sway + gutter * 0.35) * y * y * 1.4;
	// the teardrop: round at the bottom, drawn out to a point at the top
	float r = 2.0 * pow(clamp(y * 1.4, 0.0, 1.0), 0.5) * pow(clamp(1.0 - y, 0.0, 1.0), 1.3);
	float d = abs(x) / max(r, 0.001);
	float inside = (1.0 - smoothstep(0.35, 1.0, d)) * step(0.0, y) * (1.0 - smoothstep(0.9, 1.0, y));
	// heat: the heart sits a third of the way up, in the middle
	float heart = (1.0 - smoothstep(0.0, 0.6, d)) * (1.0 - smoothstep(0.12, 0.55, abs(y - 0.33)));
	vec3 col = mix(col_tip.rgb, col_body.rgb, smoothstep(0.85, 0.35, y));
	col = mix(col, col_core.rgb, heart);
	// the blue root, just above the wick, round the outside
	float root = (1.0 - smoothstep(0.04, 0.2, y)) * smoothstep(0.2, 0.8, d);
	col = mix(col, col_root.rgb * 0.7, root);
	float a = clamp(inside * (0.8 + heart * 0.9) * (1.0 - root * 0.5), 0.0, 1.0);
	ALBEDO = col * intensity;
	ALPHA = a;
}
