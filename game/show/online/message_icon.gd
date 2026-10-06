class_name MessageIcon
extends Control
## A quick-message emote drawn as a neon icon (see MessageDefs). Used on the picker buttons and in bubbles.

var icon: int = MessageDefs.Icon.NONE
var tint: Color = NeonPalette.WARN


func _init(kind: int = MessageDefs.Icon.NONE) -> void:
	icon = kind
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_icon(kind: int) -> void:
	icon = kind
	queue_redraw()


func _draw() -> void:
	MessageDefs.draw_icon(self, icon, size * 0.5, minf(size.x, size.y) * 0.46, tint)
