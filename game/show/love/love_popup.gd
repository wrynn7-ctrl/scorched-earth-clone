class_name LovePopup
extends Label
## "+34 <heart>" that rises and fades over the tank that received love. Pooled by the battle
## controller like DamagePopup; the heart is drawn, so no glyph is needed from the font.

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const RISE: float = 56.0
const LIFETIME: float = 1.3
const PINK: Color = Color(1.0, 0.5, 0.72)

var _tween: Tween = null
var _heart_px: float = 22.0
var _amount: int = 0


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 28)
	add_theme_constant_override("outline_size", 6)
	add_theme_color_override("font_outline_color", Color(NeonPalette.BG_DEEP, 0.9))
	add_theme_color_override("font_color", Color(1.0, 0.86, 0.92))
	visible = false


func get_amount() -> int:
	return _amount


## `at` is the centre of the whole popup in parent (world) coordinates.
func pop(amount: int, at: Vector2) -> void:
	_amount = amount
	text = tr("LOVE_POPUP_FMT") % amount
	var font: Font = get_theme_font("font")
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28).x
	custom_minimum_size = Vector2(tw + _heart_px + 8.0, 34.0)
	reset_size()
	position = at - size * 0.5
	modulate = Color.WHITE
	visible = true
	queue_redraw()
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:y", position.y - RISE, LIFETIME).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 0.0, LIFETIME * 0.45).set_delay(LIFETIME * 0.55)
	_tween.chain().tween_callback(func() -> void: visible = false)


func _draw() -> void:
	var font: Font = get_theme_font("font")
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28).x
	HeartShape.draw(self, Vector2(tw + 6.0 + _heart_px * 0.5, size.y * 0.5), _heart_px * 0.5, PINK)
