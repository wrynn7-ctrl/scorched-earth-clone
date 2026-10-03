shader_type canvas_item;
render_mode blend_mix;

// One cheap full-rect pass: gradient sky, sun/moon, horizon grid, stars, and (per theme) an
// aurora and a glowing city skyline. ThemeDefs pushes every colour below as a uniform; the
// defaults are the original Sunset Grid look.
uniform float aspect = 1.7778;          // rect width / height (set by sky.gd)
uniform float horizon : hint_range(0.3, 0.9) = 0.6;
uniform vec2 sun_pos = vec2(0.6, 0.40); // uv
uniform float sun_radius = 0.14;        // in height units
uniform float moon_mix : hint_range(0.0, 1.0) = 0.0;  // legacy switch: 1 = moon
uniform int sun_style = 0;              // 0 synthwave sun, 1 moon, 2 chrome sun, 3 heart sun (Love Edition)
uniform float scroll_speed = 0.35;      // grid rows per second toward the viewer (0 = still)
uniform vec2 parallax = vec2(0.0);      // camera offset in uv-ish units (set by sky.gd)
uniform vec4 sky_top : source_color = vec4(0.027, 0.008, 0.10, 1.0);
uniform vec4 sky_mid : source_color = vec4(0.18, 0.04, 0.34, 1.0);
uniform vec4 sky_low : source_color = vec4(1.0, 0.22, 0.52, 1.0);
uniform vec4 grid_col : source_color = vec4(1.0, 0.2, 0.7, 1.0);
uniform vec4 grid_col2 : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 ground_near : source_color = vec4(0.20, 0.04, 0.30, 1.0);
uniform vec4 ground_far : source_color = vec4(0.035, 0.012, 0.10, 1.0);
uniform vec4 sun_col_a : source_color = vec4(1.0, 0.92, 0.35, 1.0);   // top of the sun / moon colour
uniform vec4 sun_col_b : source_color = vec4(1.0, 0.2, 0.55, 1.0);    // bottom of the sun
uniform vec4 halo_col : source_color = vec4(1.0, 0.3, 0.6, 1.0);
uniform float star_thresh : hint_range(0.3, 0.95) = 0.78;  // a cell holds a star when hash >= this
uniform vec4 star_tint : source_color = vec4(0.8, 0.9, 1.0, 1.0);
uniform float aurora_mix : hint_range(0.0, 1.0) = 0.0;
uniform float aurora_peak = 0.26;
uniform vec4 aurora_a : source_color = vec4(0.2, 1.0, 0.7, 1.0);
uniform vec4 aurora_b : source_color = vec4(0.5, 0.5, 1.0, 1.0);
uniform float city_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec4 city_glow : source_color = vec4(1.0, 0.4, 0.2, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise: no visible cells, used for the moon's surface.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Brightness of a soft moon disc at q (-1..1 across the disc): a light sphere lit from the upper left,
// broad darker "seas" from two noise octaves and a handful of shallow craters with a faint bright rim.
float moon_shade(vec2 q) {
	float r2 = dot(q, q);
	vec3 n = vec3(q, sqrt(max(0.0, 1.0 - r2)));
	float sphere = 0.78 + 0.22 * clamp(dot(n, normalize(vec3(-0.45, -0.5, 0.75))), 0.0, 1.0);
	float seas = vnoise(q * 1.7 + 4.3) * 0.65 + vnoise(q * 3.9 + 9.1) * 0.35;
	float shade = sphere * (1.0 - 0.16 * smoothstep(0.35, 0.8, seas));
	vec2 g = q * 3.2 + 7.0;
	vec2 id = floor(g);
	float dents = 0.0;
	float rims = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = id + vec2(float(i), float(j));
			float h = hash(c);
			if (h < 0.45) { continue; }
			vec2 centre = c + 0.5 + (vec2(hash(c + 1.7), hash(c + 5.3)) - 0.5) * 0.55;
			float rad = 0.16 + 0.22 * hash(c + 9.9);
			float dist = length(g - centre);
			dents += smoothstep(rad, rad * 0.35, dist);
			rims += exp(-pow((dist - rad) / (rad * 0.22), 2.0));
		}
	}
	shade *= 1.0 - 0.13 * clamp(dents, 0.0, 1.0);
	shade += 0.05 * clamp(rims, 0.0, 1.0);
	// Darken the limb a little so the disc reads as round.
	return shade * (1.0 - 0.18 * smoothstep(0.55, 1.0, r2));
}

// Implicit heart curve on q (-1..1 across the sun's box): negative inside. The box is stretched
// to 1.25 so the heart fills it.
float heart_f(vec2 q) {
	float x = q.x * 1.25;
	float y = -q.y * 1.25 + 0.1;
	float a = x * x + y * y - 1.0;
	return a * a * a - x * x * y * y * y;
}

float stars(vec2 uv, float cells, float size, float t) {
	vec2 g = uv * vec2(aspect, 1.0) * cells;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	if (h < star_thresh) { return 0.0; }
	vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	float tw = 0.65 + 0.35 * sin(t * (0.8 + h * 2.0) + h * 40.0);
	return smoothstep(size, 0.0, d) * tw;
}

// Thin curtains with vertical streaks, strongest in the upper-middle sky.
vec3 aurora(vec2 uv, float k, float t) {
	float x = uv.x * aspect;
	float band = sin(x * 2.2 + sin(x * 0.9 + t * 0.15) * 2.0 + t * 0.1);
	float band2 = sin(x * 4.7 - t * 0.12 + 1.7);
	float curtain = pow(max(0.0, band * 0.6 + band2 * 0.4), 2.0);
	float vert = smoothstep(0.04, 0.25, k) * (1.0 - smoothstep(0.35, 0.75, k));
	float streak = 0.55 + 0.45 * sin(x * 38.0 + band * 3.0);
	return mix(aurora_a.rgb, aurora_b.rgb, clamp(k * 1.6, 0.0, 1.0)) * curtain * vert * streak * aurora_peak;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec3 col;
	if (uv.y < horizon) {
		float k = uv.y / horizon;
		col = mix(sky_top.rgb, sky_mid.rgb, smoothstep(0.0, 0.75, k));
		col = mix(col, sky_low.rgb, pow(smoothstep(0.55, 1.0, k), 2.0) * 0.9);
		// Parallax star dots (two layers).
		float s = stars(uv + parallax * 0.02, 40.0, 0.07, t) + stars(uv + parallax * 0.05 + 0.31, 18.0, 0.11, t * 0.7) * 1.2;
		col += star_tint.rgb * s * (1.0 - k * 0.8);
		if (aurora_mix > 0.0) {
			col += aurora(uv, k, t) * aurora_mix;
		}

		// Sun (synthwave stripes), moon or chrome sun.
		vec2 sp = (uv - sun_pos) * vec2(aspect, 1.0);
		float d = length(sp);
		float disc = smoothstep(sun_radius, sun_radius - max(0.003, fwidth(d) * 1.5), d);
		float vy = clamp((sp.y / sun_radius) * 0.5 + 0.5, 0.0, 1.0);
		int style = moon_mix > 0.5 ? 1 : sun_style;
		vec3 body;
		float vis = disc;
		vec3 halo_c = halo_col.rgb;
		if (style == 1) {
			vec3 base_col = moon_mix > 0.5 ? vec3(0.85, 0.93, 1.0) : sun_col_a.rgb;
			body = base_col * moon_shade(sp / sun_radius);
			if (moon_mix > 0.5) { halo_c = vec3(0.4, 0.7, 1.0); }
		} else if (style == 3) {
			// A heart-shaped sun: peach-white at the top fading to pink, with the synthwave slits low down.
			float hf = heart_f(sp / sun_radius);
			float hw = max(fwidth(hf) * 1.5, 0.003);
			vis = 1.0 - smoothstep(-hw, hw, hf);
			body = mix(sun_col_a.rgb, sun_col_b.rgb, smoothstep(0.1, 0.95, vy));
			float slit_h = step(0.15, sp.y) * step(fract(sp.y * 24.0), 0.08 + 0.4 * vy * vy);
			vis *= 1.0 - slit_h;
		} else if (style == 2) {
			// Chrome: bright sky reflection on top, a dark band, a hot horizon line, magenta below.
			vec3 top_c = sun_col_a.rgb * (1.0 - 0.35 * vy);
			vec3 mid_c = mix(top_c, vec3(0.04, 0.04, 0.09), smoothstep(0.30, 0.52, vy));
			body = mix(mid_c, sun_col_b.rgb, smoothstep(0.58, 1.0, vy));
			body += sun_col_a.rgb * (1.0 - smoothstep(0.0, 0.035, abs(vy - 0.54))) * 0.9;
			float slit_c = step(0.0, sp.y) * step(fract(sp.y * 22.0), 0.08 + 0.4 * vy * vy);
			vis *= 1.0 - slit_c;
		} else {
			body = mix(sun_col_a.rgb, sun_col_b.rgb, vy);
			// Horizontal slits in the lower half of the sun, growing toward the bottom.
			float slit = step(0.0, sp.y) * step(fract(sp.y * 26.0), 0.12 + 0.55 * vy * vy);
			vis *= 1.0 - slit;
		}
		col += halo_c * exp(-d * 5.0) * 0.55;
		col = mix(col, body, vis);

		// Glowing skyline: towers of random height with a few lit windows.
		if (city_mix > 0.0) {
			float above = horizon - uv.y;
			col += city_glow.rgb * exp(-above * 26.0) * 0.45 * city_mix;
			float cx = uv.x * aspect * 26.0;
			float id = floor(cx);
			float h = 0.012 + 0.075 * pow(hash(vec2(id, 3.0)), 1.6);
			float inside = step(above, h) * step(0.07, fract(cx)) * step(fract(cx), 0.93);
			vec2 wc = vec2(cx * 3.0, above * 150.0);
			float lit = step(0.7, hash(floor(wc) + id)) * step(0.3, fract(wc.x)) * step(0.3, fract(wc.y));
			vec3 tower = sky_top.rgb * 0.4 + city_glow.rgb * lit * 0.85;
			col = mix(col, tower, inside * city_mix);
		}
	} else {
		// Perspective grid on the ground plane below the horizon.
		float dy = uv.y - horizon;
		float z = 0.10 / max(dy, 0.002);               // depth along the ground plane
		float gx = (uv.x - 0.5 + parallax.x * 0.01) * aspect * z * 3.0;
		float gz = z - t * scroll_speed;                       // rows scroll toward the viewer
		float dx = min(fract(gx), 1.0 - fract(gx));
		float dz = min(fract(gz), 1.0 - fract(gz));
		float wx = fwidth(gx) * 1.4 + 0.004;
		float wz = fwidth(gz) * 1.4 + 0.004;
		float line = max(1.0 - smoothstep(0.0, wx, dx), 1.0 - smoothstep(0.0, wz, dz));
		float fade = smoothstep(0.0, 0.06, dy) * clamp(1.0 / (1.0 + fwidth(gz) * 3.0), 0.0, 1.0);
		vec3 base = mix(ground_near.rgb, ground_far.rgb, smoothstep(0.0, 0.6, dy));
		vec3 gcol = mix(grid_col.rgb, grid_col2.rgb, smoothstep(0.0, 0.35, dy));
		col = base + gcol * line * fade * 1.1;
		// Horizon glow strip.
		col += sky_low.rgb * exp(-dy * 40.0) * 0.8;
	}
	COLOR = vec4(col, 1.0);
}
