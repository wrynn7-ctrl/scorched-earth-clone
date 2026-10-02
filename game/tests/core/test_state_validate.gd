extends GutTest
## StateSerial.validate and SaveCodec.decode's "invalid_state" (docs/ARCHITECTURE.md section 22):
## a re-sealed save must still be a state the simulation could have produced.

const U = preload("res://tests/core/sim_test_util.gd")


func _settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = 99
	s.num_tanks = 3
	s.rounds = 3
	return s


## A mid-round aim state with some shopping behind it.
func _aim() -> MatchState:
	var s: MatchState = Simulation.new_match(_settings())
	Simulation.apply_action(s, U.buy(0, "glow_shield", 1))
	Simulation.apply_action(s, U.buy(1, "fuel_cell", 2))
	U.begin_round(s)
	return s


func _last_round() -> MatchState:
	var s: MatchState = _aim()
	s.round_index = s.settings.rounds - 1
	return s


func _bad(mutate: Callable, base: MatchState = null) -> String:
	var s: MatchState = (base if base != null else _aim()).duplicate_state()
	mutate.call(s)
	return StateSerial.validate(s)


func _assert_invalid(mutate: Callable, what: String, base: MatchState = null) -> void:
	assert_ne(_bad(mutate, base), "", what)
	var s: MatchState = (base if base != null else _aim()).duplicate_state()
	mutate.call(s)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_false(res["ok"], "decode rejects: %s" % what)
	assert_eq(res["error"], "invalid_state", what)
	assert_null(res["state"])


func test_legitimate_states_validate() -> void:
	assert_eq(StateSerial.validate(_aim()), "")
	assert_eq(StateSerial.validate(Simulation.new_match(_settings())), "", "fresh shop, no terrain")
	var s: MatchState = _aim()
	Simulation.apply_action(s, U.use_item(0, "glow_shield"))
	assert_eq(StateSerial.validate(s), "", "with a shield up")
	s.wells.append({"owner": 1, "x": 700, "y": 300, "expires_turn": s.turn_number + 6})
	assert_eq(StateSerial.validate(s), "", "with a well")
	var shop: MatchState = _aim()
	U.kill_all_but(shop, 0)
	Simulation.apply_action(shop, U.pass_turn(shop.current_tank))
	assert_eq(StateSerial.validate(shop), "", "after a round (shop again)")


func test_a_finished_match_validates() -> void:
	var settings: MatchSettings = _settings()
	settings.rounds = 1
	var s: MatchState = Simulation.new_match(settings)
	U.begin_round(s)
	U.kill_all_but(s, 0)
	s.current_tank = 0
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(U.find(ev, "round_end").size(), 1)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(StateSerial.validate(s), "")
	assert_true(SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))["ok"])


func test_phase_and_round_flow() -> void:
	_assert_invalid(func(s: MatchState) -> void: s.phase = "round_over", "round_over is never produced")
	# An unknown phase string cannot survive encoding (phase_code maps it to the shop), so only validate() sees it.
	assert_ne(_bad(func(s: MatchState) -> void: s.phase = "nonsense"), "", "unknown phase")
	_assert_invalid(func(s: MatchState) -> void: s.round_index = 77, "round_index beyond rounds")
	_assert_invalid(func(s: MatchState) -> void: s.round_index = -2, "round_index below -1")
	_assert_invalid(func(s: MatchState) -> void: s.round_index = -1, "round -1 with terrain / in aim")
	_assert_invalid(func(s: MatchState) -> void: s.terrain = null, "aim without terrain")
	_assert_invalid(func(s: MatchState) -> void: s.phase = SimConstants.PHASE_MATCH_OVER, "match_over in round 0 of 3")
	var shop: MatchState = Simulation.new_match(_settings())
	_assert_invalid(func(s: MatchState) -> void: s.terrain = Terrain.new(SimConstants.WORLD_W, SimConstants.WORLD_H),
			"terrain before the first round", shop)
	_assert_invalid(func(s: MatchState) -> void: s.phase = SimConstants.PHASE_AIM, "aim at round -1", shop)
	_assert_invalid(func(s: MatchState) -> void: s.phase = SimConstants.PHASE_SHOP, "shop with terrain at the last round",
			_last_round())
	_assert_invalid(func(s: MatchState) -> void: s.turn_number = -1, "negative turn number")


func test_current_tank() -> void:
	_assert_invalid(func(s: MatchState) -> void: s.current_tank = 99, "current_tank 99")
	_assert_invalid(func(s: MatchState) -> void: s.current_tank = -1, "current_tank -1")
	_assert_invalid(func(s: MatchState) -> void: s.current_tank = 3, "current_tank == tank count")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[s.current_tank].alive = false
		s.tanks[s.current_tank].health = 0, "the tank to act is dead")
	_assert_invalid(func(s: MatchState) -> void:
		for i: int in [1, 2]:
			s.tanks[i].alive = false
			s.tanks[i].health = 0, "aim with one tank alive")


func test_settings_and_tank_count() -> void:
	_assert_invalid(func(s: MatchState) -> void: s.settings.num_tanks = 7, "num_tanks != tanks")
	_assert_invalid(func(s: MatchState) -> void: s.settings.num_tanks = 1, "num_tanks below 2")
	_assert_invalid(func(s: MatchState) -> void: s.settings.rounds = 0, "rounds 0")
	_assert_invalid(func(s: MatchState) -> void: s.settings.rounds = 21, "rounds 21")
	_assert_invalid(func(s: MatchState) -> void: s.settings.wind_max = 101, "wind_max 101")
	_assert_invalid(func(s: MatchState) -> void: s.settings.start_money = -1, "negative start money")
	_assert_invalid(func(s: MatchState) -> void: s.tanks.pop_back(), "a tank missing")


func test_wind() -> void:
	var calm: MatchSettings = _settings()
	calm.wind_max = 20
	var base: MatchState = Simulation.new_match(calm)
	U.begin_round(base)
	assert_eq(StateSerial.validate(base), "")
	_assert_invalid(func(s: MatchState) -> void: s.wind = 21, "wind above wind_max", base)
	_assert_invalid(func(s: MatchState) -> void: s.wind = -21, "wind below -wind_max", base)
	_assert_invalid(func(s: MatchState) -> void: s.wind_rng_state = PackedInt64Array([0, 0, 0, 0]), "unseeded wind stream in a round", base)
	_assert_invalid(func(s: MatchState) -> void: s.wind_rng_state = PackedInt64Array([1, 2, 3, 1 << 33]), "wind word above 32 bits", base)
	_assert_invalid(func(s: MatchState) -> void: s.wind_rng_state = PackedInt64Array([1, 2, 3, -1]), "negative wind word", base)
	_edge_wind_ok(base)


func _edge_wind_ok(base: MatchState) -> void:
	var s: MatchState = base.duplicate_state()
	s.wind = 20
	assert_eq(StateSerial.validate(s), "", "wind exactly at the limit")
	s.wind = -20
	assert_eq(StateSerial.validate(s), "")


func test_tank_health_and_alive() -> void:
	_assert_invalid(func(s: MatchState) -> void: s.tanks[1].health = 5000, "health 5000")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[1].health = 101, "health 101")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[1].health = -1, "negative health")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[1].alive = false, "dead with health")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[1].health = 0, "alive with 0 health")
	var ok: MatchState = _aim()
	ok.tanks[1].health = 1
	assert_eq(StateSerial.validate(ok), "", "1 HP is fine")
	ok.tanks[1].health = 100
	assert_eq(StateSerial.validate(ok), "")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].angle = 1801, "angle 1801")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].angle = -1, "angle -1")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].power = 0, "power 0")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].power = 1001, "power 1001")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].id = 0, "duplicate tank id")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].team = -1, "negative team")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].color_index = 8, "colour index 8")


func test_shield_fields() -> void:
	var glow: int = Catalog.index_of("glow_shield")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = 999
		s.tanks[0].shield_hp = 5, "shield_type 999")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = -2
		s.tanks[0].shield_hp = 0, "shield_type -2")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = Catalog.index_of("pulse_missile")
		s.tanks[0].shield_hp = 5, "a weapon as the shield")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = glow
		s.tanks[0].shield_hp = 31, "glow shield above its 30 hp")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = glow
		s.tanks[0].shield_hp = -5, "negative shield hp")
	_assert_invalid(func(s: MatchState) -> void:
		s.tanks[0].shield_type = glow
		s.tanks[0].shield_hp = 0, "shield type without hp")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].shield_hp = 10, "hp without a shield")
	var ok: MatchState = _aim()
	ok.tanks[0].shield_type = glow
	ok.tanks[0].shield_hp = 30
	assert_eq(StateSerial.validate(ok), "", "full glow shield")
	ok.tanks[0].shield_hp = 1
	assert_eq(StateSerial.validate(ok), "")
	ok.tanks[0].shield_type = Catalog.index_of("fortress_field")
	ok.tanks[0].shield_hp = 100
	assert_eq(StateSerial.validate(ok), "", "fortress field holds 100")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].repulsor_charge = 101, "repulsor charge 101")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].repulsor_charge = -1, "repulsor charge -1")
	ok.tanks[0].repulsor_charge = 100
	assert_eq(StateSerial.validate(ok), "")


func test_inventory_fuel_money() -> void:
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].inventory[3] = -7, "negative stock")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].inventory[3] = 100, "stock 100")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].inventory[0] = 4, "spark_dart stored")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].fuel = -1, "negative fuel")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].fuel = 100001, "fuel beyond the cap")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].money = -1, "negative money")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].money = 1_000_000_001, "money above 10^9")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].kills = -1, "negative kills")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].round_wins = 4, "more round wins than rounds")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[0].ready = true, "ready flag during a round")
	var ok: MatchState = _aim()
	ok.tanks[0].inventory[3] = 99
	ok.tanks[0].fuel = 100000
	ok.tanks[0].money = 1_000_000_000
	assert_eq(StateSerial.validate(ok), "", "the limits themselves are legal")
	var shop: MatchState = Simulation.new_match(_settings())
	shop.tanks[0].ready = true
	assert_eq(StateSerial.validate(shop), "", "ready is fine in the shop")


func test_terrain_and_tank_boxes() -> void:
	_assert_invalid(func(s: MatchState) -> void:
		s.terrain.width = 10
		s.terrain.cells.resize(10 * 900), "terrain 10 columns wide")
	_assert_invalid(func(s: MatchState) -> void:
		s.terrain = Terrain.new(SimConstants.WORLD_W, 100), "terrain 100 high")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].x = -500, "tank far left of the map")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].x = 11, "box hangs 1 cell over the left edge")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].x = SimConstants.WORLD_W - 11, "box hangs over the right edge")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].x = 5000, "tank far right")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].y = -3, "tank above the sky limit")
	_assert_invalid(func(s: MatchState) -> void: s.tanks[2].y = 901, "tank below bedrock")
	var ok: MatchState = _aim()
	ok.tanks[2].x = 12
	assert_eq(StateSerial.validate(ok), "", "box flush with the left wall")
	ok.tanks[2].x = SimConstants.WORLD_W - 12
	assert_eq(StateSerial.validate(ok), "", "box flush with the right wall")


func test_wells() -> void:
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 40, "x": 5, "y": 5, "expires_turn": 3}] as Array[Dictionary], "owner 40")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": -1, "x": 5, "y": 5, "expires_turn": 3}] as Array[Dictionary], "owner -1")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 0, "x": 5000, "y": 5, "expires_turn": 3}] as Array[Dictionary], "x off the map")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 0, "x": 5, "y": -9000, "expires_turn": 3}] as Array[Dictionary], "y far above")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 0, "x": 5, "y": 5, "expires_turn": -1}] as Array[Dictionary], "negative expiry")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 0, "x": 5, "y": 5, "expires_turn": 999999}] as Array[Dictionary], "expiry in the far future")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 1, "x": 5, "y": 5, "expires_turn": 3}, {"owner": 0, "x": 9, "y": 5, "expires_turn": 3}] as Array[Dictionary],
			"wells out of owner order")
	_assert_invalid(func(s: MatchState) -> void:
		s.wells = [{"owner": 1, "x": 5, "y": 5, "expires_turn": 3}, {"owner": 1, "x": 9, "y": 5, "expires_turn": 3}] as Array[Dictionary],
			"two wells of one owner")
	var ok: MatchState = _aim()
	ok.wells = [{"owner": 0, "x": 0, "y": 0, "expires_turn": 2}, {"owner": 2, "x": 1599, "y": 900, "expires_turn": 6}] as Array[Dictionary]
	assert_eq(StateSerial.validate(ok), "")


func test_validation_is_cheap_and_does_not_mutate() -> void:
	var s: MatchState = _aim()
	var fp: String = Simulation.fingerprint(s)
	var t0: int = Time.get_ticks_usec()
	for _i: int in range(20):
		StateSerial.validate(s)
	var per_call_us: int = (Time.get_ticks_usec() - t0) / 20
	assert_eq(Simulation.fingerprint(s), fp)
	assert_lt(per_call_us, 5000, "no per-cell work: %d us" % per_call_us)
