// Fallen leaves on the ground: one MultiMesh of small flat cards. The atlas
// (assets/props/leaf_litter.png) holds four pale leaves in a 2 x 2 grid; INSTANCE_CUSTOM.x picks
// one and the instance colour tints it.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float wet : hint_range(0.0, 1.0) = 0.0;

varying vec2 cell;

void vertex() {
	float k = floor(INSTANCE_CUSTOM.x * 4.0);
	cell = vec2(mod(k, 2.0), floor(k / 2.0)) * 0.5;
}

void fragment() {
	vec4 c = texture(atlas, cell + UV * 0.5);
	ALBEDO = c.rgb * COLOR.rgb * (1.0 - wet * 0.3);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ROUGHNESS = 0.85 - wet * 0.45;
	SPECULAR = 0.15 + wet * 0.3;
}
