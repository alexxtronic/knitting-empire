// God mode's painted roads (scripts/god_mode.gd), shared by ground.gdshader and
// region_ground.gdshader so a road can be painted anywhere on the map. The map covers roads_rect
// (x, z, width, depth in world metres). Each pixel is one surface, by its colour:
//   red = dirt, green = gravel, blue = cobblestones (the stones are models; this is their cement),
//   yellow (red + green) = pavement, cyan (green + blue) = sidewalk, black = none.
// Linear filtering blends the colours at the edges, so road_weights() splits them back apart.
uniform sampler2D roads : filter_linear, repeat_disable, hint_default_black;
uniform vec4 roads_rect = vec4(0.0, 0.0, 1.0, 1.0);

float rd_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rd_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rd_hash(i), rd_hash(i + vec2(1.0, 0.0)), u.x), mix(rd_hash(i + vec2(0.0, 1.0)), rd_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// How much of each surface is at p (0..1 each): dirt, gravel, cobbles, pavement, sidewalk.
void road_weights(vec2 p, out float dirt, out float gravel_w, out float cobble, out float pave, out float side) {
	dirt = 0.0;
	gravel_w = 0.0;
	cobble = 0.0;
	pave = 0.0;
	side = 0.0;
	vec2 ru = (p - roads_rect.xy) / roads_rect.zw;
	if (ru.x < 0.0 || ru.y < 0.0 || ru.x > 1.0 || ru.y > 1.0) {
		return;
	}
	vec3 c = texture(roads, ru).rgb;
	pave = min(c.r, c.g);
	side = min(c.g, c.b);
	dirt = max(c.r - pave, 0.0);
	gravel_w = max(c.g - pave - side, 0.0);
	cobble = max(c.b - side, 0.0);
}

// Loose gravel: pebbles a few centimetres across, each its own shade of grey, dark in the gaps.
vec3 gravel(vec2 p, float soften) {
	vec2 q = p * 10.0;
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(rd_hash(i + g), rd_hash(i + g + vec2(17.3, 4.1)));
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = rd_hash(i + g + vec2(5.1, 9.7));
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	vec3 stone = mix(vec3(0.27, 0.25, 0.23), vec3(0.5, 0.47, 0.42), id);
	stone = mix(stone, vec3(0.42, 0.33, 0.25), step(0.84, id) * 0.8); // the odd brown one
	vec3 col = mix(vec3(0.15, 0.13, 0.11), stone, smoothstep(0.03, 0.22, d2 - d1));
	return mix(col, vec3(0.35, 0.33, 0.3), soften); // far away the pebbles blur into one grey
}

// Asphalt (Alex, 2026-11-17: "darker shade of grey with textures"): a dark grey binder with the
// aggregate showing through as pale and dark chips a centimetre or two across, mottled and worn
// lighter in broad patches, hairline cracks sealed with black tar, and the odd square repair patch
// of fresher, blacker asphalt with a seam round it. The fine detail fades out before it could shimmer.
vec3 pavement(vec2 p, float px_m) {
	float near = 1.0 - smoothstep(0.012, 0.05, px_m);
	float mid_near = 1.0 - smoothstep(0.05, 0.2, px_m);
	float wear = rd_noise(p * 0.15) * 0.6 + rd_noise(p * 0.6) * 0.4;
	vec3 col = mix(vec3(0.03, 0.034, 0.042), vec3(0.062, 0.065, 0.072), wear); // linear, a little blue: a cool grey under the warm sun
	// mottling and speck that still read from the camera's height: blotches of 30 cm and 6 cm
	float mot = rd_noise(p * 3.1 + 7.7) * 0.6 + rd_noise(p * 16.0 + 2.2) * 0.4 * mid_near + 0.2 * (1.0 - mid_near);
	col *= 0.78 + 0.44 * mot;
	float speck = rd_noise(p * 45.0);
	col = mix(col, col * (speck > 0.72 ? 1.9 : (speck < 0.2 ? 0.6 : 1.0)), mid_near * (1.0 - near) * 0.55); // pale and dark grains, blurred further off
	// the aggregate: one chip in each 1.6 cm cell, round-ish, its own shade
	vec2 q = p * 62.0;
	vec2 cell = floor(q);
	vec2 o = vec2(rd_hash(cell + 3.1), rd_hash(cell + 8.3)) * 0.5 + 0.25;
	float chip = 1.0 - smoothstep(0.18, 0.32, length(fract(q) - o));
	float shade = rd_hash(cell + 1.7);
	vec3 stone = shade > 0.55 ? vec3(0.17, 0.168, 0.165) * (0.7 + 0.6 * shade) : vec3(0.018, 0.018, 0.02);
	col = mix(col, stone, chip * near * 0.7);
	col = mix(col, col * (0.9 + 0.25 * rd_hash(floor(p * 40.0))), (1.0 - near) * mid_near * 0.6); // the chips as grain further off
	// cracks: thin wandering lines where a noise crosses its middle, in some stretches only
	float cn = rd_noise(p * 0.55 + 11.0) * 0.7 + rd_noise(p * 2.3) * 0.3;
	float slope = max(fwidth(cn) / max(px_m, 1e-5), 0.05); // the noise's change per metre, so the line is a set width
	float cd = abs(cn - 0.5) / slope; // metres from the crack
	float cw = max(0.006, px_m * 0.5);
	float crack = (1.0 - smoothstep(cw, cw * 2.0, cd)) * smoothstep(0.62, 0.75, rd_noise(p * 0.09 + 5.0));
	col = mix(col, vec3(0.012, 0.012, 0.014), crack * mid_near * 0.9);
	// repair patches: some 3 m squares carry a fresher, blacker patch with a pale seam round it
	vec2 pc = floor(p / 3.0);
	if (rd_hash(pc + 21.0) > 0.86) {
		vec2 f = fract(p / 3.0);
		vec2 lo = vec2(rd_hash(pc + 2.0), rd_hash(pc + 4.0)) * 0.3 + 0.08;
		vec2 hi = 1.0 - vec2(rd_hash(pc + 6.0), rd_hash(pc + 9.0)) * 0.3 - 0.08;
		vec2 e = min(f - lo, hi - f) * 3.0;
		float inside = step(0.0, min(e.x, e.y));
		float seam = inside * (1.0 - smoothstep(0.02, 0.05, min(e.x, e.y)));
		col = mix(col, col * 0.65, inside);
		col = mix(col, vec3(0.1, 0.098, 0.095), seam * mid_near * 0.7);
	}
	return col;
}

// Concrete paving slabs: pale, each slab its own shade, in 1.5 m squares with dark joints.
vec3 sidewalk(vec2 p, float px_m) {
	vec2 q = p / 1.5;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float tone = rd_hash(cell + vec2(3.7, 1.1));
	vec3 col = mix(vec3(0.6, 0.59, 0.56), vec3(0.7, 0.69, 0.66), tone);
	col *= 0.93 + 0.12 * rd_noise(p * 3.0) + (rd_hash(floor(p * 30.0)) - 0.5) * 0.06;
	float jw = max(0.012, px_m * 0.7); // a joint is never thinner than a screen pixel
	vec2 e = min(f, 1.0 - f) * 1.5;
	float joint = 1.0 - smoothstep(jw, jw * 2.0, min(e.x, e.y));
	return mix(col, col * 0.55, joint * (1.0 - smoothstep(0.05, 0.12, px_m)));
}

// Lays the painted roads over `col` (the ground as it would be). `dirt_col` is the dirt colour. `bare`
// comes back as how much of the spot is a road (no grass).
vec3 painted_roads(vec2 p, vec3 col, vec3 dirt_col, float speck, float mid, float px_m, out float bare) {
	float dirt, gw, cob, pave, side;
	road_weights(p, dirt, gw, cob, pave, side);
	bare = 0.0;
	if (dirt + gw + cob + pave + side < 0.02) {
		return col;
	}
	float jag = (speck - 0.5) * 0.3;
	float e_dirt = smoothstep(0.35, 0.65, dirt + jag);
	col = mix(col, dirt_col, e_dirt);
	float e_grav = smoothstep(0.35, 0.65, gw + jag);
	if (e_grav > 0.0) {
		float soften = clamp((px_m * 10.0 - 0.45) * 1.4, 0.0, 0.85);
		col = mix(col, gravel(p, soften) * (0.75 + 0.5 * mid) * (0.9 + 0.2 * speck), e_grav);
	}
	float e_cob = smoothstep(0.25, 0.5, cob);
	col = mix(col, vec3(0.6, 0.58, 0.54) * (0.9 + 0.15 * speck), e_cob);
	float e_pave = smoothstep(0.4, 0.6, pave);
	if (e_pave > 0.0) {
		col = mix(col, pavement(p, px_m), e_pave);
	}
	float e_side = smoothstep(0.4, 0.6, side);
	if (e_side > 0.0) {
		col = mix(col, sidewalk(p, px_m), e_side);
	}
	bare = max(max(max(e_dirt, e_grav), e_cob), max(e_pave, e_side));
	return col;
}
