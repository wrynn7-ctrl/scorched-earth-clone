class_name Toast
extends PanelContainer
## Short message pill near the top of the screen ("Power too low"). Fades by itself.

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _label: Label = null
var _tween: Tween = null


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", NeonPalette.WARN)
	add_child(_label)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH


func show_message(text: String, seconds: float = 2.0) -> void:
	_label.text = text
	_label.add_theme_font_size_override("font_size", UiScale.font(16.0))
	reset_size()
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, UiScale.dp(96.0))
	visible = true
	modulate = Color.WHITE
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(seconds)
	_tween.tween_property(self, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func() -> void: visible = false)


func get_text() -> String:
	return _label.text
