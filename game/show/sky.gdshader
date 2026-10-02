shader_type canvas_item;
render_mode blend_mix;

// One cheap full-rect pass: gradient sky, sun/moon, horizon grid and two star layers.
uniform float aspect = 1.7778;          // rect width / height (set by sky.gd)
uniform float horizon : hint_range(0.3, 0.9) = 0.6;
uniform vec2 sun_pos = vec2(0.6, 0.40); // uv
uniform float sun_radius = 0.14;        // in height units
uniform float moon_mix : hint_range(0.0, 1.0) = 0.0;
uniform vec2 parallax = vec2(0.0);      // camera offset in uv-ish units (set by sky.gd)
uniform vec4 sky_top : source_color = vec4(0.027, 0.008, 0.10, 1.0);
uniform vec4 sky_mid : source_color = vec4(0.18, 0.04, 0.34, 1.0);
uniform vec4 sky_low : source_color = vec4(1.0, 0.22, 0.52, 1.0);
uniform vec4 grid_col : source_color = vec4(1.0, 0.2, 0.7, 1.0);
uniform vec4 grid_col2 : source_color = vec4(0.0, 0.9, 1.0, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float stars(vec2 uv, float cells, float size, float t) {
	vec2 g = uv * vec2(aspect, 1.0) * cells;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	if (h < 0.78) { return 0.0; }
	vec2 o = vec2(hash(id + 3.1), hash(id + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	float tw = 0.65 + 0.35 * sin(t * (0.8 + h * 2.0) + h * 40.0);
	return smoothstep(size, 0.0, d) * tw;
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
		col += vec3(0.8, 0.9, 1.0) * s * (1.0 - k * 0.8);

		// Sun (synthwave stripes) or moon.
		vec2 sp = (uv - sun_pos) * vec2(aspect, 1.0);
		float d = length(sp);
		float disc = smoothstep(sun_radius, sun_radius - 0.004, d);
		float vy = clamp((sp.y / sun_radius) * 0.5 + 0.5, 0.0, 1.0);
		vec3 sun_col = mix(vec3(1.0, 0.92, 0.35), vec3(1.0, 0.2, 0.55), vy);
		// Horizontal slits in the lower half of the sun, growing toward the bottom.
		float slit = step(0.0, sp.y) * step(fract(sp.y * 26.0), 0.12 + 0.55 * vy * vy);
		vec3 moon_col = vec3(0.85, 0.93, 1.0) * (0.85 + 0.15 * hash(floor(sp * 60.0)));
		vec3 body = mix(sun_col, moon_col, moon_mix);
		float vis = disc * mix(1.0 - slit, 1.0, moon_mix);
		float halo = exp(-d * 5.0) * 0.55;
		col += mix(vec3(1.0, 0.3, 0.6), vec3(0.4, 0.7, 1.0), moon_mix) * halo;
		col = mix(col, body, vis);
	} else {
		// Perspective grid on the ground plane below the horizon.
		float dy = uv.y - horizon;
		float z = 0.10 / max(dy, 0.002);               // depth along the ground plane
		float gx = (uv.x - 0.5 + parallax.x * 0.01) * aspect * z * 3.0;
		float gz = z - t * 0.35;                       // rows scroll toward the viewer
		float dx = min(fract(gx), 1.0 - fract(gx));
		float dz = min(fract(gz), 1.0 - fract(gz));
		float wx = fwidth(gx) * 1.4 + 0.004;
		float wz = fwidth(gz) * 1.4 + 0.004;
		float line = max(1.0 - smoothstep(0.0, wx, dx), 1.0 - smoothstep(0.0, wz, dz));
		float fade = smoothstep(0.0, 0.06, dy) * clamp(1.0 / (1.0 + fwidth(gz) * 3.0), 0.0, 1.0);
		vec3 base = mix(vec3(0.20, 0.04, 0.30), vec3(0.035, 0.012, 0.10), smoothstep(0.0, 0.6, dy));
		vec3 gcol = mix(grid_col.rgb, grid_col2.rgb, smoothstep(0.0, 0.35, dy));
		col = base + gcol * line * fade * 1.1;
		// Horizon glow strip.
		col += sky_low.rgb * exp(-dy * 40.0) * 0.8;
	}
	COLOR = vec4(col, 1.0);
}
