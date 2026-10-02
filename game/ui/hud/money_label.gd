class_name MoneyLabel
extends PanelContainer
## The current player's credits, always on screen ("$ 8,500") with a small coin glyph so the
## readout is recognisable without reading.

var _coin: Control = null
var _label: Label = null
var _amount: int = 0
var _font_dp: float = 16.0


func _init() -> void:
	name = "Money"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_coin = Control.new()
	_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin.draw.connect(_draw_coin)
	row.add_child(_coin)
	_label = Label.new()
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", NeonPalette.WARN)
	row.add_child(_label)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_coin.custom_minimum_size = Vector2.ONE * UiScale.dp(_font_dp * 1.1)
	(_coin.get_parent() as HBoxContainer).add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_label.add_theme_font_size_override("font_size", UiScale.hud_font(_font_dp))


## Larger readout (the shop shows the money prominently).
func set_font_dp(size_dp: float) -> void:
	_font_dp = size_dp
	if is_inside_tree():
		apply_scale()


func set_amount(n: int) -> void:
	_amount = n
	_refresh()


func get_amount() -> int:
	return _amount


func get_text() -> String:
	return _label.text


func _refresh() -> void:
	_label.text = HudFormat.group(_amount)


func _draw_coin() -> void:
	var c: Vector2 = _coin.size * 0.5
	var r: float = minf(_coin.size.x, _coin.size.y) * 0.45
	_coin.draw_circle(c, r * 1.25, Color(NeonPalette.WARN, 0.2))
	_coin.draw_arc(c, r, 0.0, TAU, 20, NeonPalette.WARN, maxf(1.5, r * 0.18), true)
	_coin.draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), NeonPalette.WARN, maxf(1.5, r * 0.2), true)
