// The ground: grass with patchy colour, worn earth on paths and round buildings.
// mask (R): 1 = grass, 0 = bare earth, covering mask_rect (x, z, width, depth) in world metres.
// Outside the rect it's all grass. Made by scripts/grass.gd.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 lush : source_color = vec3(0.24, 0.38, 0.13);
uniform vec3 dry : source_color = vec3(0.44, 0.47, 0.21);
uniform vec3 earth : source_color = vec3(0.4, 0.31, 0.21);
uniform sampler2D mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float season_dry : hint_range(0.0, 1.0) = 0.35;
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// God mode's painted roads (scripts/god_mode.gd), covering roads_rect like the mask: G = gravel,
// B = cobblestones (the stones are models; the ground under them is their cement). Black = none.
uniform sampler2D roads : filter_linear, repeat_disable, hint_default_black;
uniform vec4 roads_rect = vec4(0.0, 0.0, 1.0, 1.0);

uniform float patch_strength : hint_range(0.0, 1.0) = 1.0;

#include "res://shaders/grass_patches.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.07 + vec2(13.1, 7.7);
		a *= 0.5;
	}
	return v;
}

// Loose gravel: pebbles a few centimetres across, each its own shade of grey, dark in the gaps.
vec3 gravel(vec2 p, float soften) {
	vec2 q = p * 10.0;
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + vec2(17.3, 4.1)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = hash(i + g + vec2(5.1, 9.7));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	vec3 stone = mix(vec3(0.27, 0.25, 0.23), vec3(0.5, 0.47, 0.42), id);
	stone = mix(stone, vec3(0.42, 0.33, 0.25), step(0.84, id) * 0.8); // the odd brown one
	vec3 col = mix(vec3(0.15, 0.13, 0.11), stone, smoothstep(0.03, 0.22, d2 - d1));
	return mix(col, vec3(0.35, 0.33, 0.3), soften); // far away the pebbles blur into one grey
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.045);
	float mid = fbm(p * 0.35);
	float fine = vnoise(p * 9.0);
	float speck = vnoise(p * 31.0);
	// grass: big drifts between lush and dry, mid-scale clumps, fine blade speckle
	float d = clamp(smoothstep(0.3, 0.75, big) * 0.6 + season_dry * 0.55 - 0.15, 0.0, 1.0);
	vec3 g = mix(lush, dry, d);
	g *= 0.8 + 0.35 * mid;
	g *= 0.88 + 0.22 * speck;
	g = mix(g, g * vec3(1.1, 1.05, 0.7), smoothstep(0.82, 0.95, fine) * 0.4); // the odd yellow clover
	g = grass_patch_tint(g, grass_patches(p), patch_strength); // the blades' light and dark patches
	// earth: packed soil with pebbles and darker damp spots
	vec3 e = earth * (0.82 + 0.3 * mid) * (0.9 + 0.2 * speck);
	e = mix(e, vec3(0.55, 0.5, 0.44), smoothstep(0.9, 0.96, vnoise(p * 14.0)) * 0.3);
	// where's grass: the mask, with ragged edges from the noise
	vec2 mu = (p - mask_rect.xy) / mask_rect.zw;
	float m = 1.0;
	if (mu.x >= 0.0 && mu.y >= 0.0 && mu.x <= 1.0 && mu.y <= 1.0) {
		m = texture(mask, mu).r;
	}
	m = smoothstep(0.25, 0.75, m + (mid - 0.5) * 0.45 + (speck - 0.5) * 0.12);
	vec3 col = mix(e, g, m);
	float px_m = fwidth(p.x) + fwidth(p.y); // metres of ground one screen pixel covers
	vec2 ru = (p - roads_rect.xy) / roads_rect.zw;
	if (ru.x >= 0.0 && ru.y >= 0.0 && ru.x <= 1.0 && ru.y <= 1.0) {
		vec3 road = texture(roads, ru).rgb;
		if (road.g > 0.02) {
			float soften = clamp((px_m * 10.0 - 0.45) * 1.4, 0.0, 0.85);
			float edge = smoothstep(0.35, 0.65, road.g + (speck - 0.5) * 0.3);
			col = mix(col, gravel(p, soften) * (0.75 + 0.5 * mid) * (0.9 + 0.2 * speck), edge);
			m *= 1.0 - edge;
		}
		if (road.b > 0.02) {
			float edge = smoothstep(0.25, 0.5, road.b);
			col = mix(col, vec3(0.6, 0.58, 0.54) * (0.9 + 0.15 * speck), edge);
			m *= 1.0 - edge;
		}
	}
	col *= 1.0 - wet * 0.28;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.82, m) * (1.0 - wet * 0.55);
	SPECULAR = 0.3 + wet * 0.25;
	// a little surface relief so light catches the clumps
	float hx = fbm((p + vec2(0.05, 0.0)) * 0.9) - fbm((p - vec2(0.05, 0.0)) * 0.9);
	float hz = fbm((p + vec2(0.0, 0.05)) * 0.9) - fbm((p - vec2(0.0, 0.05)) * 0.9);
	vec3 n_world = normalize(vec3(-hx * 1.6, 1.0, -hz * 1.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	AO = mix(0.85, 1.0, mid);
}
