class_name BigTurnBanner
extends Control
## The big "<NAME>'S TURN" call-out that opens each human turn when two or more humans share the
## device (ARCHITECTURE section 42). It is drawn in the player's colour over the battle, fades in
## and out by itself (about 1.2 s) and never takes input: every node in it ignores the mouse, so
## the player can aim straight through it. No cover screen, no waiting.
##
## Reduce motion (ShowSettings.reduce_motion): no scaling and a quicker fade. Love Edition: a
## drawn heart on each side of the text.

const SHOW_SECONDS: float = 1.2
## Phases: fade in, hold, fade out (they add up to SHOW_SECONDS).
const IN_SECONDS: float = 0.2
const HOLD_SECONDS: float = 0.7
const OUT_SECONDS: float = 0.3
const CALM_IN_SECONDS: float = 0.08
const CALM_HOLD_SECONDS: float = 0.6
const CALM_OUT_SECONDS: float = 0.2
const POP_FROM: float = 0.85
const FONT_DP: float = 34.0
const MIN_FONT_DP: float = 14.0
## Share of the screen width the text may use.
const MAX_WIDTH_SHARE: float = 0.92
## Where the text sits, as a share of the screen height (above the tanks' usual aim area).
const TOP_SHARE: float = 0.24

var _row: HBoxContainer = null
var _label: Label = null
var _heart_l: HeartIcon = null
var _heart_r: HeartIcon = null
## The team letter badge before the name (team matches only).
var _badge: TeamBadge = null
var _t: float = 0.0
var _t_in: float = IN_SECONDS
var _t_hold: float = HOLD_SECONDS
var _t_out: float = OUT_SECONDS
var _showing: bool = false
var _love: bool = false
var _index: int = 0
var _player_name: String = ""


func _init() -> void:
	name = "BigTurnBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.anchor_left = 0.0
	_row.anchor_right = 1.0
	_row.anchor_top = TOP_SHARE
	_row.anchor_bottom = TOP_SHARE
	_row.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_row)
	_heart_l = _heart("HeartLeft")
	_badge = TeamBadge.new()
	_row.add_child(_badge)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_outline_color", Color(NeonPalette.BG_DEEP, 0.95))
	_row.add_child(_label)
	_heart_r = _heart("HeartRight")


func _heart(node_name: String) -> HeartIcon:
	var h := HeartIcon.new()
	h.name = node_name
	h.visible = false
	_row.add_child(h)
	return h


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale)


## Shows the banner for `player_index` (colour comes from PlayerLooks) and fades it away again.
func show_turn(player_index: int, player_name: String, love: bool = false, team: int = TeamStyle.NONE) -> void:
	_badge.set_team(team)
	_index = player_index
	_player_name = player_name
	_love = love
	_heart_l.visible = love
	_heart_r.visible = love
	_label.text = tr("HUD_BIG_TURN") % player_name
	var c: Color = PlayerLooks.color(player_index)
	_label.add_theme_color_override("font_color", c)
	_label.add_theme_color_override("font_shadow_color", Color(c, 0.55))
	_heart_l.color = c.lightened(0.15)
	_heart_r.color = c.lightened(0.15)
	apply_scale()
	_play()


func _play() -> void:
	var calm: bool = ShowSettings.reduce_motion
	_t_in = CALM_IN_SECONDS if calm else IN_SECONDS
	_t_hold = CALM_HOLD_SECONDS if calm else HOLD_SECONDS
	_t_out = CALM_OUT_SECONDS if calm else OUT_SECONDS
	_t = 0.0
	_showing = true
	visible = true
	set_process(true)
	_apply_progress()


func _process(delta: float) -> void:
	advance(delta)


## Moves the animation on by `seconds` (the engine calls this every frame; tests call it directly).
func advance(seconds: float) -> void:
	if not _showing:
		return
	_t += seconds
	if _t >= _t_in + _t_hold + _t_out:
		hide_now()
		return
	_apply_progress()


## Opacity and (unless motion is reduced) the small pop-in for the current time.
func _apply_progress() -> void:
	var a: float = 1.0
	if _t < _t_in:
		a = _t / _t_in
	elif _t > _t_in + _t_hold:
		a = 1.0 - (_t - _t_in - _t_hold) / _t_out
	modulate = Color(1, 1, 1, clampf(a, 0.0, 1.0))
	var k: float = 1.0
	if not ShowSettings.reduce_motion and _t < _t_in:
		var f: float = _t / _t_in
		k = POP_FROM + (1.0 - POP_FROM) * (1.0 - pow(1.0 - f, 3.0))
	_row.pivot_offset = _row.size * 0.5
	_row.scale = Vector2(k, k)


## Hides it immediately (a new turn starts, or the match is left).
func hide_now() -> void:
	_showing = false
	visible = false
	modulate = Color(1, 1, 1, 0)
	set_process(false)


func apply_scale() -> void:
	var vw: float = get_viewport_rect().size.x if is_inside_tree() else 1000.0
	var base: int = UiScale.hud_font(FONT_DP)
	var chosen: int = base
	var font: Font = _label.get_theme_font("font")
	var hearts: float = 2.0 * UiScale.dp(40.0) if _love else 0.0
	if _badge.visible:
		hearts += UiScale.dp(44.0)
	var room: float = vw * MAX_WIDTH_SHARE - hearts
	if font != null and _label.text != "":
		var w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base).x
		if w > room and w > 0.0:
			chosen = maxi(roundi(UiScale.dp(MIN_FONT_DP)), floori(float(base) * room / w))
	_label.add_theme_font_size_override("font_size", chosen)
	_label.add_theme_constant_override("outline_size", maxi(2, roundi(chosen * 0.12)))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 0)
	_label.add_theme_constant_override("shadow_outline_size", maxi(2, roundi(chosen * 0.35)))
	_badge.set_badge_size(UiScale.dp(30.0) * float(chosen) / float(maxi(1, base)))
	var heart_px: float = UiScale.dp(36.0) * float(chosen) / float(maxi(1, base))
	_heart_l.set_icon_size(heart_px)
	_heart_r.set_icon_size(heart_px)


# --- accessors (tests, tools) ---

func is_showing() -> bool:
	return _showing


func get_text() -> String:
	return _label.text


func get_label() -> Label:
	return _label


func get_player() -> int:
	return _index


func is_love() -> bool:
	return _love


func get_badge() -> TeamBadge:
	return _badge


func has_hearts() -> bool:
	return _heart_l.visible and _heart_r.visible


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null and _showing:
		_label.text = tr("HUD_BIG_TURN") % _player_name
