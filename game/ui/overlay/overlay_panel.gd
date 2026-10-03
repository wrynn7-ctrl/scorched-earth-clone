class_name OverlayPanel
extends Control
## Base for full-screen modal overlays (pause, settings, round summary, standings): a dimmed backdrop that
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
var _stat_tables: Array[StatTable] = []
var _stat_scrolls: Array[ScrollContainer] = []
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
	LayoutWatch.attach(self, apply_scale, true)


func apply_scale() -> void:
	LayoutGuard.fit(self)
	var pad: int = roundi(UiScale.dp(16.0))
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	# Wider with big text so titles wrap onto fewer lines (a phone in landscape has little height).
	var min_w: float = minf(UiScale.dp(300.0 * maxf(1.0, UiScale.text_scale)), get_viewport_rect().size.x * 0.92)
	if not _stat_tables.is_empty():
		min_w = maxf(min_w, minf(UiScale.dp(460.0), get_viewport_rect().size.x * 0.92))  # tables want room
	_panel.custom_minimum_size = Vector2(min_w, 0.0)
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
	for t: StatTable in _stat_tables:
		t.apply_scale()
	_fit_scrolls()


## Sizes each stat-table scroll area to its content, but never so tall that the panel would
## leave the screen (a phone in landscape is only ~330 dp high); extra rows scroll.
func _fit_scrolls() -> void:
	if _stat_scrolls.is_empty():
		return
	var sep: float = float(_box.get_theme_constant("separation"))
	var other: float = 0.0
	for c: Node in _box.get_children():
		if c is Control and not (c is ScrollContainer and _stat_scrolls.has(c as ScrollContainer)) and (c as Control).visible:
			other += (c as Control).get_combined_minimum_size().y + sep
	var frame: float = _panel.get_theme_stylebox("panel").get_minimum_size().y + UiScale.dp(32.0)
	var avail: float = get_viewport_rect().size.y * 0.97 - frame - other - sep * float(_stat_scrolls.size())
	for i: int in range(_stat_scrolls.size()):
		var want: float = _stat_tables[i].content_height()
		_stat_scrolls[i].custom_minimum_size.y = clampf(want, 0.0, maxf(avail, UiScale.dp(72.0)))
	# The estimate above ignores wrapped labels: measure the real panel, then grow or trim the
	# (first) table so the panel just fits.
	var room: float = get_viewport_rect().size.y * 0.97 - _panel.get_combined_minimum_size().y
	var scroll: ScrollContainer = _stat_scrolls[0]
	var target: float = scroll.custom_minimum_size.y + room
	scroll.custom_minimum_size.y = clampf(target, minf(UiScale.dp(72.0), _stat_tables[0].content_height()), _stat_tables[0].content_height())


func open() -> void:
	visible = true
	if is_inside_tree():
		_fit_scrolls()
		_refit_next_frame()


## Container minimum sizes only settle after a frame, so measure again then.
func _refit_next_frame() -> void:
	if _stat_scrolls.is_empty():
		return
	await get_tree().process_frame
	if visible and is_inside_tree():
		_fit_scrolls()


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


## A "Caption ...... Value" row whose button cycles through several values: `on_press` runs on each
## tap and should update the button text. Returns the button.
func add_cycle(caption: String, value_text: String, on_press: Callable) -> Button:
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
	b.text = value_text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	_btn_dp[b] = [84.0, 14.0]
	_buttons.append(b)
	row.add_child(b)
	return b


## A scrollable table (round summary, standings). Returns the table; fill it with set_data().
func add_stat_table() -> StatTable:
	var scroll := TouchScroll.new()
	scroll.name = "TableScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var table := StatTable.new()
	scroll.add_child(table)
	_target.add_child(scroll)
	_stat_tables.append(table)
	_stat_scrolls.append(scroll)
	return table


## "Caption   [-] value [+]" row. `on_step(direction)` gets -1 / +1. Returns {minus, plus, value}.
func add_stepper(caption: String, value_text: String, on_step: Callable) -> Dictionary:
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
	var minus := Button.new()
	minus.text = "-"
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func() -> void: on_step.call(-1))
	_btn_dp[minus] = [48.0, 18.0]
	_buttons.append(minus)
	row.add_child(minus)
	var value := Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size.x = UiScale.dp(64.0)
	_font_dp[value] = 15.0
	_labels.append(value)
	row.add_child(value)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func() -> void: on_step.call(1))
	_btn_dp[plus] = [48.0, 18.0]
	_buttons.append(plus)
	row.add_child(plus)
	return {"minus": minus, "plus": plus, "value": value}
