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

uniform float patch_strength : hint_range(0.0, 1.0) = 1.0;

#include "res://shaders/grass_patches.gdshaderinc"

#include "res://shaders/ground_hole.gdshaderinc"

// god mode's painted roads: dirt, gravel, cobbles, pavement and sidewalk (roads, roads_rect)
#include "res://shaders/painted_roads.gdshaderinc"

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

// vnoise with its slope: (value, d/dx, d/dy) from the same four corners
vec3 vnoise_d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	vec2 du = 6.0 * f * (1.0 - f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	float k = a - b - c + d;
	return vec3(a + (b - a) * u.x + (c - a) * u.y + k * u.x * u.y, du.x * (b - a + k * u.y), du.y * (c - a + k * u.x));
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

void fragment() {
	vec2 p = wpos.xz;
	if (in_ground_hole(p)) {
		discard;
	}
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
	float px_m0 = fwidth(p.x) + fwidth(p.y); // metres of ground one screen pixel covers
	// close up, a fine thatch of blade streaks in the turf between the blades (two directions, so it
	// doesn't read as stripes); it fades out before it could shimmer in the distance
	float thatch_k = 1.0 - smoothstep(0.012, 0.04, px_m0);
	if (thatch_k > 0.0) {
		vec2 q1 = vec2(p.x * 0.8 + p.y * 0.6, -p.x * 0.6 + p.y * 0.8);
		float th = vnoise(q1 * vec2(42.0, 9.0)) * 0.55 + vnoise(vec2(q1.y, -q1.x) * vec2(37.0, 8.0) + 3.7) * 0.45;
		g *= 1.0 + (th - 0.5) * 0.34 * thatch_k;
	}
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
	// inside the mask its own earth already shows the painted dirt (grass.gd), so only out past it
	// does the dirt come from the road map
	bool in_mask = mu.x >= 0.0 && mu.y >= 0.0 && mu.x <= 1.0 && mu.y <= 1.0;
	float bare;
	col = painted_roads(p, col, in_mask ? col : e, speck, mid, px_m, bare);
	m *= 1.0 - bare;
	col *= 1.0 - wet * 0.28;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.82, m) * (1.0 - wet * 0.55);
	SPECULAR = 0.3 + wet * 0.25;
	// a little surface relief so light catches the clumps: two octaves are all that shows at this
	// scale. Their slopes come straight from the noise (it was eight lookups for finite differences;
	// the same relief for a quarter of the work, which mattered: the ground fills most of the screen)
	vec2 rp = p * 0.9;
	vec2 s1 = vnoise_d(rp).yz;
	vec2 s2 = vnoise_d(rp * 2.07 + vec2(13.1, 7.7)).yz;
	vec2 hs = 0.5 * (0.09 * s1 + 0.093 * s2);
	float hx = hs.x;
	float hz = hs.y;
	vec3 n_world = normalize(vec3(-hx * 1.6, 1.0, -hz * 1.6));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	AO = mix(0.85, 1.0, mid);
}
