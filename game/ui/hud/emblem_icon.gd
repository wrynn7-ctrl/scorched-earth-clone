class_name EmblemIcon
extends Control
## Draws one tank emblem in the tank's colour (used by the turn banner and lists).

var _index: int = 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_index(i: int) -> void:
	_index = i
	queue_redraw()


func get_index_value() -> int:
	return _index


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.42
	NeonPalette.draw_emblem(self, NeonPalette.tank_emblem(_index), size * 0.5, r, NeonPalette.tank_color(_index))
