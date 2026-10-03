shader_type canvas_item;
render_mode blend_mix;

// Neon wipe. `progress` runs 0..1 to cover the screen (a slanted dark band sweeps in from the
// left with a glowing leading edge) and 1..2 to uncover it (the band leaves to the right with
// a glowing trailing edge). `plain` = 1 turns it into a flat fade (reduce motion).
uniform float progress : hint_range(0.0, 2.0) = 0.0;
uniform float plain : hint_range(0.0, 1.0) = 0.0;
uniform vec4 base_col : source_color = vec4(0.027, 0.012, 0.075, 1.0);
uniform vec4 edge_a : source_color = vec4(0.0, 0.93, 1.0, 1.0);
uniform vec4 edge_b : source_color = vec4(1.0, 0.18, 0.62, 1.0);

void fragment() {
	if (plain > 0.5) {
		float a = progress <= 1.0 ? progress : 2.0 - progress;
		COLOR = vec4(base_col.rgb, clamp(a, 0.0, 1.0));
	} else {
		float x = UV.x + (UV.y - 0.5) * 0.22;      // slanted front
		float front = progress * 1.4 - 0.2;        // cover front, runs -0.2 .. 1.2
		float back = (progress - 1.0) * 1.4 - 0.2; // uncover front
		float covered = step(x, front) * (progress <= 1.0 ? 1.0 : step(back, x));
		float e1 = progress <= 1.0 ? exp(-abs(x - front) * 30.0) : 0.0;
		float e2 = progress > 1.0 ? exp(-abs(x - back) * 30.0) : 0.0;
		float glow = clamp(e1 + e2, 0.0, 1.0);
		vec3 ecol = mix(edge_a.rgb, edge_b.rgb, clamp(UV.y, 0.0, 1.0));
		float a = max(covered, glow * 0.75);
		vec3 col = mix(base_col.rgb, ecol, glow);
		COLOR = vec4(col, a);
	}
}
