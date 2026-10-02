class_name SwatchButton
extends Button
## A square button that shows a colour swatch or an emblem (setup screen). The art is a child
## control so it draws above the button's own background.

var _art: Control = null
var _color: Color = Color.WHITE
var _emblem: int = -1


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	_art = Control.new()
	_art.name = "Art"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.draw.connect(_draw_art)
	add_child(_art)


## Shows a colour swatch (emblem < 0) or `emblem` drawn in `color`.
func set_art(color: Color, emblem: int = -1) -> void:
	_color = color
	_emblem = emblem
	_art.queue_redraw()


func get_swatch_color() -> Color:
	return _color


func get_emblem() -> int:
	return _emblem


func _draw_art() -> void:
	var c: Vector2 = _art.size * 0.5
	var r: float = minf(_art.size.x, _art.size.y) * 0.3
	if _emblem >= 0:
		NeonPalette.draw_emblem(_art, _emblem, c, r, _color)
	else:
		_art.draw_circle(c, r * 1.35, Color(_color, 0.25))
		_art.draw_circle(c, r, _color)
		_art.draw_arc(c, r, 0.0, TAU, 24, NeonPalette.HOT, maxf(1.0, r * 0.12), true)
