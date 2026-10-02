class_name DamagePopup
extends Label
## Floating "-23" number that rises and fades. Pooled by the battle controller: pop() re-triggers.

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const RISE: float = 46.0
const LIFETIME: float = 1.0

var _tween: Tween = null


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 26)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(NeonPalette.BG_DEEP, 0.9))
	visible = false


## `at` is the number's centre in parent (world) coordinates.
func pop(text_value: String, color: Color, at: Vector2) -> void:
	text = text_value
	add_theme_color_override("font_color", color)
	reset_size()
	position = at - size * 0.5
	modulate = Color.WHITE
	visible = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - RISE, LIFETIME).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, LIFETIME * 0.5).set_delay(LIFETIME * 0.5)
	_tween.chain().tween_callback(func() -> void: visible = false)
