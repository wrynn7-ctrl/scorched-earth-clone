class_name WeaponPopup
extends Control
## Modal list of the weapons the current player owns (opened from the HUD weapon button).
## A dimmed backdrop closes it when tapped; choosing a row emits `chosen(item_id)`.

signal chosen(item_id: String)
signal closed

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _dim: Button = null
var _center: CenterContainer = null
var _panel: PanelContainer = null
var _margin: MarginContainer = null
var _box: VBoxContainer = null
var _title: Label = null
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _chips: Array[HudChip] = []
var _entries: Array[Dictionary] = []
var _selected: String = ""


func _init() -> void:
	theme = THEME
	name = "WeaponPopup"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = Button.new()
	_dim.name = "Backdrop"
	_dim.flat = true
	_dim.focus_mode = Control.FOCUS_NONE
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.add_theme_stylebox_override("normal", _flat(Color(NeonPalette.BG_DEEP, 0.55)))
	_dim.add_theme_stylebox_override("hover", _flat(Color(NeonPalette.BG_DEEP, 0.55)))
	_dim.add_theme_stylebox_override("pressed", _flat(Color(NeonPalette.BG_DEEP, 0.55)))
	_dim.pressed.connect(close)
	add_child(_dim)
	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_center.add_child(_panel)
	_margin = MarginContainer.new()
	_panel.add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)
	_title = Label.new()
	_title.text = tr("HUD_PICK_WEAPON")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", NeonPalette.CYAN)
	_box.add_child(_title)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	return s


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale, true)


func apply_scale() -> void:
	LayoutGuard.fit(self)
	var pad: int = roundi(UiScale.dp(12.0))
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_title.add_theme_font_size_override("font_size", UiScale.font(16.0))
	var gap: int = roundi(UiScale.dp(8.0))
	_grid.add_theme_constant_override("h_separation", gap)
	_grid.add_theme_constant_override("v_separation", gap)
	var vis: Vector2 = get_viewport_rect().size
	var cols: int = 2 if vis.x < UiScale.dp(900.0) else 3
	_grid.columns = cols
	for c: HudChip in _chips:
		c.apply_scale()
	var chip_h: float = _chips[0].custom_minimum_size.y if not _chips.is_empty() else UiScale.touch()
	var rows: int = int(ceil(float(_chips.size()) / float(cols)))
	var content_h: float = float(rows) * (chip_h + float(gap))
	var max_h: float = vis.y * 0.9 - UiScale.line_h(16.0) - float(pad) * 2.0 - UiScale.dp(8.0)
	_scroll.custom_minimum_size = Vector2(0.0, minf(content_h, max_h))


## entries: [{id, count}] (count < 0 = unlimited). `selected` is highlighted.
func open(entries: Array[Dictionary], selected: String) -> void:
	_entries = entries
	_selected = selected
	for c: HudChip in _chips:
		_grid.remove_child(c)
		c.queue_free()
	_chips.clear()
	for e: Dictionary in entries:
		var id: String = e["id"]
		var chip := HudChip.new()
		chip.name = "Pick_" + id
		chip.configure(190.0, 13.0, 12.0)
		chip.set_entry(id, tr("ITEM_" + id.to_upper()), HudChip.count_text(e["count"] as int))
		chip.toggle_mode = false
		if id == selected:
			chip.add_theme_stylebox_override("normal", chip.get_theme_stylebox("pressed", "Button"))
		chip.pressed.connect(_on_pick.bind(id))
		_grid.add_child(chip)
		_chips.append(chip)
	visible = true
	if is_inside_tree():
		apply_scale()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func get_chips() -> Array[HudChip]:
	return _chips


func get_panel() -> Control:
	return _panel


func get_chip(id: String) -> HudChip:
	for c: HudChip in _chips:
		if c.get_item() == id:
			return c
	return null


func _on_pick(id: String) -> void:
	visible = false
	chosen.emit(id)
	closed.emit()
