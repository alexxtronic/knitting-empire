// Roof tiles (or shingles) laid in courses along each slope, whatever way the roof faces: the map
// runs along the slope's level line (u) and down it (v), worked out from each face's own normal
// in world space, so a model needs no UVs for it and a moved or turned building keeps its courses.
// The maps are art/world_assets/house_exterior's `tiles` and `shingles` (scripts/building_skin.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tile = 1.0; // metres one tile of the map covers
uniform bool courses_down_u = false; // the map's courses run across it (the house's turned shingles)
uniform float rough : hint_range(0.0, 1.0) = 0.85;
// the model's own light bake (art/world_assets/light_bake) on UV2, white where there's none
uniform sampler2D ao_tex : hint_default_white, filter_linear_mipmap;
uniform float ao_amount : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// the level line from the face's own flat normal (a smoothed normal turns as it crosses a flat
	// face, and the courses would turn with it), but down the slope by the smooth one, so a curved
	// roof (the café's dormers) runs on in one piece from facet to facet
	vec3 flat_n = normalize(cross(dFdy(wpos), dFdx(wpos)));
	vec3 n = normalize(wnrm);
	if (dot(flat_n, n) < 0.0) {
		flat_n = -flat_n;
	}
	vec3 level = cross(vec3(0.0, 1.0, 0.0), flat_n);
	level = length(level) < 0.05 ? vec3(1.0, 0.0, 0.0) : normalize(level);
	vec3 down = cross(n, level);
	down = length(down) < 0.05 ? vec3(0.0, 0.0, 1.0) : normalize(down);
	if (down.y > 0.0) {
		down = -down;
		level = -level; // keep the face's u, v the right way round for its normal map
	}
	vec3 p = wpos - NODE_POSITION_WORLD; // measured from the building, so the courses sit still when it moves
	vec2 uv = vec2(dot(p, level), dot(p, down)) / tile;
	vec3 tu = level;
	vec3 tv = down;
	if (courses_down_u) {
		uv = uv.yx;
		tu = down;
		tv = level;
	}
	ALBEDO = texture(tex, uv).rgb * tint.rgb;
	NORMAL_MAP = texture(nrm, uv).rgb;
	// Godot's tangent space: TANGENT along +u, BINORMAL toward -v (the image's up), both in view space
	TANGENT = normalize((VIEW_MATRIX * vec4(tu, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(-tv, 0.0)).xyz);
	ROUGHNESS = rough;
	AO = mix(1.0, texture(ao_tex, UV2).r, ao_amount);
	AO_LIGHT_AFFECT = 0.0;
}
