shader_type spatial;
// The dog with a knitted scarf of another colour (scripts/dog.gd, data/scarves.json). dog.glb has a
// single material, so the scarf isn't a part of its own: this finds the scarf's red in his colour
// map and knits it in `tint` instead, keeping the wool's shading and the cream snowflake stripes.
// Everything else draws as the glTF material did (colour, normal map, roughness 0.9).
// The pack's other dogs (scripts/kennel.gd) wear a coat of another colour too: with coat_on, the
// golden fur (a warm colour with g/r about 0.5 to 0.7 and little blue) is drawn in `coat` instead,
// its light and shade kept (the fur's brightness over its median, FUR_LUM). With scarf_on off the
// scarf keeps the model's own red.
// The mask is worked out in the texture's own sRGB values (the sampler has no source_color hint),
// then the colour goes to linear for lighting.

uniform sampler2D albedo_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(0.72, 0.13, 0.07); // sRGB
uniform float roughness_v = 0.9;
uniform float normal_depth = 1.0;
uniform float scarf_on = 1.0; // 0: his own red scarf, as the model has it
uniform vec3 coat = vec3(0.9, 0.62, 0.32); // sRGB: the fur's colour on a pack dog
uniform float coat_on = 0.0;
const float SCARF_RED = 0.745; // the scarf's median red in the colour map
const float FUR_LUM = 0.63; // the golden fur's median brightness in the colour map

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec4 s = texture(albedo_tex, UV);
	vec3 c = s.rgb;
	float r = max(c.r, 0.001);
	// red wool: a strong red with little green or blue in it (the golden fur has g/r of 0.5 and up)
	float w = smoothstep(0.42, 0.30, c.g / r) * smoothstep(0.55, 0.42, c.b / r) * smoothstep(0.22, 0.32, c.r);
	vec3 knit = tint * clamp(c.r / SCARF_RED, 0.0, 1.3);
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float fur = (1.0 - w) * smoothstep(0.38, 0.48, c.g / r) * smoothstep(0.5, 0.4, c.b / r) * smoothstep(0.06, 0.14, lum);
	vec3 coat_c = coat * clamp(lum / FUR_LUM, 0.0, 1.5);
	vec3 col = mix(c, knit, w * scarf_on);
	col = mix(col, coat_c, fur * coat_on);
	ALBEDO = to_linear(col);
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
