// Asphalt and concrete for Bretton Oaks' roads and driveways (scripts/suburb.gd): a flat colour
// mottled by world-space noise, with fine grit, and expansion joints across a slab every `joint`
// metres along `joint_dir` (0 for none). Two value-noise lookups and a hash a pixel: the roads
// cover little of the screen, but keep it cheap.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 col : source_color = vec3(0.3, 0.3, 0.29);
uniform float mottle = 0.12;
uniform float grit = 0.08;
uniform float rough = 0.92;
uniform float joint = 0.0;
uniform vec2 joint_dir = vec2(1.0, 0.0);
uniform vec2 joint_origin = vec2(0.0, 0.0);

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
	float m = vnoise(p * 0.35) * 0.65 + vnoise(p * 1.7 + 3.1) * 0.35;
	vec3 c = col * (1.0 - mottle * 0.5 + mottle * m);
	c *= 1.0 - grit * 0.5 + grit * hash(floor(p * 40.0));
	if (joint > 0.0) {
		float a = dot(p - joint_origin, normalize(joint_dir)) / joint;
		float d = abs(fract(a + 0.5) - 0.5) * joint;
		c *= mix(0.7, 1.0, smoothstep(0.012, 0.03, d));
	}
	ALBEDO = c;
	ROUGHNESS = rough;
}
