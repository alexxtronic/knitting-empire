// The sky: a gradient from horizon to zenith, the sun and the moon (scripts/sky_bodies.gd sets
// where each is and the moon's phase), soft drifting clouds and stars at night.
// main.gd (_update_lighting) sets the colours, cloud cover (more when it rains) and how far the
// clouds have drifted. The radiance pass (used for ambient light and reflections) skips the
// cloud detail so it stays cheap.
shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.38, 0.6, 0.86);
uniform vec3 sky_horizon_color : source_color = vec3(0.97, 0.82, 0.62);
uniform vec3 ground_horizon_color : source_color = vec3(0.97, 0.82, 0.62);
uniform vec3 ground_bottom_color : source_color = vec3(0.35, 0.3, 0.25);
uniform vec3 cloud_light : source_color = vec3(1.0, 0.96, 0.9);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.6, 0.68);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.35;
uniform vec2 cloud_offset = vec2(0.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float sun_size = 0.032;
uniform vec3 sun_dir = vec3(0.0, 0.7, 0.7); // toward the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.8);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0); // toward the moon
uniform float moon_phase = 0.5; // 0 new, 0.5 full
uniform float moon_lit = 1.0; // how much of the disc is lit
uniform float moon_size = 0.04;

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
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	float up = d.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(sky_horizon_color, sky_top_color, pow(clamp(up, 0.0, 1.0), 0.55));
	} else {
		col = mix(ground_horizon_color, ground_bottom_color, clamp(-up * 4.0, 0.0, 1.0));
	}
	float clear = 1.0 - cloud_cover * 0.75;
	float above = smoothstep(-0.02, 0.03, up);
	// the sun: a bright disc with a warm halo (only above the horizon)
	vec3 sd = normalize(sun_dir);
	float sdot = max(dot(d, sd), 0.0);
	float sun_high = smoothstep(-0.08, 0.04, sd.y);
	float halo = pow(sdot, 10.0) * 0.3 + pow(sdot, 90.0) * 0.6;
	float disc = smoothstep(cos(sun_size), cos(sun_size * 0.85), dot(d, sd));
	col += sun_color * (halo * 1.4 + disc * 9.0) * above * clear * sun_high;
	// the moon: a disc lit from the sun's side by its phase, grey seas on it, a soft glow round it
	vec3 md = normalize(moon_dir);
	float mdot = dot(d, md);
	float moon_high = smoothstep(-0.04, 0.04, md.y);
	if (mdot > cos(moon_size * 1.2) && moon_high > 0.0) {
		vec3 side = sd - md * dot(sd, md);
		side = length(side) > 0.001 ? normalize(side) : normalize(cross(md, vec3(0.0, 1.0, 0.0)));
		vec3 upm = normalize(cross(side, md));
		vec2 q = vec2(dot(d, side), dot(d, upm)) / sin(moon_size); // -1..1 across the disc
		float r2 = dot(q, q);
		if (r2 < 1.0) {
			vec3 n = vec3(q, -sqrt(1.0 - r2)); // its face toward us (z away from us, toward the moon)
			float th = 6.28318 * moon_phase;
			vec3 l = vec3(sin(th), 0.0, cos(th)); // its sunlight: from behind at new moon, from us at full
			float lit = smoothstep(-0.04, 0.06, dot(n, l));
			float seas = smoothstep(0.45, 0.62, fbm(q * 2.2 + 3.0)) * 0.3;
			vec3 face = vec3(0.98, 0.97, 0.92) * (1.0 - seas);
			float edge = 1.0 - smoothstep(0.92, 1.0, r2);
			// a day moon is pale against the blue; by night it's bright, and the dark side shows faintly
			float bright = mix(0.55, 2.4, night);
			vec3 mc = face * (lit * bright + 0.025 * night);
			col = mix(col, mc + col * 0.35 * (1.0 - night), edge * moon_high * clear * mix(lit * 0.8, 1.0, night));
		}
	}
	float mglow = pow(max(mdot, 0.0), 300.0) * 0.6 + pow(max(mdot, 0.0), 30.0) * 0.12;
	col += vec3(0.7, 0.78, 1.0) * mglow * moon_lit * night * moon_high * clear;
	if (!AT_CUBEMAP_PASS && up > 0.0) {
		// clouds on a flat layer overhead, thinning toward the horizon
		vec2 p = d.xz / (up + 0.12) * 1.6 + cloud_offset;
		float n = fbm(p * 0.6);
		float n2 = fbm(p * 1.9 + vec2(n * 1.3, 0.0));
		float shape = n * 0.7 + n2 * 0.35;
		float thresh = mix(0.78, 0.36, cloud_cover);
		float c = smoothstep(thresh, thresh + 0.22, shape);
		c *= smoothstep(0.0, 0.18, up);
		// lit tops toward the sun, greyer bellies
		float lit = clamp(0.55 + (n2 - n) * 1.6 + pow(sdot, 4.0) * 0.4 * sun_high, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		cc = mix(cc, cc * sky_horizon_color * 1.25, 0.35);
		cc *= mix(1.0, 0.18, night);
		col = mix(col, cc, c * 0.92);
		// stars, faded by cloud and by daylight
		if (night > 0.01) {
			vec2 sp = d.xz / (up + 0.3) * 260.0;
			vec2 cell = floor(sp);
			float s = step(0.9965, hash(cell));
			// a round point somewhere in its cell, a pixel or two across whatever the zoom
			vec2 at = cell + 0.25 + 0.5 * vec2(hash(cell + 7.1), hash(cell + 3.7));
			float px = length(fwidth(sp));
			s *= 1.0 - smoothstep(0.5 * px, 1.5 * px, length(sp - at));
			s *= 0.6 + 0.8 * hash(cell + 1.3);
			// the full moon washes out the faint ones near it
			float wash = 1.0 - moon_lit * moon_high * (0.4 + 0.5 * pow(max(mdot, 0.0), 6.0));
			col += vec3(0.9, 0.92, 1.0) * s * night * (1.0 - c) * smoothstep(0.05, 0.3, up) * wash;
		}
	}
	COLOR = col;
}
