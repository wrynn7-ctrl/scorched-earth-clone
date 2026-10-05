class_name SuddenDeathIndicator
extends PanelContainer
## The small persistent "SUDDEN DEATH" tag under the turn banner while sudden death is active in the round
## (ARCHITECTURE section 42), with the HP the next drain takes. The battle controller derives its state from
## the match (turn_number >= Simulation.sudden_death_turn), so it is right after Continue as well.

var _label: Label = null
var _style: StyleBoxFlat = StyleBoxFlat.new()
var _drain: int = 0


func _init() -> void:
	name = "SuddenDeathIndicator"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_style.bg_color = Color(NeonPalette.BG_DEEP, 0.78)
	_style.border_color = NeonPalette.BAD
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	add_theme_stylebox_override("panel", _style)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	add_child(_label)
	_refresh()


func _ready() -> void:
	apply_scale()


## Shows or hides the tag; `next_drain` is the HP the next drain takes from every living tank (0 = unknown).
func set_active(active: bool, next_drain: int = 0) -> void:
	_drain = next_drain
	visible = active
	_refresh()


func is_active() -> bool:
	return visible


func get_next_drain() -> int:
	return _drain


func get_text() -> String:
	return _label.text


func apply_scale() -> void:
	_label.add_theme_font_size_override("font_size", UiScale.hud_font(11.0))
	_style.content_margin_left = UiScale.dp(8.0)
	_style.content_margin_right = UiScale.dp(8.0)
	_style.content_margin_top = UiScale.dp(2.0)
	_style.content_margin_bottom = UiScale.dp(2.0)


func _refresh() -> void:
	var t: String = tr("HUD_SUDDEN_DEATH")
	if _drain > 0:
		t += " · " + tr("HUD_SUDDEN_NEXT_FMT") % _drain
	_label.text = t


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_refresh()
