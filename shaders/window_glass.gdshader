// Window glass: old hand-made panes you can see through, with a slight wobble to what's behind
// them, a faint green-blue tint, and the sky and sun caught on them more at a glancing angle.
// Used by every window in the game (Catalog.window_glass(): Nora's house and Rosewood Cottage,
// and the walk-in shops' "glass_<shop>" panes). It reads the opaque scene behind it from the
// screen, so it draws what's in the room, lit as it is, rather than letting light through.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec3 tint : source_color = vec3(0.9, 0.96, 0.95);
uniform float warp : hint_range(0.0, 0.1) = 0.022; // how far the ripples bend what's behind, in metres
uniform float ripple : hint_range(0.5, 40.0) = 9.0; // ripples a metre
uniform float clarity : hint_range(0.0, 1.0) = 0.86; // how much of what's behind shows face on
uniform vec3 sheen : source_color = vec3(0.72, 0.82, 0.9); // the sky in the glass at a glancing angle

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// smooth uneven waves, as crown glass has: fixed to the pane, so they don't crawl as you move
vec2 waves(vec3 p) {
	float a = sin(p.x * ripple + 1.7 * sin(p.y * ripple * 0.63 + p.z * 2.1)) + 0.5 * sin(p.z * ripple * 1.31 - p.y * ripple * 0.4);
	float b = sin(p.y * ripple * 0.87 + 1.3 * sin(p.x * ripple * 0.71 - p.z * ripple * 0.55)) + 0.5 * sin((p.x + p.z) * ripple * 1.7);
	return vec2(a, b) / 1.5;
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 4.0);
	// bend the view by the ripples, less the further away the pane is, so it's a few pixels
	vec2 bend = waves(wpos) * warp / max(-VERTEX.z, 0.5);
	vec2 uv = SCREEN_UV + bend * vec2(1.0, VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
	// only bend toward what's actually behind the glass (not its frame in front)
	float d = texture(depth_tex, uv).r;
	vec4 behind_v = INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, d, 1.0);
	if (-behind_v.z / behind_v.w < -VERTEX.z) {
		uv = SCREEN_UV;
	}
	vec3 behind = textureLod(screen_tex, uv, 0.0).rgb;
	float through = clarity * (1.0 - fres);
	ALBEDO = sheen * 0.08 * (1.0 - through); // a little body to catch the light where it's not see-through
	EMISSION = behind * tint * through;
	ROUGHNESS = 0.06;
	SPECULAR = 0.6;
	METALLIC = 0.0;
	ALPHA = 1.0; // drawn in the transparent pass, after the room behind it, so the screen holds the room
}
