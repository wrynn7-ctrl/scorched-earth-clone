class_name ShopScreen
extends Control
## One player's shop: money, WEAPONS / ITEMS tabs, an entry per catalog item, READY.
##
## Tablets (shortest side >= 520 dp) get a list with a detail pane next to it; phones get a grid
## of cards and open the detail as a popup. All rules come from the simulation: the screen
## asks `Simulation.validate_action` which buttons to dim and toasts the reason when a dimmed
## button is pressed; the real purchase goes through the `submit` callable.

signal ready_pressed
## A message for the shop toast (already translated).
signal message(text: String)

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const TABLET_MIN_DP: float = 520.0
const TAB_WEAPONS: int = 0
const TAB_ITEMS: int = 1

var _state: MatchState = null
var _submit: Callable = Callable()
var _player: int = 0
var _tab: int = TAB_WEAPONS
var _selected: String = ""
var _cards: Dictionary = {}
var _tablet: bool = false

var _margin: MarginContainer = null
var _root: VBoxContainer = null
var _header: HBoxContainer = null
var _emblem: EmblemIcon = null
var _title: Label = null
var _money: MoneyLabel = null
var _toolbar: HBoxContainer = null
var _tab_buttons: Array[Button] = []
var _ready_btn: Button = null
var _scroll: ScrollContainer = null
var _grid: GridContainer = null
var _list: VBoxContainer = null
var _body: HBoxContainer = null
var _detail: ShopDetail = null
var _detail_holder: VBoxContainer = null
var _popup: Control = null
var _popup_center: CenterContainer = null


func _init() -> void:
	theme = THEME
	name = "ShopScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(NeonPalette.BG_DEEP, 0.9)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_margin = MarginContainer.new()
	_margin.name = "Margin"
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_root = VBoxContainer.new()
	_root.name = "Root"
	_margin.add_child(_root)
	_build_header()
	_build_toolbar()
	_build_body()
	_build_popup()
	visible = false


func _build_header() -> void:
	_header = HBoxContainer.new()
	_header.name = "Header"
	_root.add_child(_header)
	_emblem = EmblemIcon.new()
	_emblem.name = "Emblem"
	_header.add_child(_emblem)
	_title = Label.new()
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.add_child(_title)
	_money = MoneyLabel.new()
	_money.set_font_dp(24.0)
	_header.add_child(_money)


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toolbar.name = "Toolbar"
	_root.add_child(_toolbar)
	var group := ButtonGroup.new()
	for i: int in range(2):
		var b := Button.new()
		b.name = "TabWeapons" if i == TAB_WEAPONS else "TabItems"
		b.text = tr("SHOP_TAB_WEAPONS") if i == TAB_WEAPONS else tr("SHOP_TAB_ITEMS")
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_tab.bind(i))
		_toolbar.add_child(b)
		_tab_buttons.append(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toolbar.add_child(spacer)
	_ready_btn = Button.new()
	_ready_btn.name = "Ready"
	_ready_btn.text = tr("SHOP_READY")
	_ready_btn.theme_type_variation = &"FireButton"
	_ready_btn.focus_mode = Control.FOCUS_NONE
	_ready_btn.pressed.connect(func() -> void: ready_pressed.emit())
	_toolbar.add_child(_ready_btn)


func _build_body() -> void:
	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(_body)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.name = "Grid"
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_holder = VBoxContainer.new()
	_detail_holder.name = "DetailHolder"
	_detail_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail = ShopDetail.new()
	_detail.buy_pressed.connect(_on_buy)
	_detail.sell_pressed.connect(_on_sell)
	_detail.close_pressed.connect(close_popup)


func _build_popup() -> void:
	_popup = Control.new()
	_popup.name = "DetailPopup"
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.visible = false
	add_child(_popup)
	var backdrop := Button.new()
	backdrop.name = "Backdrop"
	backdrop.flat = true
	backdrop.focus_mode = Control.FOCUS_NONE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NeonPalette.BG_DEEP, 0.7)
	for state_name: String in ["normal", "hover", "pressed"]:
		backdrop.add_theme_stylebox_override(state_name, sb)
	backdrop.pressed.connect(close_popup)
	_popup.add_child(backdrop)
	_popup_center = CenterContainer.new()
	_popup_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_popup.add_child(_popup_center)


func _ready() -> void:
	apply_scale()
	get_viewport().size_changed.connect(apply_scale)


## The grid, list and detail panes take turns in the tree; free whichever is parked outside.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for n: Node in [_grid, _list, _detail, _detail_holder]:
			if is_instance_valid(n) and n.get_parent() == null:
				n.free()


# ======================================================================================
# Layout
# ======================================================================================

## True when the visible area is tablet-sized (shortest side in dp).
func is_tablet_layout() -> bool:
	var vis: Vector2 = get_viewport_rect().size
	return UiScale.canvas_to_dp(minf(vis.x, vis.y)) >= TABLET_MIN_DP


func apply_scale() -> void:
	var ins: Vector4 = UiScale.safe_insets()
	var pad: float = UiScale.dp(10.0)
	_margin.add_theme_constant_override("margin_left", roundi(pad + ins.x))
	_margin.add_theme_constant_override("margin_top", roundi(pad + ins.y))
	_margin.add_theme_constant_override("margin_right", roundi(pad + ins.z))
	_margin.add_theme_constant_override("margin_bottom", roundi(pad + ins.w))
	_root.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_header.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_toolbar.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_body.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	_emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(32.0)
	_title.add_theme_font_size_override("font_size", UiScale.font(20.0))
	for b: Button in _tab_buttons:
		b.custom_minimum_size = Vector2(UiScale.dp(120.0), UiScale.touch())
		b.add_theme_font_size_override("font_size", UiScale.font(15.0))
	_ready_btn.custom_minimum_size = Vector2(UiScale.dp(140.0), UiScale.dp(56.0))
	_ready_btn.add_theme_font_size_override("font_size", UiScale.font(22.0))
	_money.apply_scale()
	_detail.apply_scale()
	var want_tablet: bool = is_tablet_layout()
	if want_tablet != _tablet or _cards.is_empty():
		_tablet = want_tablet
		_rebuild()
	else:
		_layout_cards()
		for c: ShopCard in _cards_in_order():
			c.apply_scale()


func _cards_in_order() -> Array[ShopCard]:
	var out: Array[ShopCard] = []
	for c: Variant in _cards.values():
		out.append(c as ShopCard)
	return out


## Rebuilds the body for the current layout mode and tab.
func _rebuild() -> void:
	_close_popup_silently()
	for node: Node in [_grid, _list, _detail, _detail_holder]:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
	for c: ShopCard in _cards_in_order():
		c.queue_free()
	_cards.clear()
	var holder: Container = _list if _tablet else _grid
	_scroll.add_child(holder)
	if _tablet:
		_detail_holder.custom_minimum_size.x = UiScale.dp(340.0)
		_detail.set_icon_dp(72.0)
		_detail.set_popup_mode(false)
		_body.add_child(_detail_holder)
		_detail_holder.add_child(_detail)
		_list.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	else:
		_detail.set_icon_dp(56.0)
		_detail.set_popup_mode(true)
		_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(8.0)))
		_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(8.0)))
	for id: String in ids_for_tab(_tab):
		var card := ShopCard.new()
		card.name = "Card_" + id
		card.setup(id, ShopCard.Mode.ROW if _tablet else ShopCard.Mode.GRID)
		card.pressed.connect(_on_card_pressed.bind(id))
		holder.add_child(card)
		_cards[id] = card
	_layout_cards()
	if _tablet and (_selected == "" or not _cards.has(_selected)) and not _cards.is_empty():
		_selected = ids_for_tab(_tab)[0]
	refresh()


func _layout_cards() -> void:
	if _tablet:
		return
	var vis_w: float = get_viewport_rect().size.x - UiScale.dp(20.0)
	var gap: float = UiScale.dp(8.0)
	_grid.columns = maxi(2, int(vis_w / (UiScale.dp(150.0) + gap)))


## Catalog ids shown on a tab, in catalog order (the unlimited Spark Dart is not for sale).
static func ids_for_tab(tab: int) -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		if tab == TAB_WEAPONS and WeaponDefs.has(id) and not WeaponDefs.get_def(id).get("unlimited", false):
			out.append(id)
		elif tab == TAB_ITEMS and ItemDefs.has(id):
			out.append(id)
	return out


# ======================================================================================
# Content
# ======================================================================================

## `submit` takes an action Dictionary and returns "" or an error key.
func setup(state: MatchState, submit: Callable) -> void:
	_state = state
	_submit = submit


func show_player(player: int, tab: int = TAB_WEAPONS, select_id: String = "") -> void:
	_player = player
	_emblem.set_index(player)
	_title.text = tr("SHOP_TITLE_FMT") % (player + 1)
	_title.add_theme_color_override("font_color", PlayerLooks.color(player))
	_selected = select_id
	visible = true
	_tab = tab
	_tab_buttons[tab].set_pressed_no_signal(true)
	_tab_buttons[1 - tab].set_pressed_no_signal(false)
	if is_inside_tree():
		_tablet = is_tablet_layout()
		_rebuild()
		if select_id != "" and not _tablet and _cards.has(select_id):
			open_popup(select_id)
	_money.set_amount(_state.tanks[_player].money)


func set_tab(tab: int) -> void:
	if tab == _tab and not _cards.is_empty():
		return
	_tab = tab
	_selected = ""
	_close_popup_silently()
	_tab_buttons[tab].set_pressed_no_signal(true)
	_tab_buttons[1 - tab].set_pressed_no_signal(false)
	_rebuild()


func get_tab() -> int:
	return _tab


func get_player() -> int:
	return _player


func get_selected() -> String:
	return _selected


## Re-reads money and stock from the state and restyles every card and the detail view.
func refresh() -> void:
	if _state == null:
		return
	var t: TankState = _state.tanks[_player]
	_money.set_amount(t.money)
	for id: String in _cards.keys():
		var card: ShopCard = _cards[id]
		card.set_info(price_text(id), t.stock_of(id), is_locked(id))
		card.set_selected(id == _selected)
	_refresh_detail()


func price_text(id: String) -> String:
	var def: Dictionary = Catalog.get_def(id)
	return tr("SHOP_PRICE_FMT") % [HudFormat.money(def["price"] as int), def["bundle"] as int]


func is_locked(id: String) -> bool:
	return Catalog.get_def(id)["tier"] == "full" and not _state.settings.full_unlocked


## The simulation's verdict on buying one bundle of `id` right now ("" = allowed).
func buy_error(id: String) -> String:
	return Simulation.validate_action(_state, _buy_action(id))


func sell_error(id: String) -> String:
	return Simulation.validate_action(_state, _sell_action(id))


func _buy_action(id: String) -> Dictionary:
	return {"kind": "buy", "tank": _player, "item": id, "qty": 1}


func _sell_action(id: String) -> Dictionary:
	return {"kind": "sell", "tank": _player, "item": id, "qty": 1}


func _refresh_detail() -> void:
	if _selected == "" or not Catalog.has(_selected):
		return
	var def: Dictionary = Catalog.get_def(_selected)
	var t: TankState = _state.tanks[_player]
	var b_err: String = buy_error(_selected)
	var s_err: String = sell_error(_selected)
	var refund: int = Economy.sell_refund(def, 1, t.stock_of(_selected))
	var reason: String = ""
	if b_err != "":
		reason = tr("ERR_" + b_err.to_upper())
	_detail.show_entry(_selected, price_text(_selected), t.stock_of(_selected), is_locked(_selected),
			tr("SHOP_BUY_FMT") % HudFormat.money(def["price"] as int),
			tr("SHOP_SELL_FMT") % HudFormat.money(refund),
			b_err != "", s_err != "", reason)


# ======================================================================================
# Interaction
# ======================================================================================

func select(id: String) -> void:
	if not _cards.has(id):
		return
	_selected = id
	refresh()


func _on_card_pressed(id: String) -> void:
	select(id)
	if not _tablet:
		open_popup(id)


func open_popup(id: String) -> void:
	if _tablet:
		return
	_selected = id
	refresh()
	if _detail.get_parent() != _popup_center:
		if _detail.get_parent() != null:
			_detail.get_parent().remove_child(_detail)
		_popup_center.add_child(_detail)
	_detail.custom_minimum_size.x = minf(UiScale.dp(420.0), get_viewport_rect().size.x * 0.92)
	_popup.visible = true


func close_popup() -> void:
	_popup.visible = false


func _close_popup_silently() -> void:
	if _popup != null:
		_popup.visible = false
	if _detail != null and _detail.get_parent() == _popup_center:
		_popup_center.remove_child(_detail)


func is_popup_open() -> bool:
	return _popup.visible


func _on_buy(id: String) -> void:
	var err: String = buy_error(id)
	if err == "":
		err = _submit.call(_buy_action(id))
	if err != "":
		message.emit(tr("ERR_" + err.to_upper()))
		return
	refresh()


func _on_sell(id: String) -> void:
	var err: String = sell_error(id)
	if err == "":
		err = _submit.call(_sell_action(id))
	if err != "":
		message.emit(tr("ERR_" + err.to_upper()))
		return
	refresh()


# --- accessors (tests, tools) ---

func get_card(id: String) -> ShopCard:
	return _cards.get(id) as ShopCard


func card_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in _cards.keys():
		out.append(id)
	return out


func get_detail() -> ShopDetail:
	return _detail


func get_money_label() -> MoneyLabel:
	return _money


func get_ready_button() -> Button:
	return _ready_btn


func get_tab_button(tab: int) -> Button:
	return _tab_buttons[tab]


func get_title_text() -> String:
	return _title.text


func get_popup() -> Control:
	return _popup


func get_scroll() -> ScrollContainer:
	return _scroll
