class_name ShopDetail
extends PanelContainer
## The selected shop entry in full: big glyph, name, price per bundle, owned count, one-line
## description, why it can't be bought (if so), BUY and SELL. A side pane on tablets, a popup
## on phones (where it also has a CLOSE button).

signal buy_pressed(item_id: String)
signal sell_pressed(item_id: String)
signal close_pressed

const NEON_THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var item_id: String = ""

var _margin: MarginContainer = null
var _box: VBoxContainer = null
var _icon: ItemIcon = null
var _name: Label = null
var _price: Label = null
var _owned: Label = null
var _lock_row: HBoxContainer = null
var _lock_icon: Control = null
var _lock_label: Label = null
var _desc: Label = null
var _reason: Label = null
var _buy: ShopButton = null
var _sell: ShopButton = null
var _close: Button = null
var _icon_dp: float = 56.0


func _init() -> void:
	name = "ShopDetail"
	_margin = MarginContainer.new()
	add_child(_margin)
	_box = VBoxContainer.new()
	_margin.add_child(_box)
	var head := HBoxContainer.new()
	head.name = "Head"
	_box.add_child(head)
	_icon = ItemIcon.new()
	_icon.name = "Icon"
	head.add_child(_icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(col)
	_name = _label(col, "Name", NeonPalette.CYAN)
	_price = _label(col, "Price", NeonPalette.WARN)
	_owned = _label(col, "Owned", NeonPalette.TEXT)
	_lock_row = HBoxContainer.new()
	_lock_row.name = "LockBadge"
	_lock_icon = Control.new()
	_lock_icon.draw.connect(func() -> void:
		ItemIcon.draw_lock(_lock_icon, _lock_icon.size * 0.5, minf(_lock_icon.size.x, _lock_icon.size.y) * 0.45, NeonPalette.WARN))
	_lock_row.add_child(_lock_icon)
	_lock_label = _label(_lock_row, "LockText", NeonPalette.WARN)
	_lock_label.text = tr("SHOP_FULL_GAME")
	col.add_child(_lock_row)
	_lock_row.visible = false
	_desc = _label(_box, "Desc", NeonPalette.TEXT)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason = _label(_box, "Reason", NeonPalette.WARN)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	_box.add_child(buttons)
	_buy = _button(buttons, "Buy")
	_buy.pressed.connect(func() -> void: buy_pressed.emit(item_id))
	_sell = _button(buttons, "Sell")
	_sell.pressed.connect(func() -> void: sell_pressed.emit(item_id))
	_close = Button.new()
	_close.name = "Close"
	_close.text = tr("SHOP_CLOSE")
	_close.focus_mode = Control.FOCUS_NONE
	_close.visible = false
	_close.pressed.connect(func() -> void: close_pressed.emit())
	buttons.add_child(_close)


func _label(parent: Node, label_name: String, color: Color) -> Label:
	var l := Label.new()
	l.name = label_name
	l.add_theme_color_override("font_color", color)
	l.clip_text = false
	parent.add_child(l)
	return l


func _button(parent: Node, button_name: String) -> ShopButton:
	var b := ShopButton.new()
	b.name = button_name
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b


func _ready() -> void:
	apply_scale()


func apply_scale() -> void:
	var pad: int = roundi(UiScale.dp(10.0))
	for side: String in ["left", "top", "right", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(_icon_dp)
	_name.add_theme_font_size_override("font_size", UiScale.font(18.0))
	_price.add_theme_font_size_override("font_size", UiScale.font(13.0))
	_owned.add_theme_font_size_override("font_size", UiScale.font(13.0))
	_lock_label.add_theme_font_size_override("font_size", UiScale.font(11.0))
	_lock_icon.custom_minimum_size = Vector2.ONE * UiScale.dp(16.0)
	_desc.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_reason.add_theme_font_size_override("font_size", UiScale.font(12.0))
	for b: Button in [_buy, _sell, _close]:
		b.custom_minimum_size = Vector2(UiScale.dp(110.0), UiScale.touch())
		b.add_theme_font_size_override("font_size", UiScale.font(14.0))
	(_buy.get_parent() as HBoxContainer).add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))


func set_icon_dp(size_dp: float) -> void:
	_icon_dp = size_dp
	apply_scale()


func set_popup_mode(on: bool) -> void:
	_close.visible = on
	if on:
		# The popup floats over the card grid: make it opaque so the cards do not bleed through.
		# Read the neon theme directly: the detail is not in the tree yet when this runs, so
		# get_theme_stylebox() would fall back to the engine's border-less default panel.
		var sb: StyleBoxFlat = (NEON_THEME.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).duplicate()
		sb.bg_color = Color(NeonPalette.BG_MID, 1.0)
		sb.border_color = Color(NeonPalette.CYAN, 0.9)
		sb.shadow_color = Color(NeonPalette.CYAN, 0.3)
		add_theme_stylebox_override("panel", sb)
	else:
		remove_theme_stylebox_override("panel")


## Fills in the entry. Texts are already translated; `*_blocked` styles the buttons as
## unavailable (they still answer a press with a toast).
func show_entry(id: String, price_text: String, owned: int, locked: bool, buy_text: String, sell_text: String,
		buy_blocked: bool, sell_blocked: bool, reason: String) -> void:
	item_id = id
	_icon.set_item(id)
	_icon.set_dim(locked)
	_name.text = tr("ITEM_" + id.to_upper())
	_price.text = tr("SHOP_PRICE_LABEL") % price_text
	_owned.text = tr("SHOP_OWNED_LABEL") % owned
	_lock_row.visible = locked
	_desc.text = tr("ITEM_" + id.to_upper() + "_DESC")
	_reason.text = reason
	_reason.visible = reason != ""
	_buy.text = buy_text
	_sell.text = sell_text
	_buy.set_blocked(buy_blocked)
	_sell.set_blocked(sell_blocked)


func get_buy_button() -> ShopButton:
	return _buy


func get_sell_button() -> ShopButton:
	return _sell


func get_close_button() -> Button:
	return _close


func get_reason_text() -> String:
	return _reason.text


func get_name_text() -> String:
	return _name.text


func get_desc_text() -> String:
	return _desc.text


func get_owned_text() -> String:
	return _owned.text


func get_price_text() -> String:
	return _price.text


func is_locked_badge_visible() -> bool:
	return _lock_row.visible
