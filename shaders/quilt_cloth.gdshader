// The quilt over Nora while she sleeps (scripts/player.gd lie_in_bed): woven cloth with padded
// patches, and soft movement. This is a shader, not a cloth solver: when she lies down the quilt
// settles onto her in a few damped ripples spreading from her chest, and afterwards it rises
// and falls a little with her breathing. `age` is the seconds since she lay down.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool textured = true;
uniform vec3 base_color : source_color = vec3(0.93, 0.87, 0.74); // used when not textured (the sheet)
uniform vec2 patches = vec2(5.0, 7.0); // the quilt texture's patch grid; a padded pillow in each
uniform float puff = 1.0;        // 0 for plain sheet
uniform vec2 thread_scale = vec2(110.0, 120.0); // threads across and along the cover
uniform float age = 10.0;
uniform float breath = 0.0;      // 0..1, fades in once she has settled

varying vec2 cloth_uv;

float settle_drop(vec2 uv, float mask) {
	// the wave starts at her chest end (uv.y = 0) and runs down the bed and out to the sides
	float delay = uv.y * 0.22 + abs(uv.x - 0.5) * 0.35;
	float t = max(age - delay, 0.0);
	float fall = 0.035 * exp(-5.0 * t) * cos(9.0 * t);          // dropping onto her, with a small bounce
	float ripple = 0.006 * exp(-4.0 * t) * sin(24.0 * t - uv.y * 10.0);
	return (fall + ripple) * mask;
}

void vertex() {
	cloth_uv = UV;
	float mask = COLOR.r; // 1 over her body, 0 where the quilt rests on the mattress
	VERTEX.y += settle_drop(UV, mask);
	VERTEX.y += breath * mask * 0.011 * sin(TIME * 1.55 - UV.y * 2.5) * smoothstep(0.0, 0.5, UV.y + 0.15);
}

void fragment() {
	vec2 uv = cloth_uv;
	vec3 col = textured ? texture(albedo_tex, uv).rgb : base_color;

	// padded patches: a pillow in each, pinched at the seams
	vec2 f = fract(uv * patches);
	float pillow = sin(3.14159 * f.x) * sin(3.14159 * f.y);
	vec2 g_puff = vec2(patches.x * 3.14159 * cos(3.14159 * f.x) * sin(3.14159 * f.y),
					   patches.y * 3.14159 * sin(3.14159 * f.x) * cos(3.14159 * f.y)) * puff;

	// plain weave: threads that go over and under, fading out when they get smaller than a pixel
	vec2 w = uv * thread_scale;
	float a = 3.14159 * w.x;
	float b = 3.14159 * w.y;
	vec2 g_weave = vec2(thread_scale.x * 3.14159 * cos(a) * sin(b), thread_scale.y * 3.14159 * sin(a) * cos(b));
	float fade = 1.0 - smoothstep(0.25, 0.6, max(fwidth(w.x), fwidth(w.y)));
	float weave = sin(a) * sin(b);

	vec2 slope = g_puff * 0.012 + g_weave * 0.0016 * fade;
	NORMAL_MAP = normalize(vec3(-slope, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	float shade = mix(1.0, 0.8 + 0.2 * pillow, puff);
	ALBEDO = col * shade * (1.0 + 0.05 * weave * fade);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	RIM = 0.45;     // the soft fuzz that catches light at grazing angles, as on real cloth
	RIM_TINT = 0.7;
}
