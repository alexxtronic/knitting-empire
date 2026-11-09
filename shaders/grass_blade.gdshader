// One grass blade per MultiMesh instance (scripts/grass.gd). The blade mesh is 1 m tall with
// UV.y = 0 at the root and 1 at the tip; INSTANCE_CUSTOM.r is its height in metres, .g a random
// 0..1 used for colour. Instances carry only a yaw rotation, so the inverse is a transpose.
// Wind sways each blade, with slow gusts rolling across the field; blades near `pusher`
// (Nora) bend away from her.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 root_col : source_color = vec3(0.16, 0.26, 0.09);
uniform vec3 tip_lush : source_color = vec3(0.36, 0.55, 0.2);
uniform vec3 tip_dry : source_color = vec3(0.6, 0.6, 0.29);
uniform float season_dry : hint_range(0.0, 1.0) = 0.35;
uniform float wind = 0.18;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform vec3 pusher = vec3(0.0, -100.0, 0.0);
uniform float push_radius = 0.75;
uniform float wet : hint_range(0.0, 1.0) = 0.0;

varying float h;
varying float tint;
varying float rnd;

void vertex() {
	h = UV.y;
	float height = INSTANCE_CUSTOM.r;
	rnd = INSTANCE_CUSTOM.g;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = VERTEX;
	v.y *= height;
	v.xz *= 0.9 + height * 0.6;
	// wind: a per-blade flutter plus broad gusts travelling along wind_dir
	float t = TIME;
	float gust = sin(dot(root.xz, wind_dir) * 0.28 - t * 1.25);
	gust = 0.5 + 0.5 * gust;
	gust *= gust;
	float flutter = sin(t * 2.6 + rnd * 6.283 + root.x * 0.9) * 0.3 + sin(t * 4.1 + root.z * 1.3) * 0.12;
	vec2 bend = wind_dir * (gust * 1.4 + flutter + 0.35) * wind;
	// pushed aside by whoever walks through
	vec2 away = root.xz - pusher.xz;
	float d = length(away);
	float push = 1.0 - smoothstep(push_radius * 0.3, push_radius, d);
	bend += (away / max(d, 0.001)) * push * 0.9;
	float k = h * h;
	vec3 off = vec3(bend.x, 0.0, bend.y) * k * height;
	off.y = -length(off.xz) * 0.55; // a bent blade gets shorter
	v += transpose(mat3(MODEL_MATRIX)) * off;
	VERTEX = v;
	tint = gust;
}

void fragment() {
	vec3 tip = mix(tip_lush, tip_dry, clamp(season_dry + (rnd - 0.5) * 0.5, 0.0, 1.0));
	vec3 col = mix(root_col, tip, smoothstep(0.0, 1.0, h));
	col *= 0.88 + rnd * 0.22;
	col *= 1.0 + tint * 0.08; // gusts flash the blades a touch lighter
	col *= 1.0 - wet * 0.2;
	ALBEDO = col;
	ROUGHNESS = 0.55 - wet * 0.2;
	SPECULAR = 0.3;
	BACKLIGHT = vec3(0.14, 0.2, 0.05) * h;
	AO = mix(0.35, 1.0, h);
	AO_LIGHT_AFFECT = 0.4;
	// soften the flat-card look: lean the normal toward the sky
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, 0.55));
}
