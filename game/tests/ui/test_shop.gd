extends GutTest
## The pass-and-play shop: hand-over screens, cards, BUY / SELL / READY, layouts.

# [window px, dpi, label, tablet layout expected]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone", false],
	[Vector2(2340, 1080), 535.0, "narrowest realistic", false],
	[Vector2(2560, 1080), 450.0, "21:9 phone", false],
	[Vector2(1280, 720), 240.0, "small 16:9", false],
	[Vector2(2048, 1536), 264.0, "4:3 tablet", true],
	[Vector2(2560, 1600), 280.0, "16:10 tablet", true],
]

var _state: MatchState = null
var _log: Array[Dictionary] = []


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	PlayerLooks.reset()


func _new_state(players: int = 3, full_unlocked: bool = true, money: int = 10000) -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = players
	m.rounds = 3
	m.seed = 99
	m.start_money = money
	m.full_unlocked = full_unlocked
	_state = Simulation.new_match(m)
	_log.clear()
	return _state


## The same thing the battle controller does: validate, log and apply.
func _submit(action: Dictionary) -> String:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(_state, a)
	if err == "":
		_log.append(a)
		Simulation.apply_action(_state, a)
	return err


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


func _flow(win: Vector2 = Vector2(2340, 1080), dpi: float = 500.0) -> ShopFlow:
	var vp: SubViewport = _viewport(win, dpi)
	var f := ShopFlow.new()
	vp.add_child(f)
	f.open(_state, _submit)
	return f


func test_three_player_shop_flow_buy_sell_ready_then_round_starts() -> void:
	_new_state(3)
	var f: ShopFlow = _flow()
	watch_signals(f)
	await wait_process_frames(2)
	# --- player 1 ---
	assert_true(f.is_showing_handover())
	assert_eq(f.get_handover().get_title_text(), "PLAYER 1 — YOUR SHOP")
	assert_false(f.is_showing_shop(), "others must not see the shop before the tap")
	f.get_handover().get_tap_button().pressed.emit()
	assert_true(f.is_showing_shop())
	var screen: ShopScreen = f.get_screen()
	assert_eq(screen.get_player(), 0)
	assert_eq(screen.get_title_text(), "PLAYER 1 — SHOP")
	assert_eq(screen.get_money_label().get_amount(), 10000)
	# BUY: a bundle of 5 Pulse Missiles for $1,500.
	screen.select("pulse_missile")
	var detail: ShopDetail = screen.get_detail()
	assert_false(detail.get_buy_button().is_blocked())
	assert_true(detail.get_sell_button().is_blocked(), "nothing to sell yet")
	detail.get_buy_button().pressed.emit()
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 5)
	assert_eq(_state.tanks[0].money, 8500)
	assert_eq(screen.get_money_label().get_amount(), 8500, "money readout follows")
	assert_eq(screen.get_card("pulse_missile").get_owned_text(), "OWNED 5")
	assert_false(detail.get_sell_button().is_blocked())
	# SELL: one unit refunds price / bundle / 2 = 150.
	detail.get_sell_button().pressed.emit()
	assert_eq(_state.tanks[0].stock_of("pulse_missile"), 4)
	assert_eq(_state.tanks[0].money, 8650)
	assert_eq(_log.size(), 2)
	assert_eq(_log[0]["kind"], "buy")
	assert_eq(_log[1]["kind"], "sell")
	screen.get_ready_button().pressed.emit()
	assert_true(_state.tanks[0].ready)
	# --- player 2 gets a hand-over of their own, and a fresh shop ---
	assert_true(f.is_showing_handover())
	assert_eq(f.get_handover().get_title_text(), "PLAYER 2 — YOUR SHOP")
	assert_false(f.is_showing_shop())
	f.get_handover().get_tap_button().pressed.emit()
	assert_eq(screen.get_player(), 1)
	assert_eq(screen.get_money_label().get_amount(), 10000, "each player has their own money")
	assert_eq(screen.get_card("pulse_missile").get_owned_text(), "OWNED 0")
	screen.select("glide_orb")
	detail.get_buy_button().pressed.emit()
	assert_eq(_state.tanks[1].stock_of("glide_orb"), 3)
	screen.get_ready_button().pressed.emit()
	assert_signal_not_emitted(f, "all_ready")
	# --- player 3 is last ---
	assert_eq(f.get_handover().get_title_text(), "PLAYER 3 — YOUR SHOP")
	f.get_handover().get_tap_button().pressed.emit()
	screen.get_ready_button().pressed.emit()
	assert_signal_emitted(f, "all_ready")
	assert_true(Simulation.all_ready(_state))
	assert_false(f.visible, "the flow closes itself")
	var events: Array[Dictionary] = Simulation.start_round(_state)
	assert_eq(events[0]["type"], "round_start")
	assert_eq(_state.phase, SimConstants.PHASE_AIM)


func test_flow_skips_players_who_are_already_ready() -> void:
	_new_state(3)
	_submit({"kind": "ready", "tank": 0})
	var f: ShopFlow = _flow()
	assert_eq(f.current_player(), 1, "a restored match continues with the first player who is not ready")
	assert_eq(f.get_handover().get_title_text(), "PLAYER 2 — YOUR SHOP")


func test_buttons_are_blocked_by_the_simulations_verdict_and_toast_the_reason() -> void:
	_new_state(2, true, 1200)
	var f: ShopFlow = _flow()
	f.get_handover().get_tap_button().pressed.emit()
	var screen: ShopScreen = f.get_screen()
	screen.select("pulse_missile")  # $1,500 > $1,200
	var detail: ShopDetail = screen.get_detail()
	assert_eq(screen.buy_error("pulse_missile"), "no_money")
	assert_true(detail.get_buy_button().is_blocked())
	assert_eq(detail.get_reason_text(), "Not enough credits", "the reason is text, not only a dimmed button")
	assert_false(detail.get_buy_button().disabled, "still pressable so it can explain itself")
	detail.get_buy_button().pressed.emit()
	assert_eq(f.get_toast().get_text(), "Not enough credits")
	assert_eq(_state.tanks[0].money, 1200, "nothing was bought")
	# Selling something you do not own.
	detail.get_sell_button().pressed.emit()
	assert_eq(f.get_toast().get_text(), "None left - pick another weapon")
	# What the simulation allows is enabled.
	_state.tanks[0].money = 100000
	screen.refresh()
	assert_false(detail.get_buy_button().is_blocked())
	assert_eq(detail.get_reason_text(), "")


func test_inventory_cap_blocks_buying() -> void:
	_new_state(2, true, 1000000)
	var f: ShopFlow = _flow()
	f.get_handover().get_tap_button().pressed.emit()
	var screen: ShopScreen = f.get_screen()
	screen.get_tab_button(ShopScreen.TAB_ITEMS).pressed.emit()
	screen.select("fuel_cell")  # 1 unit per bundle
	for _i: int in range(99):
		screen.get_detail().get_buy_button().pressed.emit()
	assert_eq(_state.tanks[0].stock_of("fuel_cell"), 99)
	assert_eq(screen.buy_error("fuel_cell"), "inventory_full")
	assert_eq(screen.get_detail().get_reason_text(), "You can't carry any more of these")


func test_locked_full_tier_entries_show_a_badge_and_cannot_be_bought() -> void:
	_new_state(2, false)
	var f: ShopFlow = _flow()
	f.get_handover().get_tap_button().pressed.emit()
	var screen: ShopScreen = f.get_screen()
	assert_true(screen.get_card("supernova").is_locked_badge_visible(), "FULL GAME badge on full-tier entries")
	assert_false(screen.get_card("pulse_missile").is_locked_badge_visible(), "free entries have none")
	screen.select("supernova")
	assert_true(screen.get_detail().is_locked_badge_visible())
	assert_eq(screen.buy_error("supernova"), "locked_item")
	assert_true(screen.get_detail().get_buy_button().is_blocked())
	screen.get_detail().get_buy_button().pressed.emit()
	assert_eq(f.get_toast().get_text(), "Part of the full game")
	assert_eq(_state.tanks[0].stock_of("supernova"), 0)
	# With the full game unlocked there is no badge at all.
	_new_state(2, true)
	var f2: ShopFlow = _flow()
	f2.get_handover().get_tap_button().pressed.emit()
	assert_false(f2.get_screen().get_card("supernova").is_locked_badge_visible())


func test_tabs_list_weapons_and_items_with_names_prices_and_descriptions() -> void:
	_new_state(2)
	var f: ShopFlow = _flow()
	f.get_handover().get_tap_button().pressed.emit()
	var screen: ShopScreen = f.get_screen()
	var weapons: Array[String] = screen.card_ids()
	assert_eq(weapons.size(), 20, "every weapon except the free, unlimited Spark Dart")
	assert_false(weapons.has("spark_dart"))
	var card: ShopCard = screen.get_card("pulse_missile")
	assert_eq(card.get_name_text(), "Pulse Missile")
	assert_eq(card.get_price_text(), "$1,500 / 5", "price per bundle")
	assert_eq(card.get_owned_text(), "OWNED 0")
	screen.get_tab_button(ShopScreen.TAB_ITEMS).pressed.emit()
	assert_eq(screen.get_tab(), ShopScreen.TAB_ITEMS)
	assert_eq(screen.card_ids().size(), 7)
	assert_not_null(screen.get_card("glow_shield"))
	assert_null(screen.get_card("pulse_missile"))
	# Every entry has a one-line description key and a glyph.
	for id: String in Catalog.IDS:
		if id == "spark_dart":
			continue
		assert_ne(tr("ITEM_" + id.to_upper() + "_DESC"), "ITEM_" + id.to_upper() + "_DESC", "%s has a description" % id)
		assert_ne(tr("ITEM_" + id.to_upper()), "ITEM_" + id.to_upper(), "%s has a name" % id)
	screen.select("glow_shield")
	assert_eq(screen.get_detail().get_desc_text(), "Absorbs 30 damage.")
	assert_eq(screen.get_detail().get_name_text(), "Glow Shield")


func test_layout_mode_phone_grid_with_popup_and_tablet_list_with_detail() -> void:
	_new_state(2)
	var phone: ShopFlow = _flow(Vector2(2340, 1080), 500.0)
	phone.get_handover().get_tap_button().pressed.emit()
	await wait_process_frames(2)
	assert_false(phone.get_screen().is_tablet_layout())
	var card: ShopCard = phone.get_screen().get_card("hyperpulse")
	assert_false(phone.get_screen().is_popup_open())
	card.pressed.emit()
	assert_true(phone.get_screen().is_popup_open(), "a phone card opens the detail popup")
	assert_true(phone.get_screen().get_detail().get_close_button().visible)
	phone.get_screen().get_detail().get_close_button().pressed.emit()
	assert_false(phone.get_screen().is_popup_open())
	var tablet: ShopFlow = _flow(Vector2(2048, 1536), 264.0)
	tablet.get_handover().get_tap_button().pressed.emit()
	await wait_process_frames(2)
	assert_true(tablet.get_screen().is_tablet_layout())
	tablet.get_screen().get_card("hyperpulse").pressed.emit()
	assert_false(tablet.get_screen().is_popup_open(), "a tablet shows the detail beside the list")
	assert_eq(tablet.get_screen().get_selected(), "hyperpulse")
	assert_true(tablet.get_screen().get_detail().is_visible_in_tree())
	assert_false(tablet.get_screen().get_detail().get_close_button().visible)


func _controls(root: Node, out: Array[Control]) -> void:
	for c: Node in root.get_children():
		if c is Control:
			out.append(c as Control)
		if not (c is ScrollContainer):
			_controls(c, out)


func test_shop_fits_every_screen_and_touch_targets_are_48dp() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			_new_state(8)
			var f: ShopFlow = _flow(case[0], float(case[1]))
			var vis: Vector2 = UiScale.visible_size(case[0])
			await wait_process_frames(2)
			# Hand-over.
			var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
			var hand: HandoverScreen = f.get_handover()
			for c: Control in [hand.get_node("Tap") as Control]:
				assert_true(rect.encloses(c.get_global_rect()), "%s: hand-over tap area" % label)
			var title: Control = hand.get_node_or_null("Title") as Control
			hand.get_tap_button().pressed.emit()
			await wait_process_frames(2)
			var screen: ShopScreen = f.get_screen()
			assert_eq(screen.is_tablet_layout(), case[3], label)
			for tab: int in [ShopScreen.TAB_WEAPONS, ShopScreen.TAB_ITEMS]:
				screen.get_tab_button(tab).pressed.emit()
				await wait_process_frames(2)
				var all: Array[Control] = []
				_controls(screen, all)
				for c: Control in all:
					if c.is_visible_in_tree() and not c.get_path().get_concatenated_names().contains("DetailPopup"):
						assert_true(rect.encloses(c.get_global_rect()), "%s tab %d: %s %s outside %s" % [label, tab, c.get_path(), c.get_global_rect(), vis])
					if c is BaseButton and c.is_visible_in_tree():
						var dp: float = UiScale.canvas_to_dp(minf(c.size.x, c.size.y))
						assert_gte(dp, 47.5, "%s: %s only %.1f dp" % [label, c.name, dp])
				assert_true(rect.encloses(screen.get_scroll().get_global_rect()), "%s: list on screen" % label)
				assert_gt(screen.get_scroll().size.y, UiScale.touch() * 1.5, "%s: the list has room" % label)
			# Detail: popup on phones, pane on tablets.
			screen.set_tab(ShopScreen.TAB_WEAPONS)
			await wait_process_frames(1)
			screen.get_card("singularity_seed").pressed.emit()
			await wait_process_frames(3)
			var detail: ShopDetail = screen.get_detail()
			assert_true(rect.encloses(detail.get_global_rect()), "%s: detail %s outside %s" % [label, detail.get_global_rect(), vis])
			for b: Button in [detail.get_buy_button(), detail.get_sell_button()]:
				assert_gte(UiScale.canvas_to_dp(minf(b.size.x, b.size.y)), 47.5, "%s: %s >= 48 dp" % [label, b.name])
			if not case[3]:
				assert_gte(UiScale.canvas_to_dp(detail.get_close_button().size.y), 47.5, "%s: CLOSE >= 48 dp" % label)
			f.get_parent().queue_free()
			await wait_process_frames(1)
