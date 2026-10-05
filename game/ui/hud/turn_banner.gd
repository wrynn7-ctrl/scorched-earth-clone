class_name TurnBanner
extends PanelContainer
## "PLAYER 2'S TURN" banner in the player's colour with their emblem. A computer player's turn
## reads "CPU NORMAL — PLAYER 3" and can show a small "thinking…" line underneath.
## show_turn() plays a short pop-in; the banner then stays (set auto_hide_seconds > 0 to fade).

## Below this screen width (dp) a CPU banner wraps onto two lines (see _fit_width).
const WRAP_BELOW_DP: float = 820.0
const WRAP_WIDTH_DP: float = 118.0

var auto_hide_seconds: float = 0.0

var _index: int = 0
var _player_name: String = ""
var _emblem: EmblemIcon = null
## The team letter badge (only in team matches, ARCHITECTURE section 42).
var _badge: TeamBadge = null
var _label: Label = null
var _tween: Tween = null
var _thinking: Label = null
var _think_tween: Tween = null
## SimConstants.CTRL_* of the player shown (0 = a human, the plain "PLAYER n'S TURN" text).
var _level: int = 0
## Love Edition: a small drawn heart on each side of the text.
var _heart_l: HeartIcon = null
var _heart_r: HeartIcon = null
var _love: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.name = "Box"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	_heart_l = HeartIcon.new()
	_heart_l.name = "HeartLeft"
	_heart_l.visible = false
	row.add_child(_heart_l)
	_badge = TeamBadge.new()
	row.add_child(_badge)
	_emblem = EmblemIcon.new()
	_emblem.name = "Emblem"
	row.add_child(_emblem)
	_label = Label.new()
	_label.name = "Text"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	_heart_r = HeartIcon.new()
	_heart_r.name = "HeartRight"
	_heart_r.visible = false
	row.add_child(_heart_r)
	_thinking = Label.new()
	_thinking.name = "Thinking"
	_thinking.text = tr("HUD_THINKING")
	_thinking.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_thinking.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thinking.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_thinking.visible = false
	box.add_child(_thinking)


func _ready() -> void:
	apply_scale()
	_refresh()


func apply_scale() -> void:
	# Not scaled by the text-size setting: the banner shares the top row with the speed and pause
	# buttons on a 700 dp phone and would push them off screen at 150%.
	_label.add_theme_font_size_override("font_size", maxi(8, roundi(UiScale.dp(15.0))))
	_emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(28.0)
	_badge.set_badge_size(UiScale.dp(22.0))
	_heart_l.set_icon_size(UiScale.dp(18.0))
	_heart_r.set_icon_size(UiScale.dp(18.0))
	_thinking.add_theme_font_size_override("font_size", maxi(8, roundi(UiScale.dp(11.0))))
	if _index >= 0 and _label.text != "":
		_fit_width()


## player_index selects colour + emblem. Empty name = "PLAYER n".
func show_turn(player_index: int, player_name: String = "") -> void:
	_show(player_index, player_name, 0)


func _show(player_index: int, player_name: String, level: int) -> void:
	_level = level
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


## The team of the player shown (0..3 for a badge, anything else for none). Call before show_turn().
func set_team(team: int) -> void:
	_badge.set_team(team)


func get_badge() -> TeamBadge:
	return _badge


## A computer player's turn: "CPU NORMAL — PLAYER 3". `level` is a SimConstants.CTRL_* value.
func show_cpu_turn(player_index: int, level: int) -> void:
	_show(player_index, "", level)


## The small "thinking…" line under the text (pulses unless motion is reduced).
func set_thinking(on: bool) -> void:
	_thinking.visible = on
	if _think_tween != null:
		_think_tween.kill()
		_think_tween = null
	_thinking.modulate.a = 1.0
	if on and not ShowSettings.reduce_motion and is_inside_tree():
		_think_tween = create_tween().set_loops()
		_think_tween.tween_property(_thinking, "modulate:a", 0.35, 0.6).set_trans(Tween.TRANS_SINE)
		_think_tween.tween_property(_thinking, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)


## Love Edition: hearts beside the text, in the player's pink.
func set_love_mode(on: bool) -> void:
	_love = on
	_heart_l.visible = on
	_heart_r.visible = on


func is_love_mode() -> bool:
	return _love


func has_heart_accents() -> bool:
	return _heart_l.visible and _heart_r.visible


func is_thinking() -> bool:
	return _thinking.visible


func get_thinking_text() -> String:
	return _thinking.text


func get_text() -> String:
	return _label.text


func _refresh() -> void:
	var shown: String = _player_name if _player_name != "" else PlayerNames.label(_index)
	if _level > 0:
		_label.text = tr("HUD_CPU_TURN_FMT") % [CpuNames.level_word(_level), shown]
	else:
		_label.text = tr("HUD_TURN_OF") % shown
	_fit_width()
	_thinking.text = tr("HUD_THINKING")
	var c: Color = PlayerLooks.color(_index)
	_label.add_theme_color_override("font_color", c)
	_emblem.set_index(_index)


## "CPU EXPERT — PLAYER 8" is about 55 dp longer than the plain banner and would push the power
## panel off a ~700 dp phone, so on narrow screens it wraps onto two lines ("CPU EXPERT —" /
## "PLAYER 8"); wider screens keep one line.
func _fit_width() -> void:
	var narrow: bool = _level > 0 and is_inside_tree() and get_viewport_rect().size.x < UiScale.dp(WRAP_BELOW_DP)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if narrow else TextServer.AUTOWRAP_OFF
	_label.custom_minimum_size.x = UiScale.dp(WRAP_WIDTH_DP) if narrow else 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_refresh()
