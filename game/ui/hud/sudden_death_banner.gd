class_name SuddenDeathBanner
extends Control
## The big "SUDDEN DEATH" call-out that plays when the sudden_death event arrives (ARCHITECTURE section 42):
## red/amber neon text on a dark band with hazard-red edges. It fades in, holds and fades out by itself
## (about 2 s) and never takes input, so play continues underneath.
##
## Reduce motion: no scaling and a quicker fade. Reduce flashing: no glow pulse (it is a slow 1.5 Hz sine,
## never a blink, but it is dropped anyway). The text is the cue, colour only adds to it.

const IN_SECONDS: float = 0.18
const HOLD_SECONDS: float = 1.5
const OUT_SECONDS: float = 0.5
const CALM_IN_SECONDS: float = 0.08
const CALM_HOLD_SECONDS: float = 1.2
const CALM_OUT_SECONDS: float = 0.25
const POP_FROM: float = 1.35
const FONT_DP: float = 44.0
const MIN_FONT_DP: float = 16.0
const MAX_WIDTH_SHARE: float = 0.9
## Vertical centre as a share of the screen height (below the turn call-out, above the aim area).
const CENTER_SHARE: float = 0.40
const PULSE_HZ: float = 1.5

var _panel: PanelContainer = null
var _label: Label = null
var _style: StyleBoxFlat = StyleBoxFlat.new()
var _t: float = 0.0
var _t_in: float = IN_SECONDS
var _t_hold: float = HOLD_SECONDS
var _t_out: float = OUT_SECONDS
var _showing: bool = false
var _plays: int = 0


func _init() -> void:
	name = "SuddenDeathBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process(false)
	_panel = PanelContainer.new()
	_panel.name = "Band"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = CENTER_SHARE
	_panel.anchor_bottom = CENTER_SHARE
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_style.bg_color = Color(NeonPalette.BG_DEEP, 0.62)
	_style.border_color = Color(NeonPalette.BAD, 0.95)
	_style.border_width_top = 3
	_style.border_width_bottom = 3
	_panel.add_theme_stylebox_override("panel", _style)
	add_child(_panel)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text = tr("HUD_SUDDEN_DEATH")
	_label.add_theme_color_override("font_color", Color(1.0, 0.36, 0.28))
	_label.add_theme_color_override("font_outline_color", Color(NeonPalette.BG_DEEP, 0.95))
	_label.add_theme_color_override("font_shadow_color", Color(NeonPalette.SUNSET, 0.7))
	_panel.add_child(_label)


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale)


## Plays the call-out (a new call while one is showing restarts it).
func play() -> void:
	var calm: bool = ShowSettings.reduce_motion
	_t_in = CALM_IN_SECONDS if calm else IN_SECONDS
	_t_hold = CALM_HOLD_SECONDS if calm else HOLD_SECONDS
	_t_out = CALM_OUT_SECONDS if calm else OUT_SECONDS
	_t = 0.0
	_plays += 1
	_showing = true
	_label.text = tr("HUD_SUDDEN_DEATH")
	visible = true
	set_process(true)
	apply_scale()
	_apply_progress()


func _process(delta: float) -> void:
	advance(delta)


## Moves the animation on (the engine calls this every frame; tests call it directly).
func advance(seconds: float) -> void:
	if not _showing:
		return
	_t += seconds
	if _t >= _t_in + _t_hold + _t_out:
		hide_now()
		return
	_apply_progress()


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
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(k, k)
	var pulse: float = 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	var glow: float = 0.7 if (ShowSettings.reduce_flashing or ShowSettings.reduce_motion) else 0.45 + 0.4 * pulse
	_label.add_theme_color_override("font_shadow_color", Color(NeonPalette.SUNSET, glow))


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
	var room: float = vw * MAX_WIDTH_SHARE
	if font != null and _label.text != "":
		var w: float = font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base).x
		if w > room and w > 0.0:
			chosen = maxi(roundi(UiScale.dp(MIN_FONT_DP)), floori(float(base) * room / w))
	_label.add_theme_font_size_override("font_size", chosen)
	_label.add_theme_constant_override("outline_size", maxi(2, roundi(chosen * 0.12)))
	_label.add_theme_constant_override("shadow_offset_x", 0)
	_label.add_theme_constant_override("shadow_offset_y", 0)
	_label.add_theme_constant_override("shadow_outline_size", maxi(2, roundi(chosen * 0.35)))
	_style.set_content_margin_all(UiScale.dp(6.0))


# --- accessors (tests, tools) ---

func is_showing() -> bool:
	return _showing


## How many times play() was called (a test checks one drain event shows it once).
func play_count() -> int:
	return _plays


func get_text() -> String:
	return _label.text


func get_label() -> Label:
	return _label


func get_band() -> PanelContainer:
	return _panel


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _label != null:
		_label.text = tr("HUD_SUDDEN_DEATH")
