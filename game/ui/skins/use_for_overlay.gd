class_name UseForOverlay
extends OverlayPanel
## "USE FOR...": gives the skin being edited to player slots 1-8 (SkinStore assignments). Each slot is
## a toggle with its emblem and number and a text line saying whose look it has now (this skin,
## another skin, or the standard look), so colour is never the only cue. A Human player in that slot
## on this device wears the skin in a match; CPUs and online opponents never do.

signal changed

const PER_ROW: int = 2

var _skin_id: String = ""
var _tiles: Array[Button] = []
var _marks: Array[Control] = []
var _lines: Array[Label] = []
var _note: Label = null
var _done: Button = null
var _scroll: TouchScroll = null
var _content: VBoxContainer = null
var _grid: GridContainer = null


func _init() -> void:
	super._init()
	name = "UseForOverlay"
	add_title(tr("SKIN_USE_TITLE"), NeonPalette.CYAN, 20.0)
	# The slots and the note scroll, so BACK/DONE stay on screen on a short phone at large text.
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_grid = GridContainer.new()
	_grid.name = "Slots"
	_grid.columns = PER_ROW
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_grid)
	_target = _grid
	for i: int in range(SkinStore.MAX_SLOTS):
		var b := Button.new()
		b.name = "Slot%d" % i
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_on_slot.bind(i))
		_btn_dp[b] = [164.0, 12.0]
		_buttons.append(b)
		_target.add_child(b)
		_tiles.append(b)
		# The emblem (in the slot's default colour) sits at the button's right end.
		var mark := Control.new()
		mark.name = "Emblem"
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		mark.draw.connect(func() -> void:
			NeonPalette.draw_emblem(mark, NeonPalette.tank_emblem(i), mark.size * 0.5,
					minf(mark.size.x, mark.size.y) * 0.28, NeonPalette.tank_color(i)))
		b.add_child(mark)
		_marks.append(mark)
	_target = _content
	_note = add_label(tr("SKIN_USE_NOTE"), 12.0, NeonPalette.TEXT_DIM)
	_target = _box
	_done = add_button(tr("SKIN_USE_DONE"), 160.0)
	_done.name = "Done"
	_done.pressed.connect(close)


func get_tile(slot: int) -> Button:
	return _tiles[slot]


func get_done_button() -> Button:
	return _done


## Opens for the saved skin `skin_id`.
func open_for(skin_id: String) -> void:
	_skin_id = skin_id
	_refresh()
	open()
	if is_inside_tree():
		apply_scale()
		_fit_later()


func _fit_later() -> void:
	await get_tree().process_frame
	if visible and is_inside_tree():
		_fit_scroll()


func apply_scale() -> void:
	super.apply_scale()
	_grid.columns = 4 if get_viewport_rect().size.x >= UiScale.dp(760.0) else PER_ROW
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(8.0)))
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(8.0)))
	for i: int in range(_tiles.size()):
		(_marks[i] as Control).offset_left = -UiScale.touch()
		_tiles[i].custom_minimum_size.y = UiScale.touch() + UiScale.line_h(12.0) * 0.9
	_fit_scroll()


## The slot list takes the height the panel can spare; the rest scrolls.
func _fit_scroll() -> void:
	if _scroll == null or not is_inside_tree():
		return
	_scroll.custom_minimum_size.y = 0.0
	var others: float = _panel.get_combined_minimum_size().y
	var want: float = _content.get_combined_minimum_size().y
	var avail: float = get_viewport_rect().size.y * 0.96 - others
	_scroll.custom_minimum_size.y = clampf(want, minf(want, UiScale.dp(72.0)), maxf(avail, UiScale.dp(72.0)))


func _refresh() -> void:
	var a: Dictionary = SkinStore.assignments()
	for i: int in range(_tiles.size()):
		var current: String = str(a.get(i, ""))
		var state_key: String = "SKIN_USE_DEFAULT"
		if current == _skin_id and current != "":
			state_key = "SKIN_USE_THIS"
		elif current != "":
			state_key = "SKIN_USE_OTHER"
		_tiles[i].set_pressed_no_signal(current == _skin_id and current != "")
		_tiles[i].text = "%s\n%s" % [tr("SKIN_USE_PLAYER") % (i + 1), tr(state_key)]
		_tiles[i].tooltip_text = _tiles[i].text.replace("\n", ": ")


func _on_slot(slot: int) -> void:
	if SkinStore.assigned_id(slot) == _skin_id:
		SkinStore.unassign(slot)
	else:
		SkinStore.assign(slot, _skin_id)
	_refresh()
	changed.emit()
