// Light and dark patches across the grass, the same in the ground shader and the blades so they
// line up: broad drifts tens of metres across (sunnier yellow-green against deep blue-green),
// clumps a few metres across, and the odd darker hollow. Included by ground.gdshader and
// grass_blade.gdshader.

float gp_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float gp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(gp_hash(i), gp_hash(i + vec2(1.0, 0.0)), u.x), mix(gp_hash(i + vec2(0.0, 1.0)), gp_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// x: the broad drift, -1 dark .. 1 light; y: the clumps, -1 .. 1
vec2 grass_patches(vec2 p) {
	float broad = gp_noise(p * 0.045) * 0.55 + gp_noise(p * 0.11 + 11.0) * 0.45;
	float clump = gp_noise(p * 0.35 + 5.0) * 0.6 + gp_noise(p * 0.9 + 2.0) * 0.4;
	return vec2(smoothstep(0.32, 0.68, broad) * 2.0 - 1.0, smoothstep(0.35, 0.65, clump) * 2.0 - 1.0);
}

vec3 grass_patch_tint(vec3 col, vec2 k, float strength) {
	// light drifts go a little yellower and brighter, dark ones bluer and deeper
	vec3 light = col * vec3(1.28, 1.22, 0.86);
	vec3 dark = col * vec3(0.62, 0.72, 0.8);
	col = mix(col, k.x > 0.0 ? light : dark, abs(k.x) * strength);
	col *= 1.0 + k.y * 0.13 * strength;
	return col;
}
