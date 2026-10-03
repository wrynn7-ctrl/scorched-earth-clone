@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: the shop quantity buttons (ShopQuantity, docs/ARCHITECTURE.md section 17-19). For random
## money / stock states: MAX equals the largest quantity `Simulation.validate_action` accepts (found by
## brute force), the accepted quantities form a prefix 1..MAX, x5 is blocked exactly when 5 bundles are not
## affordable or would pass the 99-unit cap (or the item is locked / not buyable), and SELL ALL pays what the
## simulation pays.

const QaUtil = preload("res://tests/qa/qa_util.gd")

const STATES: int = 600
const BRUTE_MAX_QTY: int = 130


func _buyable_ids(full: bool) -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		var def: Dictionary = Catalog.get_def(id)
		if def.get("unlimited", false):
			continue
		if def["tier"] == "full" and not full:
			continue
		out.append(id)
	return out


func _shop_state(full: bool, seed_value: int) -> MatchState:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = 3
	s.rounds = 3
	s.full_unlocked = full
	return Simulation.new_match(s)


## Largest q in 1..BRUTE_MAX_QTY the simulation accepts, 0 if none; also reports prefix-ness.
func _brute_max(state: MatchState, tank: int, item: String) -> Dictionary:
	var best: int = 0
	var first_refused: int = -1
	var accepted_after_refusal: bool = false
	for q: int in range(1, BRUTE_MAX_QTY + 1):
		var err: String = Simulation.validate_action(state, ShopQuantity.buy_action(tank, item, q))
		if err == "":
			best = q
			if first_refused >= 0:
				accepted_after_refusal = true
		elif first_refused < 0:
			first_refused = q
	return {"max": best, "gap": accepted_after_refusal}


## Independent oracle for "BUY x5 is possible".
func _x5_expected(state: MatchState, tank: int, item: String) -> bool:
	var def: Dictionary = Catalog.get_def(item)
	if def.get("unlimited", false):
		return false
	if def["tier"] == "full" and not state.settings.full_unlocked:
		return false
	var t: TankState = state.tanks[tank]
	var units: int = 5 * (def["bundle"] as int)
	var cost: int = 5 * (def["price"] as int)
	return t.stock_of(item) + units <= SimConstants.INVENTORY_CAP and cost <= t.money


func test_max_equals_the_largest_accepted_quantity_for_random_states() -> void:
	var rng: Rng = Rng.derive(7071, 1)
	var bad: Array[String] = []
	var maxes: Dictionary = {}
	var x5_on: int = 0
	var x5_off: int = 0
	for n: int in range(STATES):
		var full: bool = n % 3 != 0
		var state: MatchState = _shop_state(full, n)
		var ids: Array[String] = _buyable_ids(true)  # includes locked ones for free states on purpose
		var item: String = ids[rng.range_int(0, ids.size() - 1)]
		var tank: int = rng.range_int(0, 2)
		var t: TankState = state.tanks[tank]
		var def: Dictionary = Catalog.get_def(item)
		var price: int = def["price"]
		var bundle: int = def["bundle"]
		# Money: random, or hugging a multiple of the price (the off-by-one zone), or extreme.
		match rng.range_int(0, 5):
			0:
				t.money = rng.range_int(0, 200000)
			1:
				t.money = price * rng.range_int(0, 120) + rng.range_int(-1, 1)
			2:
				t.money = 0
			3:
				t.money = 1_000_000
			4:
				t.money = price * 5 + rng.range_int(-1, 0)
			_:
				t.money = price * rng.range_int(0, 20)
		t.money = maxi(0, t.money)
		# Stock: random, or hugging the cap for this bundle size.
		match rng.range_int(0, 4):
			0:
				t.set_stock(item, rng.range_int(0, 99))
			1:
				t.set_stock(item, clampi(99 - 5 * bundle + rng.range_int(-1, 1), 0, 99))
			2:
				t.set_stock(item, 99 - rng.range_int(0, bundle + 1))
			3:
				t.set_stock(item, 0)
			_:
				t.set_stock(item, 99)
		t.set_stock(item, clampi(t.stock_of(item), 0, 99))
		var tag: String = "state %d (%s, full %s, money %d, stock %d, price %d, bundle %d, tank %d)" % [n, item, str(full),
				t.money, t.stock_of(item), price, bundle, tank]
		var brute: Dictionary = _brute_max(state, tank, item)
		var got: int = ShopQuantity.max_bundles(state, tank, item)
		maxes[brute["max"]] = true
		if got != brute["max"]:
			bad.append("%s: max_bundles %d != brute force %d" % [tag, got, brute["max"]])
		if brute["gap"]:
			bad.append("%s: accepted quantities are not a prefix 1..MAX" % tag)
		# x5.
		var e5: String = ShopQuantity.buy_error(state, tank, item, ShopQuantity.BUY_X5)
		var want5: bool = _x5_expected(state, tank, item)
		if (e5 == "") != want5:
			bad.append("%s: x5 error '%s' but oracle says possible=%s" % [tag, e5, str(want5)])
		if want5:
			x5_on += 1
		else:
			x5_off += 1
		if (e5 == "") != (got >= 5):
			bad.append("%s: x5 possible=%s but MAX=%d" % [tag, str(e5 == ""), got])
		# Applying MAX is legal and lands inside the limits; one more bundle is refused.
		if got >= 1:
			var before_money: int = t.money
			var before_stock: int = t.stock_of(item)
			var ev: Array[Dictionary] = Simulation.apply_action(state, ShopQuantity.buy_action(tank, item, got))
			if ev.is_empty():
				bad.append("%s: MAX purchase of %d was refused when applied" % [tag, got])
			elif t.stock_of(item) > SimConstants.INVENTORY_CAP or t.money < 0 \
					or before_money - t.money != Economy.buy_cost(def, got) \
					or t.stock_of(item) - before_stock != Economy.buy_units(def, got):
				bad.append("%s: MAX purchase left stock %d money %d" % [tag, t.stock_of(item), t.money])
			if Simulation.validate_action(state, ShopQuantity.buy_action(tank, item, 1)) == "" and got >= 99:
				bad.append("%s: still room after MAX at the cap" % tag)
		if bad.size() > 12:
			break
	gut.p("SHOP QTY  %d states, x5 enabled %d / disabled %d, distinct MAX values %d" % [STATES, x5_on, x5_off, maxes.size()])
	assert_eq(bad.size(), 0, "ShopQuantity disagrees with the simulation:\n  " + "\n  ".join(bad.slice(0, 12)))
	assert_gt(x5_on, 40, "enough states where x5 is allowed")
	assert_gt(x5_off, 40, "enough states where x5 is blocked")
	assert_gt(maxes.size(), 6, "MAX took many different values")


func test_x5_is_blocked_with_the_right_reason() -> void:
	var state: MatchState = _shop_state(true, 1)
	var t: TankState = state.tanks[0]
	# Pulse Missile: 1500 per bundle of 5.
	t.money = 7499
	assert_eq(ShopQuantity.buy_error(state, 0, "pulse_missile", 5), "no_money", "5 bundles cost 7,500")
	t.money = 7500
	assert_eq(ShopQuantity.buy_error(state, 0, "pulse_missile", 5), "")
	t.set_stock("pulse_missile", 75)
	assert_eq(ShopQuantity.buy_error(state, 0, "pulse_missile", 5), "inventory_full", "75 + 25 = 100 > 99")
	t.set_stock("pulse_missile", 74)
	assert_eq(ShopQuantity.buy_error(state, 0, "pulse_missile", 5), "")
	# Both reasons at once: the inventory check comes first (docs section 25).
	t.money = 100
	t.set_stock("pulse_missile", 99)
	assert_eq(ShopQuantity.buy_error(state, 0, "pulse_missile", 5), "inventory_full")
	assert_eq(ShopQuantity.max_bundles(state, 0, "pulse_missile"), 0)


func test_max_edge_cases() -> void:
	var state: MatchState = _shop_state(true, 2)
	var t: TankState = state.tanks[1]
	t.money = 1_000_000
	assert_eq(ShopQuantity.max_bundles(state, 1, "fuel_cell"), 99, "1 unit per bundle: the cap decides")
	t.set_stock("fuel_cell", 98)
	assert_eq(ShopQuantity.max_bundles(state, 1, "fuel_cell"), 1)
	t.set_stock("pulse_missile", 98)  # bundle 5: one unit of room, not a whole bundle
	assert_eq(ShopQuantity.max_bundles(state, 1, "pulse_missile"), 0)
	t.set_stock("pulse_missile", 94)
	assert_eq(ShopQuantity.max_bundles(state, 1, "pulse_missile"), 1)
	assert_eq(ShopQuantity.max_bundles(state, 1, "spark_dart"), 0, "unlimited: never buyable")
	assert_eq(ShopQuantity.max_bundles(state, 1, "not_an_item"), 0)
	# Wrong phase: the match is in a round.
	var started: MatchState = QaUtil.started_match(QaUtil.settings(4, 2, 2))
	assert_eq(ShopQuantity.max_bundles(started, 0, "pulse_missile"), 0, "no shopping during a round")
	# Locked in the free game.
	var free: MatchState = _shop_state(false, 3)
	free.tanks[0].money = 1_000_000
	assert_eq(ShopQuantity.max_bundles(free, 0, "supernova"), 0)
	assert_eq(ShopQuantity.buy_error(free, 0, "supernova", 5), "locked_item")
	assert_gt(ShopQuantity.max_bundles(free, 0, "pulse_missile"), 0)


func test_sell_all_pays_exactly_what_the_simulation_pays() -> void:
	var rng: Rng = Rng.derive(7071, 2)
	var checked: int = 0
	for n: int in range(120):
		var state: MatchState = _shop_state(true, 900 + n)
		var ids: Array[String] = _buyable_ids(true)
		var item: String = ids[rng.range_int(0, ids.size() - 1)]
		var t: TankState = state.tanks[rng.range_int(0, 2)]
		t.set_stock(item, rng.range_int(0, 99))
		t.money = rng.range_int(0, 50000)
		var owned: int = ShopQuantity.sell_all_units(state, t.id, item)
		assert_eq(owned, t.stock_of(item))
		var refund: int = ShopQuantity.sell_all_refund(state, t.id, item)
		var action: Dictionary = ShopQuantity.sell_action(t.id, item, maxi(owned, 1))
		var err: String = Simulation.validate_action(state, action)
		if owned == 0:
			assert_eq(err, "out_of_stock", "nothing to sell: %s" % item)
			assert_eq(refund, 0)
			continue
		assert_eq(err, "", item)
		var before: int = t.money
		Simulation.apply_action(state, action)
		assert_eq(t.money - before, refund, "SELL ALL of %d x %s pays the quoted refund" % [owned, item])
		assert_eq(t.stock_of(item), 0)
		checked += 1
	assert_gt(checked, 80)
