class_name EmblemIcon
extends Control
## Draws one player's emblem in their colour (used by the turn banner and lists). The index is
## the player index; PlayerLooks maps it to the colour/emblem the player picked.

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
	NeonPalette.draw_emblem(self, PlayerLooks.emblem(_index), size * 0.5, r, PlayerLooks.color(_index))
