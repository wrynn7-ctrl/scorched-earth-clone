class_name MessagePicker
extends Control
## The popup behind the quick-message button: the eight presets as big buttons (2 rows of 4), text for the phrases and a
## drawn icon for the emotes. After a message the buttons stay off for COOLDOWN_SECONDS (the backend allows one message
## per 3 s per player) and the caption counts it down. A tap outside the panel closes the popup.

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

signal chosen(msg: int)
signal closed

var _panel: PanelContainer = null
var _grid: GridContainer = null
var _caption: Label = null
var _buttons: Array[Button] = []
var _cooldown: float = 0.0


func _init() -> void:
	theme = THEME
	name = "MessagePicker"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	center.add_child(_panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "Box"
	margin.add_child(box)
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_color_override("font_color", NeonPalette.CYAN)
	box.add_child(_caption)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.columns = 4
	box.add_child(_grid)
	for i: int in range(MessageDefs.COUNT):
		var b := Button.new()
		b.name = "Msg%d" % i
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.accessibility_name = MessageDefs.text_of(i)
		b.tooltip_text = MessageDefs.text_of(i)
		if MessageDefs.has_icon(i):
			var icon := MessageIcon.new(MessageDefs.icon_of(i))
			icon.name = "Icon"
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 6.0
			icon.offset_right = -6.0
			icon.offset_top = 6.0
			icon.offset_bottom = -6.0
			b.add_child(icon)
		else:
			b.text = MessageDefs.text_of(i)
		b.pressed.connect(choose.bind(i))
		_grid.add_child(b)
		_buttons.append(b)
	set_process(false)


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale)


func apply_scale() -> void:
	var pad: int = roundi(UiScale.dp(12.0))
	for side: String in ["left", "top", "right", "bottom"]:
		(_panel.get_child(0) as MarginContainer).add_theme_constant_override("margin_" + side, pad)
	(_panel.get_child(0).get_child(0) as VBoxContainer).add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(8.0)))
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(8.0)))
	var w: float = minf(UiScale.dp(88.0), (get_viewport_rect().size.x * 0.9 - UiScale.dp(24.0 + 24.0)) / 4.0)
	for b: Button in _buttons:
		b.custom_minimum_size = Vector2(w, maxf(UiScale.touch(), UiScale.dp(56.0)))
		b.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))
	_caption.add_theme_font_size_override("font_size", UiScale.hud_font(13.0))
	_refresh()


func open() -> void:
	visible = true
	_refresh()
	apply_scale()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func is_open() -> bool:
	return visible


func get_button(msg: int) -> Button:
	return _buttons[msg]


func get_caption_text() -> String:
	return _caption.text


## Starts the cooldown (seconds): the buttons are off until it ends.
func start_cooldown(seconds: float = MessageDefs.COOLDOWN_SECONDS) -> void:
	_cooldown = seconds
	set_process(true)
	_refresh()


func cooldown_left() -> float:
	return _cooldown


func is_cooling_down() -> bool:
	return _cooldown > 0.0


func _process(delta: float) -> void:
	if _cooldown <= 0.0:
		set_process(false)
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_refresh()


func _refresh() -> void:
	var cooling: bool = _cooldown > 0.0
	for b: Button in _buttons:
		b.disabled = cooling
	_caption.text = tr("NET_MSG_WAIT") % ceili(_cooldown) if cooling else tr("NET_MSG_TITLE")


## Picks message `msg`: ignored during the cooldown. The popup closes and `chosen` fires.
func choose(msg: int) -> void:
	if _cooldown > 0.0 or not MessageDefs.is_valid(msg):
		return
	start_cooldown()
	close()
	chosen.emit(msg)


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
			accept_event()
