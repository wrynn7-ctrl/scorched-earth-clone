shader_type canvas_item;
// Ember gradient across the logo text (VERTEX is the label-local position): a burnt orange crown, a hot
// yellow core, glowing orange and a deep red base, like a horizon on fire. `shimmer` adds a slow warm
// highlight sweeping across (0 = off, for reduce motion). The magenta/cyan neon edge comes from the
// glow labels drawn behind it (title_screen.gd).
uniform vec4 crown_color : source_color = vec4(1.0, 0.56, 0.10, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.46, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.36, 0.06, 1.0);
uniform vec4 base_color : source_color = vec4(0.82, 0.05, 0.12, 1.0);
uniform float height = 120.0;     // glyph block height in pixels
uniform float width = 400.0;      // glyph block width in pixels
uniform float top = 0.0;          // label-local y where the glyph block starts
uniform float left = 0.0;         // label-local x where the glyph block starts
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
varying vec2 vpos;

void vertex() {
	vpos = VERTEX;
}

void fragment() {
	float k = clamp((vpos.y - top) / height, 0.0, 1.0);
	vec3 c = mix(crown_color.rgb, core_color.rgb, smoothstep(0.0, 0.32, k));
	c = mix(c, glow_color.rgb, smoothstep(0.34, 0.66, k));
	c = mix(c, base_color.rgb, smoothstep(0.62, 1.0, k));
	COLOR.rgb = c * 1.08;
	float u = clamp((vpos.x - left) / width, 0.0, 1.0);
	float sweep = fract(TIME * 0.11) * 1.7 - 0.35;           // highlight centre, 0..1 across the text
	float band = exp(-pow((u - sweep) * 7.0, 2.0));
	COLOR.rgb += vec3(0.5, 0.36, 0.2) * band * shimmer;
}
