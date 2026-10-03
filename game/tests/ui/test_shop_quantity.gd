extends GutTest
## Shop quantity buttons: BUY x1 / x5 / MAX and SELL x1 / ALL. The max calculation and the actions each tap submits.
## Pulse Missile: $1,500 per bundle of 5. Fuel Cell: 1 unit per bundle.

var _state: MatchState = null
var _log: Array[Dictionary] = []


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	PlayerLooks.reset()


func _new_state(money: int, full: bool = true) -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = 2
	m.rounds = 3
	m.seed = 99
	m.start_money = money
	m.full_unlocked = full
	_state = Simulation.new_match(m)
	_log.clear()
	return _state


func _submit(action: Dictionary) -> String:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(_state, a)
	if err == "":
		_log.append(a)
		Simulation.apply_action(_state, a)
	return err


func _screen(tab: int = ShopScreen.TAB_WEAPONS, win: Vector2 = Vector2(2340, 1080), dpi: float = 500.0) -> ShopScreen:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	var f := ShopFlow.new()
	vp.add_child(f)
	f.open(_state, _submit, 0, true, tab)
	return f.get_screen()


# --- the max calculation ---------------------------------------------------------------------

func test_max_is_limited_by_money() -> void:
	_new_state(10000)
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 6, "10,000 / 1,500")
	_state.tanks[0].money = 1499
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 0, "cannot afford even one")
	_state.tanks[0].money = 1500
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 1)


func test_max_is_limited_by_the_99_cap_and_the_bundle_size() -> void:
	_new_state(1000000)
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 19, "19 bundles of 5 = 95 units, 99 cap")
	_state.tanks[0].inventory[Catalog.index_of("pulse_missile")] = 90
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 1, "room for 9 units = 1 bundle")
	_state.tanks[0].inventory[Catalog.index_of("pulse_missile")] = 96
	assert_eq(ShopQuantity.max_bundles(_state, 0, "pulse_missile"), 0, "3 units of room: not even one bundle")
	assert_eq(ShopQuantity.max_bundles(_state, 0, "fuel_cell"), 99, "1-unit bundles fill the cap")


func test_max_agrees_with_the_simulation_for_every_entry() -> void:
	_new_state(7777)
	for id: String in Catalog.IDS:
		var n: int = ShopQuantity.max_bundles(_state, 0, id)
		if n == 0:
			continue
		assert_eq(ShopQuantity.buy_error(_state, 0, id, n), "", "%s: max %d is legal" % [id, n])
		assert_ne(ShopQuantity.buy_error(_state, 0, id, n + 1), "", "%s: one more is refused" % id)


func test_max_is_zero_when_the_entry_cannot_be_bought() -> void:
	_new_state(1000000, false)
	for id: String in Catalog.IDS:
		if Catalog.get_def(id)["tier"] == "full":
			assert_eq(ShopQuantity.max_bundles(_state, 0, id), 0, "%s needs the full game" % id)
	assert_eq(ShopQuantity.max_bundles(_state, 0, "spark_dart"), 0, "the free starter is not for sale")


func test_actions_have_the_right_shape() -> void:
	assert_eq(ShopQuantity.buy_action(1, "glide_orb", 5), {"kind": "buy", "tank": 1, "item": "glide_orb", "qty": 5})
	assert_eq(ShopQuantity.sell_action(0, "glide_orb", 3), {"kind": "sell", "tank": 0, "item": "glide_orb", "qty": 3})


# --- the buttons ----------------------------------------------------------------------------

func test_x5_submits_one_buy_with_qty_5() -> void:
	_new_state(10000)
	var screen: ShopScreen = _screen()
	await wait_process_frames(2)
	screen.select("pulse_missile")
	screen.get_detail().get_buy5_button().pressed.emit()
	assert_eq(_log.size(), 1)
	assert_eq(_log[0], {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 5})
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 25)
	assert_eq(_state.tanks[0].money, 2500)
	assert_eq(screen.get_money_label().get_amount(), 2500)


func test_max_buys_everything_money_allows_then_blocks() -> void:
	_new_state(10000)
	var screen: ShopScreen = _screen()
	await wait_process_frames(2)
	screen.select("pulse_missile")
	var d: ShopDetail = screen.get_detail()
	assert_eq(d.get_buy_max_button().text, "MAX ×6  $9,000")
	d.get_buy_max_button().pressed.emit()
	assert_eq(_log[0]["qty"], 6)
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 30)
	assert_eq(_state.tanks[0].money, 1000)
	assert_true(d.get_buy_max_button().is_blocked(), "nothing more affordable")
	assert_true(d.get_buy5_button().is_blocked())
	assert_true(d.get_buy_button().is_blocked())
	assert_eq(d.get_reason_text(), "Not enough credits")
	var before: int = _log.size()
	d.get_buy_max_button().pressed.emit()
	assert_eq(_log.size(), before, "a blocked MAX submits nothing")


func test_x5_is_blocked_with_its_own_reason_when_only_x1_fits() -> void:
	_new_state(3000)  # two bundles, not five
	var screen: ShopScreen = _screen()
	await wait_process_frames(2)
	screen.select("pulse_missile")
	var d: ShopDetail = screen.get_detail()
	assert_false(d.get_buy_button().is_blocked())
	assert_true(d.get_buy5_button().is_blocked())
	assert_false(d.get_buy_max_button().is_blocked())
	assert_eq(d.get_reason_text(), "×5: Not enough credits", "the reason is text, not only a dimmed button")
	d.get_buy5_button().pressed.emit()
	assert_eq(_log.size(), 0)
	assert_eq(_state.tanks[0].money, 3000)


func test_sell_all_sells_everything_in_one_action() -> void:
	_new_state(10000)
	var screen: ShopScreen = _screen()
	await wait_process_frames(2)
	screen.select("pulse_missile")
	var d: ShopDetail = screen.get_detail()
	assert_true(d.get_sell_all_button().is_blocked(), "nothing to sell yet")
	d.get_buy5_button().pressed.emit()  # 25 units, $2,500 left
	var refund: int = Economy.sell_refund(Catalog.get_def("pulse_missile"), 25, 25)
	assert_eq(d.get_sell_all_button().text, "ALL ×25  +$%s" % HudFormat.money(refund).trim_prefix("$"))
	d.get_sell_all_button().pressed.emit()
	assert_eq(_log[1], {"kind": "sell", "tank": 0, "item": "pulse_missile", "qty": 25})
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 0)
	assert_eq(_state.tanks[0].money, 2500 + refund)
	assert_true(d.get_sell_all_button().is_blocked())
	d.get_sell_all_button().pressed.emit()
	assert_eq(_log.size(), 2, "ALL with nothing owned submits nothing")


func test_sell_x1_still_sells_one() -> void:
	_new_state(10000)
	var screen: ShopScreen = _screen()
	await wait_process_frames(2)
	screen.select("pulse_missile")
	var d: ShopDetail = screen.get_detail()
	d.get_buy_button().pressed.emit()
	d.get_sell_button().pressed.emit()
	assert_eq(_log[1]["qty"], 1)
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 4)


func test_locked_entries_send_x5_and_max_to_the_unlock_screen() -> void:
	_new_state(1000000, false)
	var screen: ShopScreen = _screen()
	watch_signals(screen)
	await wait_process_frames(2)
	var locked: String = ""
	for id: String in ShopScreen.ids_for_tab(ShopScreen.TAB_WEAPONS):
		if screen.is_locked(id):
			locked = id
			break
	assert_ne(locked, "")
	screen.select(locked)
	screen.get_detail().get_buy_max_button().pressed.emit()
	assert_signal_emitted(screen, "locked_tapped")
	assert_eq(_log.size(), 0)


func test_quantity_buttons_are_48dp_and_fit_the_phone_popup() -> void:
	_new_state(10000)
	var screen: ShopScreen = _screen(ShopScreen.TAB_WEAPONS, Vector2(2340, 1080), 535.0)
	await wait_process_frames(2)
	screen.get_card("pulse_missile").pressed.emit()
	await wait_process_frames(3)
	var d: ShopDetail = screen.get_detail()
	for b: Button in [d.get_buy_button(), d.get_buy5_button(), d.get_buy_max_button(), d.get_sell_button(), d.get_sell_all_button()]:
		assert_gte(UiScale.canvas_to_dp(b.size.y), 47.5, "%s tall enough" % b.name)
		assert_gte(UiScale.canvas_to_dp(b.size.x), 47.5, "%s wide enough" % b.name)
