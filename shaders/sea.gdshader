// The sea off Saltmeadow Beach (scripts/regions.gd): turquoise over the sand near the shore,
// deep blue further out, rolling swell, a ragged line of foam where it meets the beach, and the
// sky in it at grazing angles.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.32, 0.62, 0.6);
uniform vec3 deep : source_color = vec3(0.07, 0.22, 0.36);
uniform float shore_z = 58.0; // where the water meets the sand (it lies to +z of this)
uniform float rain : hint_range(0.0, 1.0) = 0.0;

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

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 g = vec2(0.0);
	g += vec2(cos(p.x * 0.35 + t * 0.6), cos(p.y * 0.42 - t * 0.8)) * 0.07;
	g += vec2(cos(dot(p, vec2(1.3, -0.9)) - t * 1.3), cos(dot(p, vec2(-1.1, 1.7)) + t * 1.1)) * 0.04;
	g += vec2(vnoise(p * 2.0 + t * 0.5) - 0.5, vnoise(p * 2.0 - t * 0.4 + 5.0) - 0.5) * (0.06 + 0.1 * rain);
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float out_to_sea = clamp((p.y - shore_z) / 30.0, 0.0, 1.0);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 1.0, out_to_sea));
	// foam: a band at the shore that washes in and out, broken up by noise
	float wash = sin(t * 0.5 + p.x * 0.05) * 0.8;
	float band = 1.0 - smoothstep(0.0, 1.6, p.y - shore_z - wash);
	float foam = band * smoothstep(0.35, 0.75, vnoise(p * vec2(1.5, 3.0) + vec2(t * 0.3, 0.0)) + band * 0.4);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(col * (1.0 - fres * 0.4), vec3(0.95, 0.97, 0.95), foam * 0.85);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.6;
}
