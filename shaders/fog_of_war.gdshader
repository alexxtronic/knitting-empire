// The fog over land she hasn't explored yet (scripts/fog_of_war.gd). One quad that covers the
// screen: each pixel finds what it sees from the depth buffer, follows the view ray through a
// layer of ground fog `top` metres deep, and adds up how much unexplored land (fog_tex's alpha,
// one texel a cell of the explored grid) the ray crosses on the way. So the fog lies on the
// ground round trees and hills, thins where she has been, and you always see through it
// (max_alpha). Two kinds of lookup a sample, STEPS samples a pixel: cheap on every graphics level,
// and it needs no volumetric fog (which is off at Low).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 origin = vec2(-116.0, -120.0); // world x, z of fog_tex's corner
uniform vec2 size = vec2(280.0, 202.0); // metres it covers
uniform float top = 6.0; // the fog layer's height above the ground
uniform float density = 0.05; // optical depth a metre in full fog
uniform float max_alpha = 0.62; // never thicker than this: it only says "unexplored"
uniform float max_len = 90.0; // metres of ray counted at most (the sky, the far hills)
uniform vec3 color : source_color = vec3(0.84, 0.87, 0.91);

const int STEPS = 6;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0); // the whole screen, at the near plane
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// smooth value noise: the fog drifts in slow banks rather than lying flat
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 ndc = SCREEN_UV * 2.0 - 1.0;
	float d = texture(depth_tex, SCREEN_UV).r;
	vec4 hit = INV_PROJECTION_MATRIX * vec4(ndc, d, 1.0);
	vec4 nearp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0, 1.0); // reverse Z: 1 is the near plane
	vec3 a = (INV_VIEW_MATRIX * vec4(nearp.xyz / nearp.w, 1.0)).xyz;
	vec3 b = (INV_VIEW_MATRIX * vec4(hit.xyz / hit.w, 1.0)).xyz;
	vec3 dir = b - a;
	float len = length(dir);
	dir /= max(len, 0.0001);
	len = min(len, max_len);
	// the part of the ray under the fog's top
	float t0 = 0.0;
	float t1 = len;
	if (a.y > top) {
		if (dir.y >= -0.0001) {
			discard;
		}
		t0 = (top - a.y) / dir.y;
	} else if (dir.y > 0.0001) {
		t1 = min(t1, (top - a.y) / dir.y);
	}
	if (t1 <= t0) {
		discard;
	}
	float dt = (t1 - t0) / float(STEPS);
	float od = 0.0;
	float drift = TIME * 0.015;
	for (int i = 0; i < STEPS; i++) {
		vec3 p = a + dir * (t0 + (float(i) + 0.5) * dt);
		float f = texture(fog_tex, (p.xz - origin) / size).a;
		float h = 1.0 - smoothstep(0.0, top, p.y); // thickest on the ground
		float bank = 0.55 + 0.9 * vnoise(p.xz * 0.045 + vec2(drift, drift * 0.6));
		od += f * h * bank;
	}
	od *= dt * density;
	float alpha = (1.0 - exp(-od)) * max_alpha;
	if (alpha < 0.004) {
		discard;
	}
	ALBEDO = color;
	ALPHA = alpha;
}
