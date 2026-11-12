shader_type fog;
// Morning mist: a ground-hugging layer of volumetric fog, patchy and slowly drifting. It lies in
// world space (the noise doesn't follow the camera), thins with height and fades out at the
// volume's edges. scripts/lighting.gd turns `density` up at dawn and down to nothing by mid-morning;
// the low sun's shadows through it are the light shafts between the trees.

uniform float density = 0.0;
uniform float falloff = 0.8; // per metre: the mist halves about every 0.9 m of height
uniform vec3 albedo : source_color = vec3(1.0, 0.96, 0.92);
uniform sampler3D noise : filter_linear, repeat_enable;
uniform float noise_scale = 0.045; // patches about 20 m across
uniform vec2 drift = vec2(0.035, 0.02); // metres per second, with the morning air

void fog() {
	float h = max(WORLD_POSITION.y + 0.3, 0.0);
	float layer = exp(-h * falloff);
	vec3 p = WORLD_POSITION * vec3(noise_scale, noise_scale * 2.5, noise_scale);
	p.xz += drift * TIME * noise_scale;
	float n = texture(noise, p).r * 0.65 + texture(noise, p * 2.7 + vec3(0.3, 0.1, 0.7)).r * 0.35;
	float patchy = smoothstep(0.25, 0.75, n);
	float edge = clamp(-SDF / 6.0, 0.0, 1.0); // SDF is negative inside: fade over the last 6 m
	DENSITY = density * layer * mix(0.25, 1.4, patchy) * edge;
	ALBEDO = albedo;
}
