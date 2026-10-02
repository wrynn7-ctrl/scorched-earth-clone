shader_type canvas_item;
// Vertical cyan -> magenta gradient across the logo text (VERTEX is the label-local position).
uniform vec4 top_color : source_color = vec4(0.0, 0.93, 1.0, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.22, 0.66, 1.0);
uniform float height = 120.0;
varying float vy;

void vertex() {
	vy = VERTEX.y;
}

void fragment() {
	float k = smoothstep(0.1, 0.95, clamp(vy / height, 0.0, 1.0));
	COLOR.rgb = mix(top_color.rgb, bottom_color.rgb, k) * 1.08;
}
