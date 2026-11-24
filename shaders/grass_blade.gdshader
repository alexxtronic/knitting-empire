// One grass blade per MultiMesh instance (scripts/grass.gd). The blade mesh is 1 m tall with
// UV.y = 0 at the root and 1 at the tip; INSTANCE_CUSTOM.r is its height in metres, .g a random
// 0..1 used for colour, .b the land it grows in (index + how far into it, grass.gd _outer_amount:
// 0 is the farm and town), .a 1 for a stem gone to seed. Instances carry only a yaw rotation, so
// the inverse is a transpose.
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
uniform float patch_strength : hint_range(0.0, 1.0) = 1.0; // the light and dark patches (grass_patches.gdshaderinc)
// the ground's own grass colours (ground.gdshader): a blade's root takes the turf's colour under it, so
// the blades read as the turf growing up rather than dark sticks laid on it
uniform vec3 lush : source_color = vec3(0.24, 0.38, 0.13);
uniform vec3 dry : source_color = vec3(0.44, 0.47, 0.21);
// blades sink into the turf over the last few metres before the chunks stop drawing (grass.gd's range),
// so the edge of the grass doesn't pop
uniform float fade_end = 46.0;
// far grass is thinned (grass.gd _keep_at): out from thin_near fewer blades are drawn, down to
// thin_keep of them at fade_end, each widened so the turf looks as full
uniform float thin_near = 16.0;
uniform float thin_keep = 1.0;
// the patches baked once over grass.gd's REGION (grass_patch_bake.gdshader); until the bake has drawn,
// each blade works its patch out itself
uniform sampler2D patch_tex : filter_linear, repeat_disable;
uniform vec4 patch_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool patch_baked = false;
// each land's blades take its ground's colour (grass.gd set_lands): a tint over the farm's colours
uniform vec3 land_tint[8];
// a streamed square drawn leaner (grass.gd outer_frac, outer_reach): its blades widened by x, its range a share y
instance uniform vec2 lean = vec2(1.0, 1.0);
uniform float frac_widen = 1.0; // the level draws a share of the blades (grass.gd set_quality): each this much wider
uniform vec3 seed_col : source_color = vec3(0.78, 0.72, 0.52); // a seed head's pale tip
uniform vec3 straw : source_color = vec3(0.66, 0.6, 0.34); // a blade's sun-dried tip

#include "res://shaders/grass_patches.gdshaderinc"

#include "res://shaders/ground_hole.gdshaderinc"

varying float h;
varying float tint;
varying float rnd;
varying vec2 gpatch;
varying vec3 ltint;
varying float lk;
varying float seedy;

void vertex() {
	h = UV.y;
	float height = INSTANCE_CUSTOM.r;
	rnd = INSTANCE_CUSTOM.g;
	float land = INSTANCE_CUSTOM.b;
	int li = clamp(int(floor(land)), 0, 7);
	lk = li == 0 ? 0.0 : fract(land);
	ltint = mix(vec3(1.0), land_tint[li], lk);
	seedy = INSTANCE_CUSTOM.a;
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (patch_baked) {
		gpatch = textureLod(patch_tex, (root.xz - patch_rect.xy) / patch_rect.zw, 0.0).rg * 2.0 - 1.0;
	} else {
		gpatch = grass_patches(root.xz);
	}
	float far = length(root - INV_VIEW_MATRIX[3].xyz);
	float fend = fade_end * lean.y;
	height *= 1.0 - smoothstep(fend - 14.0 * lean.y, fend - 2.0, far);
	vec3 v = VERTEX;
	v.y *= height;
	v.xz *= 0.9 + height * 0.6;
	float keep = mix(1.0, thin_keep, smoothstep(thin_near, fend, far));
	v.x *= inversesqrt(keep) * lean.x * frac_widen; // fewer blades, each a little wider
	// wind: a per-blade flutter plus broad gusts travelling along wind_dir
	float t = TIME;
	// two trains of gusts at different scales and a little apart in heading, so the waves rolling over
	// a field break up rather than marching in rows
	float gust = sin(dot(root.xz, wind_dir) * 0.28 - t * 1.25) * 0.65
		+ sin(dot(root.xz, vec2(wind_dir.x * 0.94 - wind_dir.y * 0.34, wind_dir.y * 0.94 + wind_dir.x * 0.34)) * 0.083 - t * 0.53) * 0.35;
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
	VERTEX = in_ground_hole(root.xz) ? vec3(0.0) : v; // none over the basement while she's down there
	tint = gust;
}

void fragment() {
	// the lands' ground keeps its colour through the year, so their blades dry less with the season
	float sdry = season_dry * (1.0 - 0.7 * lk);
	float dryness = clamp(sdry + (rnd - 0.5) * 0.5, 0.0, 1.0);
	vec3 tip = mix(tip_lush, tip_dry, dryness);
	// the root: the turf's colour where it stands, a shade deeper (the ground's own mix of lush and dry)
	vec3 turf = mix(lush, dry, clamp(sdry * 0.55 + 0.1, 0.0, 1.0)) * 0.82;
	vec3 base = mix(root_col, turf, 0.7);
	vec3 col = mix(base, tip, smoothstep(0.0, 0.85, h));
	// each blade its own hue: some warmer and yellower, some cooler and bluer
	float hue = fract(rnd * 7.31) - 0.5;
	col *= vec3(1.0 + hue * 0.16, 1.0 + hue * 0.04, 1.0 - hue * 0.2);
	col *= 0.9 + rnd * 0.2;
	// sun-dried tips on some blades, more of them as the season dries; a stem gone to seed is pale at the top
	float burn = (step(0.8, fract(rnd * 13.7)) * 0.45 + sdry * 0.12) * smoothstep(0.75, 1.0, h);
	col = mix(col, straw, burn);
	col = mix(col, seed_col, seedy * smoothstep(0.72, 0.9, h));
	col *= ltint;
	col = grass_patch_tint(col, gpatch, patch_strength * (1.0 - lk)); // the lands' ground has its own patches
	col *= 1.0 + tint * 0.08; // gusts flash the blades a touch lighter
	col *= 1.0 - wet * 0.2;
	ALBEDO = col;
	ROUGHNESS = 0.55 - wet * 0.2;
	SPECULAR = 0.3;
	// sunlight through a thin blade: warm yellow-green glow toward the tip when the sun is behind it
	BACKLIGHT = vec3(0.36, 0.42, 0.1) * ltint * h * h;
	AO = mix(0.55, 1.0, h);
	AO_LIGHT_AFFECT = 0.4;
	// soften the flat-card look: lean the normal toward the sky, so a blade is lit like the turf it
	// grows from and doesn't go dark when it's seen edge-on or from behind
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, 0.72));
}
