class_name OverlayPanel
extends Control
## Base for full-screen modal overlays (pause, round end, match end): a dimmed backdrop that
## swallows input, and a centred neon panel holding a vertical stack built in code.
## Sizes derive from UiScale. Subclasses call the add_* helpers in _init/_build.

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _dim: ColorRect = null
var _center: CenterContainer = null
var _panel: PanelContainer = null
var _margin: MarginContainer = null
var _box: VBoxContainer = null
var _buttons: Array[Button] = []
var _labels: Array[Label] = []
var _tally_box: VBoxContainer = null
var _font_dp: Dictionary = {}
var _btn_dp: Dictionary = {}  # Button -> [min width in dp, font dp]
## Where the add_* helpers put new controls (defaults to the main column).
var _target: Container = null


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.6)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_center = CenterContainer.new()
	_center.name = "Center"
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_center.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_box.name = "Box"
	_margin.add_child(_box)
	_target = _box
	visible = false


func _ready() -> void:
	apply_scale()
	get_viewport().size_changed.connect(apply_scale)


func apply_scale() -> void:
	var pad: int = roundi(UiScale.dp(16.0))
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_panel.custom_minimum_size = Vector2(UiScale.dp(300.0), 0.0)
	for c: Node in _box.find_children("*", "Container", true, false):
		if c is GridContainer:
			(c as GridContainer).add_theme_constant_override("h_separation", roundi(UiScale.dp(16.0)))
			(c as GridContainer).add_theme_constant_override("v_separation", roundi(UiScale.dp(8.0)))
		elif c is HBoxContainer:
			(c as HBoxContainer).add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	for b: Button in _buttons:
		var spec: Array = _btn_dp[b]
		b.custom_minimum_size = Vector2(UiScale.dp(float(spec[0])), UiScale.touch())
		b.add_theme_font_size_override("font_size", UiScale.font(float(spec[1])))
	for l: Label in _labels:
		l.add_theme_font_size_override("font_size", UiScale.font(float(_font_dp[l])))
	if _tally_box != null:
		_rebuild_tally_sizes()


func open() -> void:
	visible = true


func close() -> void:
	visible = false


func add_title(text: String, color: Color = NeonPalette.CYAN, size_dp: float = 23.0) -> Label:
	var l: Label = add_label(text, size_dp, color)
	return l


func add_label(text: String, size_dp: float = 16.0, color: Color = NeonPalette.TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	_font_dp[l] = size_dp
	_labels.append(l)
	_target.add_child(l)
	return l


## A full-width button in the current target (width_dp is the minimum width).
func add_button(text: String, width_dp: float = 260.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_dp[b] = [width_dp, 17.0]
	_buttons.append(b)
	_target.add_child(b)
	return b


## Starts a horizontal row; following add_* calls go into it until end_container().
func begin_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	_box.add_child(row)
	_target = row
	return row


## Starts a 2-column grid (used for the settings toggles).
func begin_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	_box.add_child(g)
	_target = g
	return g


func end_container() -> void:
	_target = _box


## A "Caption ...... ON/OFF" row; `on_changed(bool)` is called after each press. Returns the button.
func add_toggle(caption: String, value: bool, on_changed: Callable) -> Button:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.add_child(row)
	var l := Label.new()
	l.text = caption
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_font_dp[l] = 15.0
	_labels.append(l)
	row.add_child(l)
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.button_pressed = value
	b.text = tr("SET_ON") if value else tr("SET_OFF")
	b.toggled.connect(func(on: bool) -> void:
		b.text = tr("SET_ON") if on else tr("SET_OFF")
		on_changed.call(on))
	_btn_dp[b] = [84.0, 14.0]
	_buttons.append(b)
	row.add_child(b)
	return b


## Per-player rows: emblem, name, round wins. `highlight` (>= 0) brightens that player.
func set_tally(wins: PackedInt32Array, highlight: int = -1) -> void:
	if _tally_box == null:
		_tally_box = VBoxContainer.new()
		_tally_box.name = "Tally"
		_box.add_child(_tally_box)
	for c: Node in _tally_box.get_children():
		_tally_box.remove_child(c)
		c.free()
	for i: int in range(wins.size()):
		var row := HBoxContainer.new()
		row.name = "Row%d" % i
		var icon := EmblemIcon.new()
		icon.set_index(i)
		row.add_child(icon)
		var name_l := Label.new()
		name_l.text = tr("HUD_PLAYER_N") % (i + 1)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var col: Color = NeonPalette.tank_color(i)
		name_l.add_theme_color_override("font_color", col if (highlight < 0 or highlight == i) else col.darkened(0.35))
		row.add_child(name_l)
		var score := Label.new()
		score.text = str(wins[i])
		score.add_theme_color_override("font_color", NeonPalette.HOT if highlight == i else NeonPalette.TEXT)
		row.add_child(score)
		_tally_box.add_child(row)
	_rebuild_tally_sizes()


func get_tally_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if _tally_box == null:
		return ""
	for row: Node in _tally_box.get_children():
		parts.append("%s %s" % [(row.get_child(1) as Label).text, (row.get_child(2) as Label).text])
	return ", ".join(parts)


func _rebuild_tally_sizes() -> void:
	var fs: int = UiScale.font(20.0)
	for row: Node in _tally_box.get_children():
		(row.get_child(0) as Control).custom_minimum_size = Vector2.ONE * UiScale.dp(26.0)
		(row.get_child(1) as Label).add_theme_font_size_override("font_size", fs)
		(row.get_child(2) as Label).add_theme_font_size_override("font_size", fs)
		(row as HBoxContainer).add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
