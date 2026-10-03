shader_type canvas_item;
// Vertical cyan -> magenta gradient across the logo text (VERTEX is the label-local position),
// with an optional slow highlight sweeping across it (`shimmer` 0 = off, for reduce motion).
uniform vec4 top_color : source_color = vec4(0.0, 0.93, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.22, 0.66, 1.0);
uniform float height = 120.0;
uniform float width = 400.0;
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
varying vec2 vpos;

void vertex() {
	vpos = VERTEX;
}

void fragment() {
	float k = smoothstep(0.1, 0.95, clamp(vpos.y / height, 0.0, 1.0));
	COLOR.rgb = mix(top_color.rgb, bottom_color.rgb, k) * 1.08;
	float sweep = fract(TIME * 0.11) * 1.7 - 0.35;           // highlight centre, 0..1 across the text
	float band = exp(-pow((vpos.x / width - sweep) * 7.0, 2.0));
	COLOR.rgb += vec3(0.45, 0.4, 0.5) * band * shimmer;
}
