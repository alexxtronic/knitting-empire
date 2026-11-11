// Cobblestone tiles laid by god mode's road painting (scripts/god_mode.gd): the tile models
// cover whole 4 x 2 m squares, and this draws only the part of each that was painted, so paving
// can have any outline (a round cul-de-sac, a curved lane). The painted map's blue channel is
// the cobbles; it covers roads_rect (x, z, width, depth) in world metres.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_normal = 1.0;
uniform float normal_depth = 1.0;
uniform float roughness = 0.9;
uniform sampler2D roads : filter_linear, repeat_disable, hint_default_black;
uniform vec4 roads_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 ru = (wpos.xz - roads_rect.xy) / roads_rect.zw;
	if (ru.x < 0.0 || ru.y < 0.0 || ru.x > 1.0 || ru.y > 1.0 || texture(roads, ru).b < 0.5) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ROUGHNESS = roughness;
}
