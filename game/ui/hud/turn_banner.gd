class_name TurnBanner
extends PanelContainer
## "PLAYER 2'S TURN" banner in the player's colour with their emblem.
## show_turn() plays a short pop-in; the banner then stays (set auto_hide_seconds > 0 to fade).

var auto_hide_seconds: float = 0.0

var _index: int = 0
var _player_name: String = ""
var _emblem: EmblemIcon = null
var _label: Label = null
var _tween: Tween = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	_emblem = EmblemIcon.new()
	_emblem.name = "Emblem"
	row.add_child(_emblem)
	_label = Label.new()
	_label.name = "Text"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	_label.add_theme_font_size_override("font_size", UiScale.font(16.0))
	_emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(28.0)


## player_index selects colour + emblem. Empty name = "PLAYER n".
func show_turn(player_index: int, player_name: String = "") -> void:
	_index = player_index
	_player_name = player_name
	_refresh()
	visible = true
	if _tween != null:
		_tween.kill()
	if ShowSettings.reduce_motion:
		modulate = Color.WHITE
	else:
		modulate = Color(1, 1, 1, 0)
		_tween = create_tween()
		_tween.tween_property(self, "modulate:a", 1.0, 0.25)
	if auto_hide_seconds > 0.0:
		if _tween == null:
			_tween = create_tween()
		_tween.tween_interval(auto_hide_seconds)
		_tween.tween_property(self, "modulate:a", 0.0, 0.4)


func get_text() -> String:
	return _label.text


func _refresh() -> void:
	var shown: String = _player_name if _player_name != "" else tr("HUD_PLAYER_N") % (_index + 1)
	_label.text = tr("HUD_TURN_OF") % shown
	var c: Color = NeonPalette.tank_color(_index)
	_label.add_theme_color_override("font_color", c)
	_emblem.set_index(_index)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_refresh()
