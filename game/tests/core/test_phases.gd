extends GutTest
## Phase flow (docs/ARCHITECTURE.md section 16): shop -> ready -> round -> shop -> ... -> match_over.

const U = preload("res://tests/core/sim_test_util.gd")


func test_new_match_is_a_shop_without_terrain() -> void:
	var s: MatchState = U.shop_state(3)
	assert_eq(s.phase, "shop")
	assert_eq(s.round_index, -1)
	assert_null(s.terrain)
	assert_eq(s.tanks.size(), 3)
	assert_eq(s.wells.size(), 0)
	for t: TankState in s.tanks:
		assert_eq(t.money, SimConstants.DEFAULT_START_MONEY)
		assert_eq(t.kills, 0)
		assert_eq(t.damage_dealt, 0)
		assert_eq(t.round_wins, 0)
		assert_false(t.ready)
		assert_eq(t.shield_type, -1)
		assert_eq(t.shield_hp, 0)
		assert_eq(t.repulsor_charge, 0)
		assert_eq(t.stock_of("spark_dart"), 0, "the spark dart is never stored")
		for n: int in t.inventory:
			assert_eq(n, 0, "empty inventory")


func test_start_money_setting_is_used() -> void:
	var st := MatchSettings.new()
	st.num_tanks = 2
	st.start_money = 777
	var s: MatchState = Simulation.new_match(st)
	for t: TankState in s.tanks:
		assert_eq(t.money, 777)


func test_start_round_needs_every_tank_ready() -> void:
	var s: MatchState = U.shop_state(3)
	var before: String = Simulation.fingerprint(s)
	assert_eq(Simulation.start_round(s).size(), 0, "nobody ready")
	Simulation.apply_action(s, U.ready(0))
	Simulation.apply_action(s, U.ready(2))
	assert_false(Simulation.all_ready(s))
	var mid: String = Simulation.fingerprint(s)
	assert_eq(Simulation.start_round(s).size(), 0, "tank 1 not ready")
	assert_eq(Simulation.fingerprint(s), mid, "a refused start_round changes nothing")
	assert_ne(mid, before)
	Simulation.apply_action(s, U.ready(1))
	assert_true(Simulation.all_ready(s))
	var ev: Array[Dictionary] = Simulation.start_round(s)
	assert_eq(U.types(ev), ["round_start", "wind", "turn"] as Array[String])
	assert_eq(s.phase, "aim")
	assert_eq(s.round_index, 0)
	assert_not_null(s.terrain)
	for t: TankState in s.tanks:
		assert_false(t.ready, "ready flags are cleared by start_round")
	assert_eq(Simulation.start_round(s).size(), 0, "not valid in aim")
	assert_false(Simulation.all_ready(s), "all_ready is false outside the shop")


func test_full_flow_two_rounds_to_match_over() -> void:
	var s: MatchState = U.shop_state(2, 2)
	for t: TankState in s.tanks:
		Simulation.apply_action(s, U.buy(t.id, "pulse_missile", 1))
	U.begin_round(s)
	assert_eq(s.phase, "aim")
	assert_eq(s.round_index, 0)
	assert_eq(s.current_tank, 0)
	# round 0 ends: tank 1 is destroyed
	Simulation.apply_damage(s, 0, 1, 500, "explosion", 0, [] as Array[Dictionary])
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(U.find(ev, "round_end")[0]["winner"], 0)
	assert_eq(s.phase, "shop", "back to the shop after round pay")
	assert_eq(s.tanks[0].round_wins, 1)
	# shop again: stock and money persist, new round re-places everyone
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 5)
	var money0: int = s.tanks[0].money
	Simulation.apply_action(s, U.buy(1, "glow_shield", 1))
	var old_cells: PackedByteArray = s.terrain.cells.duplicate()
	U.begin_round(s)
	assert_eq(s.round_index, 1)
	assert_eq(s.current_tank, 1, "first turn rotates with the round")
	assert_eq(s.tanks[0].money, money0, "money kept across rounds")
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 5)
	assert_true(s.terrain.cells != old_cells, "fresh terrain")
	assert_eq(TankState.rest_y(s.terrain, s.tanks[0].x), s.tanks[0].y)
	# round 1 (the last): tank 0 dies -> match_over, still paid
	Simulation.apply_damage(s, 1, 0, 500, "explosion", 0, [] as Array[Dictionary])
	var ev2: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(1))
	assert_eq(U.find(ev2, "round_end")[0]["winner"], 1)
	assert_eq(s.phase, "match_over")
	assert_gt(U.find(ev2, "money").size(), 0, "last round is paid too")
	assert_eq(Simulation.start_round(s).size(), 0)
	assert_eq(Simulation.standings(s), [0, 1] as Array[int], "1 win, 100 damage and 1 kill each: lower id first")


func test_round_scoped_state_is_reset_and_persistent_state_kept() -> void:
	var s: MatchState = U.started_match(_settings(3))
	var t: TankState = s.tanks[1]
	t.health = 20
	t.shield_type = Catalog.index_of("ion_shield")
	t.shield_hp = 17
	t.repulsor_charge = 44
	t.fuel = 33
	t.kills = 2
	t.damage_dealt = 250
	t.set_stock("fuel_cell", 4)
	t.money = 4321
	s.wells.append({"owner": 1, "x": 10, "y": 20, "expires_turn": 99})
	s.phase = "shop"
	U.begin_round(s)
	assert_eq(t.health, SimConstants.MAX_HEALTH)
	assert_true(t.alive)
	assert_eq(t.shield_type, -1)
	assert_eq(t.shield_hp, 0)
	assert_eq(t.repulsor_charge, 0)
	assert_eq(s.wells.size(), 0, "wells cleared")
	assert_eq(t.fuel, 33, "fuel kept")
	assert_eq(t.kills, 2)
	assert_eq(t.damage_dealt, 250)
	assert_eq(t.stock_of("fuel_cell"), 4)
	assert_eq(t.money, 4321)
	assert_eq(t.power, SimConstants.DEFAULT_POWER)
	assert_eq(s.turn_number, 0)


func test_dead_tanks_are_revived_for_the_next_round_and_can_shop_before() -> void:
	var s: MatchState = U.started_match(_settings(2))
	U.kill_all_but(s, 0)
	Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(s.phase, "shop")
	assert_false(s.tanks[1].alive)
	assert_eq(Simulation.validate_action(s, U.buy(1, "fuel_cell", 1)), "", "dead tanks can still shop")
	assert_eq(Simulation.validate_action(s, U.ready(1)), "")
	U.begin_round(s)
	assert_true(s.tanks[1].alive)


func test_actions_from_the_wrong_phase_are_rejected() -> void:
	var s: MatchState = U.shop_state(2)
	for a: Dictionary in [U.fire(0, 450, 500), U.move(0, 1), U.use_item(0, "glow_shield"), U.pass_turn(0)]:
		assert_eq(Simulation.validate_action(s, a), "bad_phase", "aim action in the shop: %s" % str(a))
	var aim: MatchState = U.flat_state()
	for a: Dictionary in [U.buy(0, "fuel_cell"), U.sell(0, "pulse_missile"), U.ready(0)]:
		assert_eq(Simulation.validate_action(aim, a), "bad_phase", "shop action in aim: %s" % str(a))
	aim.phase = "match_over"
	for a: Dictionary in [U.buy(0, "fuel_cell"), U.ready(0), U.fire(0, 450, 500), U.pass_turn(0)]:
		assert_eq(Simulation.validate_action(aim, a), "bad_phase", "anything in match_over: %s" % str(a))


func test_not_your_turn_does_not_apply_in_the_shop() -> void:
	var s: MatchState = U.shop_state(3)
	assert_eq(Simulation.validate_action(s, U.buy(2, "fuel_cell")), "")
	assert_eq(Simulation.validate_action(s, U.ready(1)), "")
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.ready(2))
	assert_eq(U.types(ev), ["ready"] as Array[String])
	assert_true(s.tanks[2].ready)


func test_round_over_phase_constant_is_kept_but_unused() -> void:
	assert_eq(SimConstants.PHASE_ROUND_OVER, "round_over")
	var s: MatchState = U.started_match(_settings(2))
	U.kill_all_but(s, 0)
	Simulation.apply_action(s, U.pass_turn(0))
	assert_ne(s.phase, SimConstants.PHASE_ROUND_OVER)


func _settings(n: int) -> MatchSettings:
	var st := MatchSettings.new()
	st.seed = 99
	st.num_tanks = n
	st.rounds = 3
	return st
