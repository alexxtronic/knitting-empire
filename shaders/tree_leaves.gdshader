// Leaves on the map trees (art/world_assets/trees): the painted leaf texture, cut out by its
// alpha, with a sway in the wind that grows with height and a little rustle. The trees are
// MultiMesh instances; the instance colour tints each tree slightly. main.gd sets `wind` and `wet`
// (stronger and darker in the rain), the same as the old canopy shader.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float wind = 0.18;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform float wet : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(wpos.y - root.y - 1.4, 0.0);
	float t = TIME;
	float gust = 0.5 + 0.5 * sin(dot(root.xz, wind_dir) * 0.2 - t * 0.9);
	float sway = sin(t * 1.3 + root.x * 0.37 + root.z * 0.23) * 0.6 + gust * 0.8;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * sway * wind * h * 0.1;
	// each card flutters on its own a little
	off.y += sin(t * 3.1 + wpos.x * 2.3 + wpos.z * 1.9) * 0.02 * h * (0.5 + wind * 3.0);
	VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb * COLOR.rgb * (1.0 - wet * 0.15);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// the crown's normals are bent round it on purpose: keep them on the back of a card too
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.8 - wet * 0.3;
	SPECULAR = 0.2;
	BACKLIGHT = c.rgb * 0.35;
}
