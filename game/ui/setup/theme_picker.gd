class_name ThemePicker
extends OverlayPanel
## The terrain-theme chooser on the setup screen: the five themes and "Random", as big touch
## targets with a tiny preview each. Themes that need the full game stay visible, marked with
## a lock and the words "FULL GAME" (the text is the cue; colour is never the only one).
## Tapping one reports `locked_chosen` instead of choosing it (a later task opens the Unlock
## screen from there). Tapping outside the panel or CANCEL closes without a choice.

signal chosen(id: String)
signal locked_chosen(id: String)

const TARGET_HEIGHT_DP: float = 56.0

var _title: Label = null
var _options: Dictionary = {}
var _locks: Dictionary = {}
var _order: PackedStringArray = PackedStringArray()
var _back: Button = null


func _init() -> void:
	super._init()
	name = "ThemePicker"
	_title = add_label(tr("SETUP_THEME_PICK_TITLE"), 15.0, NeonPalette.CYAN)
	_title.name = "Title"
	begin_grid()
	_order = ThemeDefs.ids().duplicate()
	_order.append(ThemeDefs.RANDOM)
	for id: String in _order:
		var b: Button = add_button(tr(ThemeDefs.name_key(id)), 170.0)
		b.name = "Theme_" + id
		b.toggle_mode = true  # the current choice shows as pressed
		b.icon = ThemeSwatch.texture(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_option.bind(id))
		_options[id] = b
		_locks[id] = _make_lock(b)
	_back = add_button(tr("SETUP_BACK"), 170.0)
	_back.name = "Cancel"
	_back.pressed.connect(close)
	end_container()


func _make_lock(b: Button) -> Control:
	var lock := Control.new()
	lock.name = "Lock"
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	lock.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	lock.offset_left = -UiScale.dp(30.0)
	lock.offset_right = -4.0
	lock.draw.connect(func() -> void:
		ItemIcon.draw_lock(lock, lock.size * 0.5, minf(lock.size.x, lock.size.y) * 0.4, NeonPalette.WARN))
	b.add_child(lock)
	return lock


## Opens the picker with `current` highlighted. Without the full game, themes whose tier is
## "full" carry the lock and the FULL GAME words.
func open_for(current: String, full: bool) -> void:
	for id: String in _order:
		var b: Button = _options[id]
		var locked: bool = ThemeDefs.is_locked(id, full)
		var label: String = tr(ThemeDefs.name_key(id))
		b.text = "%s\n%s" % [label, tr("SETUP_FULL_GAME")] if locked else label
		b.set_pressed_no_signal(id == current)
		b.tooltip_text = label
		(_locks[id] as Control).visible = locked
	open()
	if is_inside_tree():
		apply_scale()


func get_option(id: String) -> Button:
	return _options[id] as Button


func is_lock_shown(id: String) -> bool:
	return (_locks[id] as Control).visible


func get_cancel_button() -> Button:
	return _back


func get_panel() -> PanelContainer:
	return _panel


func apply_scale() -> void:
	super.apply_scale()
	for id: String in _order:
		var b: Button = _options[id]
		b.custom_minimum_size.y = UiScale.dp(TARGET_HEIGHT_DP)
		b.add_theme_font_size_override("font_size", UiScale.font(14.0))
		b.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(52.0)))
		b.clip_text = true
		(_locks[id] as Control).offset_left = -UiScale.dp(30.0)
	_back.custom_minimum_size.y = UiScale.dp(TARGET_HEIGHT_DP)


func _on_option(id: String) -> void:
	var locked: bool = (_locks[id] as Control).visible
	close()
	if locked:
		locked_chosen.emit(id)
	else:
		chosen.emit(id)


## A tap on the dimmed area outside the panel dismisses the picker.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
			accept_event()
