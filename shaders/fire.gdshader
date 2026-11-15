// A living fire for the fireplace (Catalog._fireplace_fire): each quad is one sheet of flame that
// turns round its upright axis to face the camera, drawn additively. Layered noise rises through
// it, faster near the top, and breaks the flame into licking tongues that part and join; the
// colour follows the heat, white-gold at the root, orange in the body, a deep red at the tips.
// `embers` (1.0) turns a flat quad into the bed of coals under the logs instead: a crackling glow
// that brightens and dims in patches. Every quad has its own `seed`, so no two burn in step.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float intensity = 1.45;
uniform float speed = 1.0;
uniform float width = 1.0; // how wide the flame's root is, of the quad's half-width
uniform float embers = 0.0; // 1.0: the coal bed (a flat quad) rather than a sheet of flame
uniform bool billboard_y = true;
uniform vec4 col_core : source_color = vec4(1.0, 0.93, 0.72, 1.0);
uniform vec4 col_body : source_color = vec4(1.0, 0.52, 0.12, 1.0);
uniform vec4 col_tip : source_color = vec4(0.62, 0.09, 0.02, 1.0);
instance uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	if (billboard_y && embers < 0.5) { // upright, turned to the camera (as BILLBOARD_FIXED_Y does)
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
}

void fragment() {
	float t = TIME * speed + seed * 17.0;
	if (embers > 0.5) {
		// the coal bed: glowing patches that crackle, dark seams between the coals, a soft edge
		vec2 q = UV * vec2(6.0, 3.0) + seed;
		float coals = fbm(q * 1.3 + vec2(0.0, t * 0.05));
		float crackle = fbm(q * 3.1 - vec2(t * 0.35, t * 0.2));
		float seams = smoothstep(0.32, 0.52, fbm(q * 2.2 + 4.0));
		float heat = clamp(coals * 1.25 * seams + (crackle - 0.5) * 0.7, 0.0, 1.0);
		vec2 c = UV * 2.0 - 1.0;
		float edge = 1.0 - smoothstep(0.55, 1.0, length(c * vec2(1.0, 1.15)));
		vec3 col = mix(col_tip.rgb * 0.6, col_body.rgb, smoothstep(0.25, 0.7, heat));
		col = mix(col, col_core.rgb, smoothstep(0.75, 1.0, heat));
		ALBEDO = col * intensity * (0.35 + heat);
		ALPHA = clamp(edge * smoothstep(0.08, 0.45, heat), 0.0, 1.0);
	} else {
	vec2 uv = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y); // x -1..1 across, y 0 at the root .. 1 at the top
	float y = uv.y;
	// the rising turbulence: slow broad billows and quick small licks, both stronger higher up
	float big = fbm(vec2(uv.x * 1.6 + seed, y * 2.2 - t * 1.7));
	float small = fbm(vec2(uv.x * 4.5 - seed, y * 5.5 - t * 3.6));
	float x = uv.x + (big - 0.5) * 0.9 * y + (small - 0.5) * 0.35 * y;
	// the flame's outline: a broad root narrowing to a tip, its top torn into tongues
	float w = width * mix(0.78, 0.08, pow(y, 0.7));
	float side = 1.0 - smoothstep(w * 0.45, w, abs(x));
	float top = y + (small - 0.5) * 0.55 * y + (big - 0.5) * 0.35;
	float body = side * (1.0 - smoothstep(0.25, 0.95, top));
	body *= smoothstep(0.0, 0.12, y); // the root fades into the logs
	// separate wisps break off and rise above the flame
	float wisp = smoothstep(0.62, 0.8, fbm(vec2(uv.x * 3.0 + seed * 3.0, y * 4.0 - t * 4.2))) * side * smoothstep(0.35, 0.7, y) * (1.0 - smoothstep(0.8, 1.0, y));
	float a = clamp(body + wisp * 0.6, 0.0, 1.0);
	// heat: hottest low in the middle, cooling outward and upward
	float heat = clamp(body * 1.3 - y * 0.7 - abs(x) * 0.6, 0.0, 1.0);
	vec3 col = mix(col_tip.rgb, col_body.rgb, smoothstep(0.05, 0.45, heat));
	col = mix(col, col_core.rgb, smoothstep(0.55, 0.95, heat));
	ALBEDO = col * intensity * (0.5 + heat * 0.7);
	ALPHA = a * 0.85;
	}
}
