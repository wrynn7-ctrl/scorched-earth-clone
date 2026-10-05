class_name HandoverScreen
extends Control
## "PLAYER N - YOUR SHOP": shown before each player's shop so the others do not see what is
## bought. The whole screen is one big tap target.

signal continued

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _tap: Button = null
var _box: VBoxContainer = null
var _emblem: EmblemIcon = null
var _title: Label = null
var _hint: Label = null
var _tap_label: Label = null
var _player: int = 0
var _pulse: Tween = null


func _init() -> void:
	theme = THEME
	name = "HandoverScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(NeonPalette.BG_DEEP, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_tap = Button.new()
	_tap.name = "Tap"
	_tap.flat = true
	_tap.focus_mode = Control.FOCUS_NONE
	_tap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state_name: String in ["normal", "hover", "pressed", "focus"]:
		_tap.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	_tap.pressed.connect(func() -> void: continued.emit())
	add_child(_tap)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_box)
	_emblem = EmblemIcon.new()
	_emblem.name = "Emblem"
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_emblem)
	_title = _label("Title")
	_hint = _label("Hint")
	_hint.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_hint.text = tr("SHOP_PASS_HINT")
	_tap_label = _label("TapToContinue")
	_tap_label.add_theme_color_override("font_color", NeonPalette.HOT)
	_tap_label.text = tr("SHOP_TAP_CONTINUE")
	visible = false


func _label(label_name: String) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	return l


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale)


func apply_scale() -> void:
	_emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(72.0)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_hint.add_theme_font_size_override("font_size", UiScale.font(15.0))
	_tap_label.add_theme_font_size_override("font_size", UiScale.font(18.0))
	# Wrap the title before it can leave the screen on a narrow phone at a large text size.
	_title.custom_minimum_size.x = minf(get_viewport_rect().size.x * 0.9, UiScale.dp(640.0))
	_fit_title()


## One line when it can be: a long name shrinks the title (down to 60%) before it wraps.
func _fit_title() -> void:
	var base: int = UiScale.font(30.0)
	var chosen: int = base
	var font: Font = _title.get_theme_font("font")
	var room: float = _title.custom_minimum_size.x
	if font != null and room > 0.0 and _title.text != "":
		var w: float = font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, base).x
		if w > room:
			chosen = maxi(roundi(base * 0.6), floori(base * room / w))
	_title.add_theme_font_size_override("font_size", chosen)


func show_player(player: int) -> void:
	_player = player
	_emblem.set_index(player)
	_title.text = tr("SHOP_HANDOVER") % PlayerNames.label(player)
	_title.add_theme_color_override("font_color", PlayerLooks.color(player))
	_fit_title()
	visible = true
	if _pulse != null:
		_pulse.kill()
	_tap_label.modulate.a = 1.0
	if not ShowSettings.reduce_motion and is_inside_tree():
		_pulse = create_tween().set_loops()
		_pulse.tween_property(_tap_label, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
		_pulse.tween_property(_tap_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func hide_screen() -> void:
	visible = false
	if _pulse != null:
		_pulse.kill()
		_pulse = null


func get_player() -> int:
	return _player


func get_title_text() -> String:
	return _title.text


func get_tap_button() -> Button:
	return _tap
