class_name ShopCard
extends Button
## One catalog entry in the shop: glyph, name, price per bundle, owned count, FULL GAME lock
## badge. Two looks: a vertical "grid" card (phones) and a wide "row" (tablets, with the
## one-line description). Tapping selects the entry; BUY/SELL live in the detail view.

enum Mode { GRID, ROW }

var item_id: String = ""

var _mode: Mode = Mode.GRID
var _root: Container = null
var _icon: ItemIcon = null
var _name: Label = null
var _desc: Label = null
var _price: Label = null
var _owned: Label = null
var _lock_row: HBoxContainer = null
var _lock_icon: Control = null
var _lock_label: Label = null
var _selected: bool = false


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_contents = true


func setup(id: String, mode: Mode) -> void:
	item_id = id
	_mode = mode
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build()


func _build() -> void:
	_root = HBoxContainer.new() if _mode == Mode.ROW else VBoxContainer.new()
	_root.name = "Content"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_icon = ItemIcon.new()
	_icon.name = "Icon"
	_icon.set_item(item_id)
	_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_name = _label("Name", NeonPalette.TEXT)
	_price = _label("Price", NeonPalette.WARN)
	_owned = _label("Owned", NeonPalette.CYAN)
	_lock_row = HBoxContainer.new()
	_lock_row.name = "LockBadge"
	_lock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_lock_icon = Control.new()
	_lock_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_icon.draw.connect(func() -> void:
		ItemIcon.draw_lock(_lock_icon, _lock_icon.size * 0.5, minf(_lock_icon.size.x, _lock_icon.size.y) * 0.45, NeonPalette.WARN))
	_lock_row.add_child(_lock_icon)
	_lock_label = _label("LockText", NeonPalette.WARN, _lock_row)
	_lock_label.text = tr("SHOP_FULL_GAME")
	_lock_row.visible = false
	if _mode == Mode.ROW:
		_root.add_child(_icon)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		_root.add_child(col)
		_name.reparent(col)
		_desc = _label("Desc", NeonPalette.TEXT_DIM, col)
		_desc.text = tr("ITEM_" + item_id.to_upper() + "_DESC")
		var right := VBoxContainer.new()
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.alignment = BoxContainer.ALIGNMENT_CENTER
		_root.add_child(right)
		_price.reparent(right)
		_owned.reparent(right)
		right.add_child(_lock_row)
		_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_owned.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		# Top to bottom: lock badge, glyph, name, price, owned.
		_root.add_child(_icon)
		_root.move_child(_icon, 0)
		_root.add_child(_lock_row)
		_root.move_child(_lock_row, 0)
	_name.text = tr("ITEM_" + item_id.to_upper())


func _label(label_name: String, color: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if _mode == Mode.GRID else HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_color_override("font_color", color)
	if parent != null:
		parent.add_child(l)
	elif _root != null:
		_root.add_child(l)
	return l


func _ready() -> void:
	apply_scale()


func apply_scale() -> void:
	var m: int = roundi(UiScale.dp(6.0))
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, m)
	_root.add_theme_constant_override("separation", roundi(UiScale.dp(8.0 if _mode == Mode.ROW else 2.0)))
	_name.add_theme_font_size_override("font_size", UiScale.font(13.0))
	_price.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_owned.add_theme_font_size_override("font_size", UiScale.font(12.0))
	_lock_label.add_theme_font_size_override("font_size", UiScale.font(10.0))
	_lock_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(14.0)
	if _desc != null:
		_desc.add_theme_font_size_override("font_size", UiScale.font(11.0))
	if _mode == Mode.GRID:
		_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(40.0)
		var h: float = UiScale.dp(40.0) + UiScale.line_h(13.0) + UiScale.line_h(12.0) * 2.0 + UiScale.dp(16.0) + float(m) * 2.0
		custom_minimum_size = Vector2(UiScale.dp(150.0), h)
	else:
		_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(40.0)
		var h: float = maxf(UiScale.touch() + UiScale.dp(12.0), UiScale.line_h(13.0) + UiScale.line_h(11.0) + float(m) * 2.0)
		custom_minimum_size = Vector2(UiScale.dp(260.0), h)


## price_text: e.g. "$1,500 / 5"; owned: units in stock; locked: full-tier entry while locked.
func set_info(price_text: String, owned: int, locked: bool) -> void:
	_price.text = price_text
	_owned.text = tr("SHOP_OWNED_FMT") % owned
	_lock_row.visible = locked
	_icon.set_dim(locked)


func set_selected(sel: bool) -> void:
	_selected = sel
	if sel:
		# A tinted fill with a bright border: the text stays readable (the stock pressed style is solid cyan).
		var sb: StyleBoxFlat = (get_theme_stylebox("normal", "Button") as StyleBoxFlat).duplicate()
		sb.bg_color = Color(NeonPalette.CYAN, 0.22)
		sb.border_color = Color.WHITE
		add_theme_stylebox_override("normal", sb)
		add_theme_stylebox_override("hover", sb)
	else:
		remove_theme_stylebox_override("normal")
		remove_theme_stylebox_override("hover")


func is_selected() -> bool:
	return _selected


func is_locked_badge_visible() -> bool:
	return _lock_row.visible


func get_price_text() -> String:
	return _price.text


func get_owned_text() -> String:
	return _owned.text


func get_name_text() -> String:
	return _name.text


func get_desc_text() -> String:
	return _desc.text if _desc != null else ""
