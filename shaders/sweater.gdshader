// A knitted sweater (scripts/sweaters.gd): the design's colour map on UV, a stitch per few pixels,
// times the shade of a tiling knit tile on UV2 (stockinette, or knit-two purl-two rib where the mask
// says), with the tile's normal map. The same as the review renders' material in
// art/world_assets/sweater/build.py.
shader_type spatial;

uniform sampler2D design : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D rib_mask : hint_default_black, filter_nearest, repeat_disable;
uniform sampler2D stock : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rib : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rib_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// wool's soft fuzz at the edges, tinted by the wool's own colour
uniform float fuzz : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float m = texture(rib_mask, UV).r;
	vec3 shade = mix(texture(stock, UV2).rgb, texture(rib, UV2).rgb, m);
	ALBEDO = texture(design, UV).rgb * shade;
	NORMAL_MAP = mix(texture(stock_n, UV2).rgb, texture(rib_n, UV2).rgb, m);
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
	RIM = fuzz;
	RIM_TINT = 0.8;
}
