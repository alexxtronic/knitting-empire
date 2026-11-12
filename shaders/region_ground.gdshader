// The ground of one of the lands round the farm (scripts/regions.gd, data/regions.json): three
// colours mixed by large and small noise, fading at its edges into the farm's grass, and
// darker and wetter below `wet_below` (the beach under the tide line).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 col_a : source_color = vec3(0.3, 0.4, 0.2);
uniform vec3 col_b : source_color = vec3(0.35, 0.42, 0.22);
uniform vec3 col_c : source_color = vec3(0.4, 0.38, 0.3);
uniform vec3 edge_col : source_color = vec3(0.24, 0.38, 0.13); // the grass round it (ground.gdshader's lush)
uniform vec4 rect = vec4(0.0, 0.0, 1.0, 1.0); // x, z, width, depth of the patch in world metres
uniform float fade = 9.0; // metres over which the edge blends away
uniform float wet_below = -100.0;
uniform float wet : hint_range(0.0, 1.0) = 0.0; // rain

varying vec3 wpos;

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
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float big = fbm(p * 0.06);
	float small = fbm(p * 0.55 + 7.0);
	vec3 c = mix(col_a, col_b, smoothstep(0.3, 0.7, big));
	c = mix(c, col_c, smoothstep(0.5, 0.8, small) * 0.7);
	c *= 0.92 + 0.16 * vnoise(p * 3.1);
	// below the tide line: wet, darker, shinier
	float under = smoothstep(wet_below + 0.05, wet_below - 0.25, wpos.y);
	c = mix(c, c * 0.62, under);
	// the edge: a ragged line blending into the grass, then gone
	vec2 d = min(p - rect.xy, rect.xy + rect.zw - p);
	float e = min(d.x, d.y) + (fbm(p * 0.12) - 0.5) * fade * 0.9;
	float k = smoothstep(0.0, fade, e);
	if (k < 0.04 + 0.08 * hash(floor(p * 9.0))) {
		discard;
	}
	ALBEDO = mix(edge_col, c, k) * (1.0 - 0.25 * wet);
	ROUGHNESS = mix(0.95, 0.35, max(under, wet * 0.6));
	SPECULAR = 0.3;
}
