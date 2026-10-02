shader_type canvas_item;
render_mode blend_mix;

// The terrain bytes are uploaded unchanged (column-major, index = x * height + y) as an
// R8 texture of size (height x width). So texel (tx, ty) = (y, x): this shader swaps.
uniform sampler2D cells : filter_nearest, repeat_disable;
uniform ivec2 world_size = ivec2(1600, 900);
uniform vec4 edge_a : source_color = vec4(0.0, 0.93, 1.0, 1.0);
uniform vec4 edge_b : source_color = vec4(1.0, 0.18, 0.62, 1.0);
uniform float grid_strength : hint_range(0.0, 0.3) = 0.07;
uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;

// Subtle strata colours for materials 0..15 (0 = air, unused).
const vec3 STRATA[16] = vec3[16](
	vec3(0.0),
	vec3(0.30, 0.12, 0.45), vec3(0.24, 0.12, 0.50), vec3(0.18, 0.14, 0.52), vec3(0.13, 0.18, 0.52),
	vec3(0.10, 0.24, 0.50), vec3(0.08, 0.30, 0.48), vec3(0.08, 0.34, 0.44), vec3(0.10, 0.36, 0.38),
	vec3(0.30, 0.16, 0.40), vec3(0.36, 0.12, 0.34), vec3(0.40, 0.10, 0.28), vec3(0.28, 0.10, 0.26),
	vec3(0.20, 0.10, 0.30), vec3(0.14, 0.09, 0.28), vec3(0.10, 0.08, 0.24)
);

// 12 neighbour taps: axis at r=1, diagonals at r=2, axis at r=3, with falloff weights.
const ivec2 OFFS[12] = ivec2[12](
	ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
	ivec2(2, 2), ivec2(-2, 2), ivec2(2, -2), ivec2(-2, -2),
	ivec2(3, 0), ivec2(-3, 0), ivec2(0, 3), ivec2(0, -3)
);
const float WTS[12] = float[12](
	0.34, 0.34, 0.34, 0.34,
	0.16, 0.16, 0.16, 0.16,
	0.10, 0.10, 0.10, 0.10
);

int cell_at(ivec2 p) {
	if (p.y >= world_size.y) { return 255; } // bedrock below the world
	if (p.y < 0) { return 0; }
	p.x = clamp(p.x, 0, world_size.x - 1);
	return int(texelFetch(cells, ivec2(p.y, p.x), 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 wp = UV * vec2(world_size);
	ivec2 p = ivec2(floor(wp));
	int m = cell_at(p);
	bool solid = m > 0;

	float acc = 0.0;
	for (int i = 0; i < 12; i++) {
		bool other = cell_at(p + OFFS[i]) > 0;
		if (other != solid) { acc += WTS[i]; }
	}
	float edge = clamp(acc, 0.0, 1.0);
	vec3 ecol = mix(edge_a.rgb, edge_b.rgb, smoothstep(0.0, 1.0, 0.5 + 0.5 * sin(wp.x * 0.004 + 1.2)));

	if (solid) {
		float depth = clamp(wp.y / float(world_size.y), 0.0, 1.0);
		// Opaque dirt: bright enough near the surface to clearly read as a solid mass in front of
		// the sky's ground plane (it was too close to that plane's dark purple).
		vec3 base = STRATA[clamp(m, 0, 15)] * mix(1.0, 0.42, depth);
		// Faint grid + scanline texture inside the dirt.
		float hl = step(0.86, fract(wp.y / 6.0));
		float vl = step(0.94, fract(wp.x / 24.0));
		float grid = max(hl * 0.6, vl) * grid_strength;
		base += ecol * grid;
		base += vec3(0.02) * sin(wp.y * 1.6);
		// Glowing rim where solid meets air; inner glow bleeds a little into the dirt.
		float rim = smoothstep(0.55, 1.0, edge);
		vec3 col = base + ecol * (edge * 0.55 + rim * 1.3) * glow_strength;
		COLOR = vec4(col, 1.0);  // alpha is exactly 1: nothing behind the dirt may show through
	} else {
		// Air: soft halo hugging the surface, transparent elsewhere.
		float halo = edge * edge * 0.8 * glow_strength;
		COLOR = vec4(ecol, halo);
	}
}
