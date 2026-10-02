class_name WindIndicator
extends PanelContainer
## Wind arrow + number. Direction and strength come from an int in [-100, 100]
## (negative blows left). Strength is shown both by arrow length and by the number.

var _wind: int = 0
var _arrow: Control = null
var _caption: Label = null
var _value: Label = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_arrow = Control.new()
	_arrow.name = "Arrow"
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	row.add_child(_arrow)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	col.add_child(_caption)
	_value = Label.new()
	_value.name = "Value"
	col.add_child(_value)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_arrow.custom_minimum_size = Vector2(UiScale.dp(76.0), UiScale.dp(40.0))
	_caption.add_theme_font_size_override("font_size", UiScale.font(11.0))
	_value.add_theme_font_size_override("font_size", UiScale.font(24.0))


func set_wind(w: int) -> void:
	_wind = clampi(w, -HudFormat.WIND_MAX, HudFormat.WIND_MAX)
	_refresh()


func get_wind() -> int:
	return _wind


func _refresh() -> void:
	_caption.text = tr("HUD_WIND_CALM") if _wind == 0 else tr("HUD_WIND")
	_value.text = HudFormat.wind(_wind)
	var col: Color = NeonPalette.TEXT
	if absi(_wind) > 66:
		col = NeonPalette.MAGENTA
	elif _wind != 0:
		col = NeonPalette.CYAN
	_value.add_theme_color_override("font_color", col)
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	var s: Vector2 = _arrow.size
	var mid: float = s.y * 0.5
	var strength: float = float(absi(_wind)) / float(HudFormat.WIND_MAX)
	var col: Color = NeonPalette.MAGENTA if absi(_wind) > 66 else NeonPalette.CYAN
	if _wind == 0:
		_arrow.draw_circle(Vector2(s.x * 0.5, mid), s.y * 0.14, NeonPalette.TEXT_DIM)
		return
	var dir: float = 1.0 if _wind > 0 else -1.0
	var half: float = s.x * 0.5
	var length: float = lerpf(0.34, 1.0, strength) * s.x * 0.96
	var tail_x: float = half - dir * length * 0.5
	var tip_x: float = half + dir * length * 0.5
	var head: float = minf(s.y * 0.42, length * 0.5)
	var thick: float = maxf(3.0, s.y * 0.14)
	_arrow.draw_line(Vector2(tail_x, mid), Vector2(tip_x - dir * head * 0.6, mid), Color(col, 0.28), thick * 2.2, true)
	_arrow.draw_line(Vector2(tail_x, mid), Vector2(tip_x - dir * head * 0.6, mid), col, thick, true)
	var tri := PackedVector2Array([
		Vector2(tip_x, mid), Vector2(tip_x - dir * head, mid - head * 0.8), Vector2(tip_x - dir * head, mid + head * 0.8),
	])
	_arrow.draw_colored_polygon(tri, col)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _caption != null:
		_refresh()
