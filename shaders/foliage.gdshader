// Tree canopies: the leaf colour comes per tree (instance uniform `tint`), with leafy noise
// patches, darker undersides, light glowing through at the edges, and a gentle sway in the
// wind that grows with height. main.gd sets `wind` (stronger in the rain).
shader_type spatial;
render_mode diffuse_burley;

instance uniform vec3 tint : source_color = vec3(0.8, 0.5, 0.2);
uniform float wind = 0.18;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wet : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying float wy;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y);
	return mix(a, b, u.z);
}

void vertex() {
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// canopies hang off a node at the tree's base, so world height above the ground is the lever
	float h = max(wpos.y - 1.6, 0.0);
	float t = TIME;
	float gust = 0.5 + 0.5 * sin(dot(root.xz, wind_dir) * 0.2 - t * 0.9);
	float sway = sin(t * 1.3 + root.x * 0.37 + root.z * 0.23) * 0.6 + gust * 0.8;
	float rustle = vnoise(wpos * 1.7 + vec3(t * 1.8)) - 0.5;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * sway * wind * h * 0.12;
	off += NORMAL * rustle * 0.05 * (0.5 + wind * 3.0);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	wy = NORMAL.y;
}

void fragment() {
	float n = vnoise(wpos * 2.6);
	float n2 = vnoise(wpos * 7.0);
	vec3 col = tint * (0.78 + 0.32 * n) * (0.9 + 0.15 * n2);
	col = mix(col, col * vec3(1.08, 1.04, 0.8), smoothstep(0.7, 0.9, n2) * 0.5); // sunny clusters
	col *= mix(0.62, 1.05, clamp(wy * 0.5 + 0.5, 0.0, 1.0)); // shaded underneath
	ALBEDO = col * (1.0 - wet * 0.15);
	ROUGHNESS = 0.8 - wet * 0.3;
	SPECULAR = 0.25;
	BACKLIGHT = tint * 0.35;
	// a bumpy leafy surface instead of a smooth ball
	float e = 0.08;
	vec3 g = vec3(vnoise(wpos * 3.5 + vec3(e, 0, 0)) - vnoise(wpos * 3.5 - vec3(e, 0, 0)),
		vnoise(wpos * 3.5 + vec3(0, e, 0)) - vnoise(wpos * 3.5 - vec3(0, e, 0)),
		vnoise(wpos * 3.5 + vec3(0, 0, e)) - vnoise(wpos * 3.5 - vec3(0, 0, e)));
	NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(g * 2.2, 0.0)).xyz);
	AO = 0.75 + 0.25 * n;
	AO_LIGHT_AFFECT = 0.3;
}
