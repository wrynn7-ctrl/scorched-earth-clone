extends GutTest
## What the computer opponents buy (docs/ARCHITECTURE.md section 29).


func _shop(level: int, money: int = 10000, tanks: int = 2, seed_value: int = 7) -> MatchState:
	var settings := MatchSettings.new()
	settings.seed = seed_value
	settings.num_tanks = tanks
	settings.rounds = 3
	settings.start_money = money
	var ctrl := PackedInt32Array()
	for _i: int in range(tanks):
		ctrl.append(level)
	settings.controllers = ctrl
	return Simulation.new_match(settings)


## Runs the AI shop for one tank and applies it; returns the actions.
func _go(state: MatchState, tank: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = AiPlayer.shop_actions(state, tank)
	for a: Dictionary in actions:
		assert_eq(Simulation.validate_action(state, a), "", "illegal shop action %s" % str(a))
		Simulation.apply_action(state, a)
	return actions


func _bought(actions: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for a: Dictionary in actions:
		if a["kind"] == "buy":
			out[a["item"]] = (out.get(a["item"], 0) as int) + (a["qty"] as int)
	return out


func test_the_list_always_ends_with_ready_and_every_buy_is_legal() -> void:
	for level: int in [1, 2, 3, 4]:
		for money: int in [0, 900, 3000, 10000, 60000]:
			var state: MatchState = _shop(level, money)
			var actions: Array[Dictionary] = _go(state, 0)
			assert_false(actions.is_empty())
			assert_eq(actions[actions.size() - 1]["kind"], "ready", "level %d money %d" % [level, money])
			assert_eq(actions.filter(func(a: Dictionary) -> bool: return a["kind"] == "ready").size(), 1)
			assert_true(state.tanks[0].ready)
			assert_gte(state.tanks[0].money, 0)
			assert_lte(state.tanks[0].money, money)


func test_a_tank_that_is_already_ready_buys_nothing() -> void:
	var state: MatchState = _shop(4)
	_go(state, 0)
	assert_eq(AiPlayer.shop_actions(state, 0), [])
	var aim: MatchState = AiTestUtil.duel(3, 4, 700, 0)
	assert_eq(AiPlayer.shop_actions(aim, 0), [], "outside the shop phase")


func test_shop_fuzz_over_random_stock_and_money_is_always_legal() -> void:
	var bad: int = 0
	for i: int in range(120):
		var r: Rng = Rng.derive(i, 313)
		var state: MatchState = _shop(r.range_int(1, 4), r.range_int(0, 40000), r.range_int(2, 5), 300 + i)
		for t: TankState in state.tanks:
			for id: String in Catalog.IDS:
				if id != Catalog.SPARK_DART and r.chance(1, 3):
					t.set_stock(id, r.range_int(1, 99))
		state.tanks[r.range_int(0, state.tanks.size() - 1)].shield_type = Catalog.index_of("ion_shield")
		state.tanks[0].shield_hp = 0
		for t: TankState in state.tanks:
			var sim: MatchState = state.duplicate_state()
			for a: Dictionary in AiPlayer.shop_actions(state, t.id):
				if Simulation.validate_action(sim, a) != "":
					bad += 1
				Simulation.apply_action(sim, a)
	assert_eq(bad, 0, "every shop action of 120 random shops is legal in sequence")


func test_easy_buys_a_few_cheap_random_things() -> void:
	var kinds: Dictionary = {}
	var max_cost: int = 0
	for s: int in range(30):
		var state: MatchState = _shop(SimConstants.CTRL_EASY, 10000, 2, 100 + s)
		var actions: Array[Dictionary] = _go(state, 0)
		var bought: Dictionary = _bought(actions)
		for id: String in bought.keys():
			kinds[id] = true
			assert_true(AiProfile.SHOP_EASY_POOL.has(id) or id == "pulse_missile" or id == "hyperpulse", "Easy bought %s" % id)
		max_cost = maxi(max_cost, 10000 - state.tanks[0].money)
		assert_between(state.tanks[0].stock_of("pulse_missile"), 10, 20, "Easy stocks 8-12 shots of Pulse Missile (bundles of 5)")
		assert_between(10000 - state.tanks[0].money, 3000, 8000, "Easy spends a real share but keeps a reserve")
	gut.p("SHOP    easy: %d different cheap items over 30 shops, most spent %d of 10000" % [kinds.size(), max_cost])
	assert_gte(kinds.size(), 5, "random: a varied mix")
	assert_lte(max_cost, 8000, "keeps at least a 20% reserve")


func test_normal_buys_a_balanced_simple_kit() -> void:
	var state: MatchState = _shop(SimConstants.CTRL_NORMAL)
	_go(state, 0)
	var t: TankState = state.tanks[0]
	assert_gte(t.stock_of("pulse_missile"), 10)
	assert_gte(t.stock_of("glow_shield"), 1)
	# 60-75% of the money goes into the kit; the rest stays in the bank.
	assert_between(10000 - t.money, 4500, 7500, "Normal spends 45-75% of 10000")
	assert_gte(t.money, 2500)
	gut.p("SHOP    normal kit: pulse %d, hyperpulse %d, glow shield %d, chutes %d, money left %d" % [
			t.stock_of("pulse_missile"), t.stock_of("hyperpulse"), t.stock_of("glow_shield"),
			t.stock_of("drift_chute"), t.money])
	assert_eq(t.stock_of("singularity_seed"), 0)
	assert_eq(t.stock_of("static_burst"), 0)


func test_hard_plans_shield_strong_weapons_and_chutes() -> void:
	var state: MatchState = _shop(SimConstants.CTRL_HARD, 20000)
	_go(state, 0)
	var t: TankState = state.tanks[0]
	gut.p("SHOP    hard kit (20000): pulse %d, hyperpulse %d, ion shield %d, chutes %d, seeker %d, nova %d, repair %d, money left %d" % [
			t.stock_of("pulse_missile"), t.stock_of("hyperpulse"), t.stock_of("ion_shield"),
			t.stock_of("drift_chute"), t.stock_of("seeker"), t.stock_of("nova_core"),
			t.stock_of("nanorepair_kit"), t.money])
	assert_gte(t.stock_of("ion_shield"), 1, "shield first")
	assert_gte(t.stock_of("hyperpulse"), 6)
	assert_gte(t.stock_of("drift_chute"), 2)
	assert_gte(t.stock_of("pulse_missile"), 10)
	assert_gte(t.stock_of("seeker"), 2)


func test_expert_saves_money_and_keeps_a_reserve() -> void:
	var state: MatchState = _shop(SimConstants.CTRL_EXPERT, 10000)
	_go(state, 0)
	var t: TankState = state.tanks[0]
	gut.p("SHOP    expert kit (10000): pulse %d, hyperpulse %d, ion shield %d, chutes %d, money left %d" % [
			t.stock_of("pulse_missile"), t.stock_of("hyperpulse"), t.stock_of("ion_shield"),
			t.stock_of("drift_chute"), t.money])
	assert_gte(t.money, AiProfile.EXPERT_RESERVE, "keeps a reserve")
	assert_gte(t.stock_of("pulse_missile"), 10)
	assert_gte(t.stock_of("ion_shield"), 1)
	# Already stocked up: the next shop spends nothing.
	for entry: Array in AiProfile.SHOP_EXPERT:
		t.set_stock(entry[0], maxi(t.stock_of(entry[0]), entry[1] as int))
	t.money = 8000
	t.ready = false
	var again: Array[Dictionary] = _go(state, 0)
	assert_eq(_bought(again), {}, "nothing to buy when stocked")
	assert_eq(t.money, 8000)


func test_expert_counters_what_the_opponents_own() -> void:
	var plain: MatchState = _shop(SimConstants.CTRL_EXPERT, 20000)
	var plain_buys: Dictionary = _bought(_go(plain, 0))
	assert_false(plain_buys.has("static_burst"), "no shields around: no Static Burst")
	assert_false(plain_buys.has("photon_lance"))
	var shielded: MatchState = _shop(SimConstants.CTRL_EXPERT, 20000)
	shielded.tanks[1].set_stock("ion_shield", 1)
	var buys: Dictionary = _bought(_go(shielded, 0))
	assert_true(buys.has("static_burst"), "an opponent owns a shield: Static Burst (%s)" % str(buys))
	var repulsing: MatchState = _shop(SimConstants.CTRL_EXPERT, 20000)
	repulsing.tanks[1].set_stock("repulsor_field", 1)
	var buys2: Dictionary = _bought(_go(repulsing, 0))
	assert_true(buys2.has("photon_lance"), "an opponent owns a repulsor: Photon Lance (%s)" % str(buys2))
	var active: MatchState = _shop(SimConstants.CTRL_EXPERT, 20000)
	active.tanks[1].shield_type = Catalog.index_of("glow_shield")
	active.tanks[1].shield_hp = 20
	assert_true(_bought(_go(active, 0)).has("static_burst"), "a live shield counts too")


func test_a_poor_expert_does_not_waste_money_on_counters_before_missiles() -> void:
	var state: MatchState = _shop(SimConstants.CTRL_EXPERT, 3500)
	state.tanks[1].set_stock("ion_shield", 1)
	var buys: Dictionary = _bought(_go(state, 0))
	assert_true(buys.has("pulse_missile"), "ammunition first: %s" % str(buys))


func test_all_levels_buy_in_a_free_version_match_without_locked_items() -> void:
	for level: int in [1, 2, 3, 4]:
		var state: MatchState = _shop(level, 30000)
		state.settings.full_unlocked = false
		_go(state, 0)
		for id: String in Catalog.IDS:
			if Catalog.get_def(id)["tier"] == "full":
				assert_eq(state.tanks[0].stock_of(id), 0, "level %d bought locked %s" % [level, id])


func test_shopping_is_deterministic_and_does_not_depend_on_the_other_tanks_having_shopped() -> void:
	var a: MatchState = _shop(SimConstants.CTRL_EASY, 10000, 3, 55)
	var b: MatchState = _shop(SimConstants.CTRL_EASY, 10000, 3, 55)
	assert_eq(AiPlayer.shop_actions(a, 2), AiPlayer.shop_actions(b, 2))
	_go(b, 0)
	assert_eq(AiPlayer.shop_actions(a, 1), AiPlayer.shop_actions(b, 1), "own purchases come from the tank's own stream")


func test_a_second_shop_after_a_round_buys_with_the_round_money() -> void:
	var settings := MatchSettings.new()
	settings.seed = 9
	settings.num_tanks = 2
	settings.rounds = 2
	settings.controllers = PackedInt32Array([SimConstants.CTRL_NORMAL, SimConstants.CTRL_NORMAL])
	var state: MatchState = Simulation.new_match(settings)
	for t: TankState in state.tanks:
		_go(state, t.id)
	Simulation.start_round(state)
	SimTestUtil.kill_all_but(state, 0)
	Simulation.apply_action(state, SimTestUtil.pass_turn(0))
	assert_eq(state.phase, SimConstants.PHASE_SHOP, "round over, shop open")
	var money_before: int = state.tanks[1].money
	var second: Array[Dictionary] = _go(state, 1)
	assert_eq(second[second.size() - 1]["kind"], "ready")
	assert_lte(state.tanks[1].money, money_before)
