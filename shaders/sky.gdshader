// The sky: a gradient from horizon to zenith, the sun, soft drifting clouds and stars at night.
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
uniform float sun_size = 0.035;

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
	// the sun: a soft disc with a warm halo (only above the horizon)
	vec3 sd = LIGHT0_DIRECTION;
	float sdot = max(dot(d, sd), 0.0);
	float halo = pow(sdot, 12.0) * 0.25 + pow(sdot, 120.0) * 0.5;
	float disc = smoothstep(cos(sun_size), cos(sun_size * 0.8), dot(d, sd));
	vec3 sun_col = LIGHT0_COLOR * LIGHT0_ENERGY;
	float sun_vis = smoothstep(-0.05, 0.05, up) * (1.0 - cloud_cover * 0.75);
	col += sun_col * (halo + disc * 3.0) * sun_vis * float(LIGHT0_ENABLED);
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
		float lit = clamp(0.55 + (n2 - n) * 1.6 + pow(sdot, 4.0) * 0.4, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_light, lit);
		cc = mix(cc, cc * sky_horizon_color * 1.25, 0.35);
		cc *= mix(1.0, 0.18, night);
		col = mix(col, cc, c * 0.92);
		// stars, faded by cloud and by daylight
		if (night > 0.01) {
			vec2 sp = d.xz / (up + 0.3) * 260.0;
			float s = step(0.9965, hash(floor(sp)));
			col += vec3(0.9, 0.92, 1.0) * s * night * (1.0 - c) * smoothstep(0.05, 0.3, up);
		}
	}
	COLOR = col;
}
