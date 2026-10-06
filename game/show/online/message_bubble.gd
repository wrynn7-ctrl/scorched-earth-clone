class_name MessageBubble
extends PanelContainer
## A quick message floating over the sender's tank for BUBBLE_SECONDS. Text messages show the words, emotes the drawn
## icon. The frame is in the sender's tank colour. It fades out in the last half second and never takes input.

var seat: int = -1
var msg: int = -1
var age: float = 0.0
var _label: Label = null
var _icon: MessageIcon = null
var _style: StyleBoxFlat = StyleBoxFlat.new()


func _init() -> void:
	name = "Bubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.bg_color = Color(NeonPalette.BG_DEEP, 0.9)
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(12)
	_style.content_margin_left = 10.0
	_style.content_margin_right = 10.0
	_style.content_margin_top = 4.0
	_style.content_margin_bottom = 4.0
	_style.anti_aliasing = true
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = MessageIcon.new()
	_icon.visible = false
	row.add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_color_override("font_color", NeonPalette.TEXT)
	row.add_child(_label)


func show_message(for_seat: int, message: int, color: Color) -> void:
	seat = for_seat
	msg = message
	age = 0.0
	_style.border_color = color
	var emote: bool = MessageDefs.has_icon(message)
	_icon.visible = emote
	_icon.set_icon(MessageDefs.icon_of(message))
	_label.visible = not emote
	_label.text = MessageDefs.text_of(message)
	accessibility_name = MessageDefs.text_of(message)
	modulate.a = 1.0
	visible = true
	apply_scale()


func apply_scale() -> void:
	_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(30.0)
	_label.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))


## Advances the timer; returns false once the bubble is done and may be freed.
func tick(delta: float) -> bool:
	age += delta
	var left: float = MessageDefs.BUBBLE_SECONDS - age
	modulate.a = clampf(left / 0.5, 0.0, 1.0)
	return left > 0.0


func is_emote() -> bool:
	return _icon.visible


func get_text() -> String:
	return _label.text if _label.visible else ""
