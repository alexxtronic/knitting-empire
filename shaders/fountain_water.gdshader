// The plaza fountain's water: rings that spread from the middle and from where each of the
// `falls` streams lands, over a slow swell. town.gd puts it on the model's two water surfaces.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 shallow : source_color = vec3(0.36, 0.52, 0.48);
uniform vec3 deep : source_color = vec3(0.16, 0.3, 0.3);
uniform vec3 centre = vec3(0.0);
uniform float radius = 1.36;
uniform float land_radius = 0.885; // how far from the middle the falls land (0 = none)
uniform int falls = 8;

varying vec3 wpos;

// slope of a ring train spreading from `at`, fading with distance
vec2 rings(vec2 p, vec2 at, float freq, float speed, float reach, float t) {
	vec2 v = p - at;
	float r = max(length(v), 0.001);
	return (v / r) * cos(r * freq - t * speed) * exp(-r / reach);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz - centre.xz;
	float t = TIME;
	vec2 g = rings(p, vec2(0.0), 24.0, 4.0, 0.9, t) * 0.16;
	if (land_radius > 0.0) {
		for (int i = 0; i < falls; i++) {
			float a = PI / float(falls) + float(i) * TAU / float(falls);
			g += rings(p, vec2(cos(a), -sin(a)) * land_radius, 46.0, 7.0, 0.16, t + float(i) * 0.7) * 0.3;
		}
	}
	g += vec2(cos(p.x * 3.1 + t * 1.1), cos(p.y * 2.7 - t * 0.9)) * 0.03;
	vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float edge = clamp(length(p) / radius, 0.0, 1.0);
	vec3 col = mix(deep, shallow, smoothstep(0.2, 1.0, edge));
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// ring crests catch a little light, so the movement reads from the game camera
	float crest = clamp(length(g) * 2.2, 0.0, 1.0);
	ALBEDO = mix(col * (1.0 - fres * 0.5), vec3(0.78, 0.88, 0.84), crest * 0.35);
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
