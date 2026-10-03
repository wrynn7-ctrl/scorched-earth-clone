class_name HeartIcon
extends Control
## A drawn heart as a control (never a font glyph): banner accents, the win title, the popups.
## `fill` 1 is solid; below 1 only the lower part is tinted (a meter).

var color: Color = Color(1.0, 0.4, 0.64):
	set(v):
		color = v
		queue_redraw()
var fill: float = 1.0:
	set(v):
		fill = clampf(v, 0.0, 1.0)
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## A square icon `px` canvas units wide.
func set_icon_size(px: float) -> void:
	custom_minimum_size = Vector2(px, px)


func _draw() -> void:
	var s: float = minf(size.x, size.y) * 0.42
	HeartShape.draw(self, size * 0.5, s, color, fill)
