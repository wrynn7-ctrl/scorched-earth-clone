class_name ShopButton
extends Button
## A BUY / SELL button that can be "blocked": it looks disabled but still takes presses, so
## the shop can answer with a toast that says *why* (a truly disabled button is silent).

var blocked: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE


func set_blocked(b: bool) -> void:
	blocked = b
	modulate = Color(1, 1, 1, 0.45) if b else Color.WHITE


func is_blocked() -> bool:
	return blocked
