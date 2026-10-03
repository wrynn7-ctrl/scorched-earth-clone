class_name FacingMark
extends Control
## Tiny drawn neon chevron beside the angle readout. One mark sits on each side of the number;
## the mark on the side the barrel leans to is lit, the other stays blank but keeps its space so
## the number never jumps. Drawn (not a font glyph) so it exists on every font.

## Which side of the number this mark is on: HudFormat.FACING_LEFT or FACING_RIGHT.
var side: int = HudFormat.FACING_RIGHT
var lit: bool = false:
	set(v):
		if v != lit:
			lit = v
			queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Sizes the slot from the readout's font size in pixels.
func fit_to_font(font_px: int) -> void:
	custom_minimum_size = Vector2(float(font_px) * 0.5, float(font_px) * 0.8)


func _draw() -> void:
	if not lit:
		return
	var c: Vector2 = size * 0.5
	var h: float = minf(size.y, size.x * 1.6)
	var d: float = float(side)  # +1 points right, -1 points left
	var w: float = h * 0.5
	var tip: Vector2 = c + Vector2(d * w * 0.5, 0.0)
	var back_x: float = c.x - d * w * 0.5
	var tri := PackedVector2Array([tip, Vector2(back_x, c.y - h * 0.5), Vector2(back_x, c.y + h * 0.5)])
	var pad: float = maxf(1.5, h * 0.12)
	var glow := PackedVector2Array([
		tip + Vector2(d * pad * 1.4, 0.0),
		Vector2(back_x - d * pad, c.y - h * 0.5 - pad * 1.3),
		Vector2(back_x - d * pad, c.y + h * 0.5 + pad * 1.3),
	])
	draw_colored_polygon(glow, Color(NeonPalette.CYAN, 0.28))
	draw_colored_polygon(tri, NeonPalette.CYAN)
