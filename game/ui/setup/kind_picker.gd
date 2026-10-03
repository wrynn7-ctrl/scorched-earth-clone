class_name KindPicker
extends OverlayPanel
## The "who controls this slot" chooser on the setup screen: Human, CPU Easy, CPU Normal, CPU
## Hard, CPU Expert, laid out as a 2-column grid of big (56 dp) touch targets in a centred panel.
## A phone in landscape is only ~320 dp high, so the grid keeps the panel short. Hard and Expert
## carry a lock icon and the words "FULL GAME" while the full game is not unlocked (the text is
## the cue; colour is never the only one).
##
## Tapping outside the panel or BACK closes it without a choice.

## `level` is a SimConstants.CTRL_* value.
signal chosen(level: int)

const TARGET_HEIGHT_DP: float = 56.0

var _title: Label = null
var _options: Array[Button] = []
var _locks: Array[Control] = []
var _back: Button = null
var _player: int = 0


func _init() -> void:
	super._init()
	name = "KindPicker"
	_title = add_label("", 15.0, NeonPalette.CYAN)
	_title.name = "Title"
	begin_grid()
	for level: int in range(SimConstants.CTRL_MAX + 1):
		var b: Button = add_button(CpuNames.full_name(level), 170.0)
		b.name = "Level%d" % level
		b.toggle_mode = true  # the current choice shows as pressed
		b.pressed.connect(_on_option.bind(level))
		_options.append(b)
		_locks.append(_make_lock(b))
	_back = add_button(tr("SETUP_BACK"), 170.0)
	_back.name = "Cancel"
	_back.pressed.connect(close)
	end_container()


func _make_lock(b: Button) -> Control:
	var lock := Control.new()
	lock.name = "Lock"
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	lock.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	lock.offset_left = 6.0
	lock.offset_right = 6.0 + UiScale.dp(28.0)
	lock.draw.connect(func() -> void:
		ItemIcon.draw_lock(lock, lock.size * 0.5, minf(lock.size.x, lock.size.y) * 0.4, NeonPalette.WARN))
	b.add_child(lock)
	return lock


## Opens the picker for `player` (0-based). `current` is highlighted; levels above
## SimConstants.CTRL_FREE_MAX are locked when `full_unlocked` is false.
func open_for(player: int, current: int, full_unlocked: bool) -> void:
	_player = player
	_title.text = tr("SETUP_PICK_TITLE") % (player + 1)
	for level: int in range(_options.size()):
		var b: Button = _options[level]
		var locked: bool = not full_unlocked and level > SimConstants.CTRL_FREE_MAX
		b.disabled = locked
		b.text = tr("SETUP_PICK_LOCKED_FMT") % CpuNames.full_name(level) if locked else CpuNames.full_name(level)
		b.set_pressed_no_signal(level == current)
		_locks[level].visible = locked
	open()
	if is_inside_tree():
		apply_scale()


func get_option(level: int) -> Button:
	return _options[level]


func get_cancel_button() -> Button:
	return _back


func get_panel() -> PanelContainer:
	return _panel


func get_player() -> int:
	return _player


func apply_scale() -> void:
	super.apply_scale()
	for b: Button in _options:
		b.custom_minimum_size.y = UiScale.dp(TARGET_HEIGHT_DP)
		b.add_theme_font_size_override("font_size", UiScale.font(15.0))
		b.clip_text = true
	_back.custom_minimum_size.y = UiScale.dp(TARGET_HEIGHT_DP)
	# Room for the lock icon on locked entries.
	for i: int in range(_options.size()):
		_locks[i].offset_right = 6.0 + UiScale.dp(28.0)


func _on_option(level: int) -> void:
	close()
	chosen.emit(level)


## A tap on the dimmed area outside the panel dismisses the picker.
func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			close()
			accept_event()
