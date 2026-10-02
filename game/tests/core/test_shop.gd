extends GutTest
## Buy / sell / ready (docs/ARCHITECTURE.md sections 17-19).

const U = preload("res://tests/core/sim_test_util.gd")


func test_buy_happy_path() -> void:
	var s: MatchState = U.shop_state(2)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.buy(0, "pulse_missile", 2))
	var t: TankState = s.tanks[0]
	assert_eq(t.money, SimConstants.DEFAULT_START_MONEY - 3000)
	assert_eq(t.stock_of("pulse_missile"), 10, "2 bundles of 5")
	assert_eq(ev.size(), 1)
	assert_eq(ev[0], {"type": "money", "tick": 0, "tank": 0, "delta": -3000, "money": 7000, "reason": "buy"})
	assert_eq(s.tanks[1].money, SimConstants.DEFAULT_START_MONEY, "other tanks untouched")
	assert_eq(s.tanks[1].stock_of("pulse_missile"), 0)


func test_buy_every_free_item_exactly_to_zero_money() -> void:
	var s: MatchState = U.shop_state(2)
	s.tanks[0].money = 1500
	assert_eq(Simulation.validate_action(s, U.buy(0, "pulse_missile", 1)), "")
	Simulation.apply_action(s, U.buy(0, "pulse_missile", 1))
	assert_eq(s.tanks[0].money, 0)
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", 1)), "no_money")


func test_bundle_sizes() -> void:
	var s: MatchState = U.shop_state(2)
	s.tanks[0].money = 1_000_000
	Simulation.apply_action(s, U.buy(0, "hyperpulse", 1))
	Simulation.apply_action(s, U.buy(0, "drift_chute", 3))
	Simulation.apply_action(s, U.buy(0, "nova_core", 4))
	assert_eq(s.tanks[0].stock_of("hyperpulse"), 3)
	assert_eq(s.tanks[0].stock_of("drift_chute"), 6)
	assert_eq(s.tanks[0].stock_of("nova_core"), 4)
	assert_eq(s.tanks[0].money, 1_000_000 - 2500 - 4500 - 24000)


func test_buy_error_keys() -> void:
	var s: MatchState = U.shop_state(2)
	s.settings.full_unlocked = false
	assert_eq(Simulation.validate_action(s, U.buy(0, "nope", 1)), "unknown_item")
	assert_eq(Simulation.validate_action(s, U.buy(0, "spark_dart", 1)), "not_buyable")
	assert_eq(Simulation.validate_action(s, U.buy(0, "supernova", 1)), "locked_item")
	assert_eq(Simulation.validate_action(s, U.buy(0, "nova_core", 2)), "no_money")
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", 0)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", -2)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.buy(5, "fuel_cell", 1)), "bad_tank")
	assert_eq(Simulation.validate_action(s, U.buy(-1, "fuel_cell", 1)), "bad_tank")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell"}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "qty": 1}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 1.0}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": 5, "qty": 1}), "bad_field")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0.0, "item": "fuel_cell", "qty": 1}), "bad_field")
	# weapons given as items to use_item etc. are separate; but a weapon can be bought
	assert_eq(Simulation.validate_action(s, U.buy(0, "pulse_missile", 1)), "")


func test_rejected_buys_change_nothing() -> void:
	var s: MatchState = U.shop_state(2)
	s.settings.full_unlocked = false
	var before: String = Simulation.fingerprint(s)
	for a: Dictionary in [U.buy(0, "supernova"), U.buy(0, "spark_dart"), U.buy(0, "nope"), U.buy(0, "nova_core", 5),
			U.buy(0, "fuel_cell", 0), U.buy(0, "fuel_cell", 100)]:
		assert_ne(Simulation.validate_action(s, a), "", str(a))
		assert_eq(Simulation.apply_action(s, a).size(), 0)
		assert_eq(Simulation.fingerprint(s), before)


func test_full_tier_is_locked_until_unlocked() -> void:
	var s: MatchState = U.shop_state(2)
	s.tanks[0].money = 1_000_000
	var full_ids: Array[String] = []
	var free_ids: Array[String] = []
	for id: String in Catalog.IDS:
		if id == "spark_dart":
			continue
		if Catalog.get_def(id)["tier"] == "full":
			full_ids.append(id)
		else:
			free_ids.append(id)
	assert_eq(full_ids.size(), 13)
	assert_eq(free_ids.size(), 14)
	s.settings.full_unlocked = false
	for id: String in full_ids:
		assert_eq(Simulation.validate_action(s, U.buy(0, id, 1)), "locked_item", id)
	for id: String in free_ids:
		assert_eq(Simulation.validate_action(s, U.buy(0, id, 1)), "", id)
	s.settings.full_unlocked = true
	for id: String in full_ids:
		assert_eq(Simulation.validate_action(s, U.buy(0, id, 1)), "", id)


func test_locked_check_precedes_money_check() -> void:
	var s: MatchState = U.shop_state(2)
	s.settings.full_unlocked = false
	s.tanks[0].money = 0
	assert_eq(Simulation.validate_action(s, U.buy(0, "supernova", 1)), "locked_item")


func test_inventory_cap_is_99_units() -> void:
	var s: MatchState = U.shop_state(2)
	var t: TankState = s.tanks[0]
	t.money = 10_000_000
	t.set_stock("pulse_missile", 94)
	assert_eq(Simulation.validate_action(s, U.buy(0, "pulse_missile", 1)), "", "94 + 5 = 99 fits")
	Simulation.apply_action(s, U.buy(0, "pulse_missile", 1))
	assert_eq(t.stock_of("pulse_missile"), 99)
	assert_eq(Simulation.validate_action(s, U.buy(0, "pulse_missile", 1)), "inventory_full")
	t.set_stock("pulse_missile", 95)
	assert_eq(Simulation.validate_action(s, U.buy(0, "pulse_missile", 1)), "inventory_full", "95 + 5 = 100 does not fit")
	t.set_stock("fuel_cell", 98)
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", 1)), "")
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", 2)), "inventory_full")
	assert_eq(Simulation.validate_action(s, U.buy(0, "nova_core", 100)), "inventory_full")
	assert_eq(Simulation.validate_action(s, U.buy(0, "nova_core", 1 << 40)), "inventory_full", "huge qty")
	assert_eq(Simulation.validate_action(s, U.buy(0, "nova_core", 99)), "")


func test_inventory_full_is_checked_before_money() -> void:
	var s: MatchState = U.shop_state(2)
	s.tanks[0].money = 0
	s.tanks[0].set_stock("fuel_cell", 99)
	assert_eq(Simulation.validate_action(s, U.buy(0, "fuel_cell", 1)), "inventory_full")


func test_sell_refund_math() -> void:
	var s: MatchState = U.shop_state(2)
	var t: TankState = s.tanks[0]
	t.money = 0
	t.set_stock("pulse_missile", 5)
	t.set_stock("hyperpulse", 3)
	t.set_stock("drift_chute", 3)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.sell(0, "pulse_missile", 3))
	assert_eq(t.money, 450, "1500 * 3 / 5 / 2")
	assert_eq(t.stock_of("pulse_missile"), 2)
	assert_eq(ev[0], {"type": "money", "tick": 0, "tank": 0, "delta": 450, "money": 450, "reason": "sell"})
	Simulation.apply_action(s, U.sell(0, "pulse_missile", 1))
	assert_eq(t.money, 450 + 150, "1500 * 1 / 5 / 2")
	Simulation.apply_action(s, U.sell(0, "hyperpulse", 1))
	assert_eq(t.money, 600 + 416, "2500 / 3 = 833, / 2 = 416 (integer division)")
	t.money = 0
	Simulation.apply_action(s, U.sell(0, "drift_chute", 3))
	assert_eq(t.money, 1500 * 3 / 2 / 2, "1500 * 3 / 2 = 2250, / 2 = 1125")
	assert_eq(t.stock_of("drift_chute"), 0)


func test_sell_more_than_owned_sells_what_is_owned() -> void:
	var s: MatchState = U.shop_state(2)
	var t: TankState = s.tanks[0]
	t.money = 0
	t.set_stock("pulse_missile", 2)
	Simulation.apply_action(s, U.sell(0, "pulse_missile", 50))
	assert_eq(t.stock_of("pulse_missile"), 0)
	assert_eq(t.money, 300, "2 units * 300")


func test_sell_whole_bundle_refund_is_half_the_price() -> void:
	for id: String in Catalog.IDS:
		if id == "spark_dart":
			continue
		var def: Dictionary = Catalog.get_def(id)
		var bundle: int = def["bundle"]
		assert_eq(Economy.sell_refund(def, bundle, bundle), (def["price"] as int) / 2, id)


func test_sell_errors() -> void:
	var s: MatchState = U.shop_state(2)
	assert_eq(Simulation.validate_action(s, U.sell(0, "pulse_missile", 1)), "out_of_stock")
	assert_eq(Simulation.validate_action(s, U.sell(0, "spark_dart", 1)), "out_of_stock")
	assert_eq(Simulation.validate_action(s, U.sell(0, "nope", 1)), "unknown_item")
	s.tanks[0].set_stock("pulse_missile", 1)
	assert_eq(Simulation.validate_action(s, U.sell(0, "pulse_missile", 0)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.sell(0, "pulse_missile", -1)), "bad_field")
	assert_eq(Simulation.validate_action(s, U.sell(9, "pulse_missile", 1)), "bad_tank")
	assert_eq(Simulation.validate_action(s, U.sell(0, "pulse_missile", 1)), "")
	assert_eq(Simulation.validate_action(s, {"kind": "sell", "tank": 0, "item": "pulse_missile"}), "bad_field")


func test_buy_then_sell_loses_half() -> void:
	var s: MatchState = U.shop_state(2)
	Simulation.apply_action(s, U.buy(0, "nova_core", 1))
	Simulation.apply_action(s, U.sell(0, "nova_core", 1))
	assert_eq(s.tanks[0].money, SimConstants.DEFAULT_START_MONEY - 3000)


func test_ready_and_already_ready() -> void:
	var s: MatchState = U.shop_state(2)
	assert_eq(Simulation.validate_action(s, U.ready(0)), "")
	Simulation.apply_action(s, U.ready(0))
	assert_true(s.tanks[0].ready)
	assert_eq(Simulation.validate_action(s, U.ready(0)), "already_ready")
	assert_eq(Simulation.apply_action(s, U.ready(0)).size(), 0)
	assert_eq(Simulation.validate_action(s, U.ready(7)), "bad_tank")
	assert_eq(Simulation.validate_action(s, {"kind": "ready"}), "bad_field")


func test_shopping_in_any_order_after_others_are_ready() -> void:
	var s: MatchState = U.shop_state(2)
	Simulation.apply_action(s, U.ready(0))
	Simulation.apply_action(s, U.buy(0, "fuel_cell", 1))
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 1, "buying after ready is allowed")
	Simulation.apply_action(s, U.ready(1))
	Simulation.apply_action(s, U.sell(0, "fuel_cell", 1))
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 0)
	assert_eq(Simulation.start_round(s).size(), 3)


func test_catalog_index_stock_through_inventory_array() -> void:
	var s: MatchState = U.shop_state(2)
	s.tanks[0].money = 1_000_000
	for id: String in Catalog.IDS:
		if id == "spark_dart":
			continue
		Simulation.apply_action(s, U.buy(0, id, 1))
		assert_eq(s.tanks[0].inventory[Catalog.index_of(id)], Catalog.get_def(id)["bundle"], id)
	assert_eq(s.tanks[0].inventory[0], 0)
