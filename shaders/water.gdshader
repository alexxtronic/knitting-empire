// The pond: slow ripples, the sky reflected at grazing angles, deeper colour in the middle,
// and rain rings when it rains (main.gd sets `rain`).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.34, 0.5, 0.48);
uniform vec3 deep : source_color = vec3(0.12, 0.26, 0.32);
uniform vec3 centre = vec3(0.0);
uniform float radius = 2.5;
uniform float rain : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 ripple_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(cos(p.x * 3.1 + t * 1.1), cos(p.y * 2.7 - t * 0.9)) * 0.06;
	g += vec2(cos(dot(p, vec2(2.3, -3.7)) - t * 1.7), cos(dot(p, vec2(-4.1, 1.9)) + t * 1.3)) * 0.04;
	return g;
}

// expanding rings where raindrops land, on a jittered grid
vec2 rain_grad(vec2 p, float t) {
	vec2 g = vec2(0.0);
	vec2 cell = floor(p * 2.2);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			float h = hash(c);
			float life = fract(t * 0.9 + h);
			vec2 at = (c + vec2(hash(c + 3.1), hash(c + 7.7))) / 2.2;
			vec2 v = p - at;
			float r = length(v);
			float ring = sin((r - life * 0.45) * 60.0) * smoothstep(0.08, 0.0, abs(r - life * 0.45)) * (1.0 - life);
			g += (v / max(r, 0.001)) * ring;
		}
	}
	return g * 0.35;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec2 g = ripple_grad(p, t);
	if (rain > 0.01) {
		g += rain_grad(p, t) * rain;
	}
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float edge = clamp(length(p - centre.xz) / radius, 0.0, 1.0);
	vec3 col = mix(deep, shallow, smoothstep(0.35, 1.0, edge));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = col * (1.0 - fres * 0.5);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// a lighter rim where the water meets the stones
	EMISSION = vec3(0.0);
	ALBEDO = mix(ALBEDO, ALBEDO * 1.35, smoothstep(0.88, 1.0, edge));
}
