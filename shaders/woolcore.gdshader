// Woolcore v0: the world as felt and knitting.
// pattern 0 = felt (soft mottling, fine fibres, a fuzzy rim)
// pattern 1 = knit (stockinette "V" stitches, `stitch` metres wide), on top of the felt
// Textures are projected in world space from three sides (triplanar), so a stretched box keeps
// stitches the same size. Made by scripts/catalog.gd (Catalog.mat / Catalog.knit).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform int pattern = 0;
uniform float stitch = 0.3;
uniform float fuzz : hint_range(0.0, 1.0) = 1.0;
uniform float contrast : hint_range(0.0, 1.0) = 0.7; // how dark the gaps between stitches are
// the prop's own Cycles light bake (art/world_assets/light_bake), on UV2; white where there's none
uniform sampler2D baked_ao : hint_default_white, filter_linear_mipmap;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

// One stockinette stitch per unit cell: two petals leaning out from the bottom centre, a "V".
// Returns height 0..1 (1 = top of the yarn).
float knit_h(vec2 uv) {
	vec2 f = fract(uv);
	vec2 p = vec2(abs(f.x - 0.5), f.y);
	vec2 a = vec2(0.05, -0.08);
	vec2 b = vec2(0.36, 1.06);
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	float d = length(pa - ba * t);
	float h = 1.0 - smoothstep(0.1, 0.25, d);
	h *= 0.7 + 0.3 * sin(t * 3.14159);
	// little twist lines along the yarn ply
	h *= 0.9 + 0.1 * sin((t * 9.0 + d * 30.0));
	return h;
}

// Felt and knit for one projection plane: returns (shade, height).
vec2 surface(vec2 co, float st) {
	float mott = fbm(co * 1.7);
	float fib = vnoise(co * 55.0) * 0.5 + vnoise(co * 110.0 + 3.1) * 0.5;
	float fw = length(fwidth(co * 55.0));
	fib = mix(fib, 0.5, smoothstep(0.15, 0.5, fw)); // fibres fade out before they'd shimmer
	float shade = 0.92 + 0.14 * mott + 0.07 * (fib - 0.5);
	float h = 0.6;
	if (pattern == 1) {
		vec2 uv = co / vec2(st, st * 0.78);
		float fk = length(fwidth(uv));
		float k = knit_h(uv);
		float tint = hash(floor(uv)) * 0.06 - 0.03;
		// full stitches only when one is 12+ pixels across; smaller than that they crawl as the
		// camera moves (worse once the 3D view is upscaled), so fade to the average colour
		float detail = 1.0 - smoothstep(0.08, 0.3, fk);
		h = mix(0.55, k, detail);
		shade *= mix(1.0, mix(contrast, 1.08, k) + tint, detail);
	}
	return vec2(shade, h);
}

void fragment() {
	vec3 n = abs(wnrm);
	vec3 w = pow(n, vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 top = surface(wpos.xz, stitch);
	vec2 sx = surface(vec2(wpos.z, wpos.y), stitch);
	vec2 sz = surface(vec2(wpos.x, wpos.y), stitch);
	vec2 s = top * w.y + sx * w.x + sz * w.z;
	ALBEDO = albedo.rgb * s.x;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
	AO = mix(0.55, 1.0, s.y) * texture(baked_ao, UV2).r;
	AO_LIGHT_AFFECT = pattern == 1 ? 0.45 : 0.1;
	RIM = 0.35 * fuzz;
	RIM_TINT = 0.6;
}
