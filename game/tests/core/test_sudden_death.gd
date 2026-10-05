@warning_ignore_start("integer_division")
extends GutTest
## Sudden death (docs/ARCHITECTURE.md section 40): threshold, drain schedule, shields, round end,
## draws, love mode and saves.

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


## Flat-ground match; the turn counter starts at `turn` and tank 0 holds the turn.
func _state(n: int, turn: int = 0) -> MatchState:
	var s: MatchState = U.flat_state(n)
	s.turn_number = turn
	return s


func _pass_turn(s: MatchState) -> Array[Dictionary]:
	return Simulation.apply_action(s, U.pass_turn(s.current_tank))


func _pass_n(s: MatchState, count: int) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for _i: int in range(count):
		all.append_array(_pass_turn(s))
	return all


func _drains(ev: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in ev:
		if e["type"] == "damage" and e["cause"] == "sudden_death":
			out.append(e)
	return out


# --- threshold -----------------------------------------------------------------------------

func test_constants_and_helpers() -> void:
	assert_eq(SimConstants.SUDDEN_DEATH_TURNS_PER_TANK, 10)
	assert_eq(SimConstants.SUDDEN_DEATH_BASE, 5)
	assert_eq(SimConstants.SUDDEN_DEATH_MAX, 25)
	var st := MatchSettings.new()
	for n: int in [2, 3, 4, 8]:
		st.num_tanks = n
		assert_eq(Simulation.sudden_death_turn(st), 10 * n)
	var amounts: Array[int] = []
	for c: int in range(1, 9):
		amounts.append(Simulation.sudden_death_amount(c))
	assert_eq(amounts, [5, 10, 15, 20, 25, 25, 25, 25] as Array[int])
	assert_eq(Simulation.sudden_death_amount(0), 0)


func test_threshold_turn_for_2_3_4_and_8_tanks() -> void:
	for n: int in [2, 3, 4, 8]:
		var s: MatchState = _state(n)
		var threshold: int = 10 * n
		var first: int = -1
		var seen: int = 0
		for turn: int in range(1, threshold + 2 * n + 1):
			var ev: Array[Dictionary] = _pass_turn(s)
			var sd: Array[Dictionary] = U.find(ev, "sudden_death")
			seen += sd.size()
			if sd.size() > 0 and first < 0:
				first = turn
				assert_eq(s.turn_number, threshold, "%d tanks" % n)
		assert_eq(first, threshold, "%d tanks: the %dth turn" % [n, threshold])
		assert_eq(seen, 1, "%d tanks: emitted exactly once" % n)


func test_no_drain_and_no_event_before_the_threshold() -> void:
	var s: MatchState = _state(3)
	var ev: Array[Dictionary] = _pass_n(s, 29)
	assert_eq(U.find(ev, "sudden_death").size(), 0)
	assert_eq(_drains(ev).size(), 0)
	for t: TankState in s.tanks:
		assert_eq(t.health, 100)
	assert_eq(s.sudden_death_cycles, 0)


func test_the_event_shape() -> void:
	var s: MatchState = _state(2, 19)
	var ev: Array[Dictionary] = _pass_turn(s)
	var sd: Dictionary = U.find(ev, "sudden_death")[0]
	assert_eq(sd, {"type": "sudden_death", "tick": 0})


func test_threshold_crossing_mid_cycle_drains_at_the_next_wrap() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 1
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(s.turn_number, 30)
	assert_eq(U.find(ev, "sudden_death").size(), 1)
	assert_eq(_drains(ev).size(), 0, "tank 1 -> 2 is not a wrap")
	assert_eq(U.types(ev), ["sudden_death", "wind", "turn"] as Array[String])
	ev = _pass_turn(s)
	assert_eq(_drains(ev).size(), 3, "tank 2 passes to tank 0: that wraps, and the drain runs")
	assert_eq(s.sudden_death_cycles, 1)
	assert_eq(U.find(ev, "sudden_death").size(), 0, "the event was already emitted")


func test_threshold_crossing_on_the_wrap_drains_at_once() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.types(ev).slice(0, 1), ["sudden_death"] as Array[String])
	assert_eq(_drains(ev).size(), 3)
	for t: TankState in s.tanks:
		assert_eq(t.health, 95)
	assert_eq(s.sudden_death_cycles, 1)
	assert_eq(s.current_tank, 0)


# --- drain ---------------------------------------------------------------------------------------

func test_drain_schedule_5_10_15_20_25_25() -> void:
	var s: MatchState = _state(2, 18)
	# Staggered health so nobody dies during the six cycles.
	s.tanks[0].health = 100
	s.tanks[1].health = 100
	var seen: Array[int] = []
	var healths: Array[int] = []
	for cycle: int in range(5):
		var ev: Array[Dictionary] = _pass_n(s, 2)
		for d: Dictionary in _drains(ev):
			if d["tank"] == 0:
				seen.append(d["amount"])
				healths.append(d["health"])
		assert_eq(s.sudden_death_cycles, cycle + 1)
	assert_eq(seen, [5, 10, 15, 20, 25] as Array[int], "the first drain is on the pass that wraps at turn 20")
	assert_eq(healths, [95, 85, 70, 50, 25] as Array[int])


func test_escalation_stops_at_25() -> void:
	var s: MatchState = _state(2, 18)
	s.sudden_death_cycles = 9
	s.turn_number = 40
	var ev: Array[Dictionary] = _pass_n(s, 2)
	var d: Array[Dictionary] = _drains(ev)
	assert_eq(d.size(), 2)
	assert_eq(d[0]["amount"], 25)
	assert_eq(s.sudden_death_cycles, 10)


func test_drain_event_fields_and_order() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	s.tanks[1].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.types(ev), ["sudden_death", "damage", "damage", "damage", "tank_destroyed", "wind", "turn"] as Array[String])
	assert_eq(ev[1], {"type": "damage", "tick": 0, "tank": 0, "amount": 5, "health": 95, "cause": "sudden_death"})
	assert_eq(ev[2]["tank"], 1)
	assert_eq(ev[2]["health"], 0)
	assert_eq(ev[3]["tank"], 2)
	assert_eq(ev[4], {"type": "tank_destroyed", "tick": 0, "tank": 1})
	assert_eq(ev[6]["tank"], 0)


func test_drain_bypasses_shields() -> void:
	var s: MatchState = _state(2, 19)
	s.current_tank = 1
	s.tanks[0].shield_type = Catalog.index_of("ion_shield")
	s.tanks[0].shield_hp = 60
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(s.tanks[0].health, 95)
	assert_eq(s.tanks[0].shield_hp, 60, "the shield is untouched")
	assert_true(s.tanks[0].has_shield())
	assert_eq(U.find(ev, "shield_hit").size(), 0)
	assert_eq(U.find(ev, "shield_down").size(), 0)


func test_drain_gives_no_money_credit_or_kills() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	for t: TankState in s.tanks:
		t.money = 400
	s.tanks[1].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.find(ev, "money").size(), 0)
	for t: TankState in s.tanks:
		assert_eq(t.money, 400)
		assert_eq(t.kills, 0)
		assert_eq(t.damage_dealt, 0)


func test_the_drain_runs_through_apply_damage_with_no_attacker() -> void:
	var s: MatchState = _state(2)
	var ev: Array[Dictionary] = []
	s.tanks[0].money = 100
	assert_eq(Simulation.apply_damage(s, -1, 0, 30, "sudden_death", 0, ev), 30)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	assert_eq(Simulation.apply_damage(s, -1, 1, 30, "sudden_death", 0, ev), 30)
	assert_eq(s.tanks[1].shield_hp, 30)
	assert_eq(s.tanks[0].money, 100)


func test_the_next_tank_skips_one_the_drain_destroyed() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	s.tanks[0].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_false(s.tanks[0].alive)
	assert_eq(s.current_tank, 1, "tank 0 was next but died in the drain")
	assert_eq(U.find(ev, "turn")[0]["tank"], 1)
	assert_eq(s.phase, SimConstants.PHASE_AIM)


func test_drain_skips_dead_tanks() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	var junk: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 1, 1000, "explosion", 0, junk)
	var ev: Array[Dictionary] = _pass_turn(s)
	var d: Array[Dictionary] = _drains(ev)
	assert_eq(d.size(), 2, "only the living are drained")
	assert_eq([d[0]["tank"], d[1]["tank"]], [0, 2])


func test_wrap_with_dead_tanks_uses_the_next_living_index() -> void:
	# Tanks 0 and 1 alive, tank 2 dead: the turn goes 0 -> 1 -> 0, and every 1 -> 0 hop is a wrap.
	var s: MatchState = _state(3, 28)
	var junk: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 2, 1000, "explosion", 0, junk)
	s.turn_number = 29
	s.current_tank = 0
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(s.turn_number, 30)
	assert_eq(_drains(ev).size(), 0)
	ev = _pass_turn(s)
	assert_eq(_drains(ev).size(), 2)
	assert_eq(s.sudden_death_cycles, 1)


func test_a_move_death_in_the_wrap_still_drains() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	s.tanks[2].health = 5
	# The current tank dies on its own turn (e.g. a walking fall); the turn passes on and the wrap drains.
	var junk: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 2, 1000, "fall", 0, junk)
	var ev: Array[Dictionary] = []
	Simulation._finish_turn(s, 0, ev)
	assert_eq(U.find(ev, "sudden_death").size(), 1)
	assert_eq(_drains(ev).size(), 2, "tanks 0 and 1; 2 is gone")
	assert_eq(s.current_tank, 0)


func test_sudden_death_during_a_fire_timeline() -> void:
	var s: MatchState = _state(2, 19)
	s.current_tank = 1
	var ev: Array[Dictionary] = Simulation.apply_action(s, {"kind": "fire", "tank": 1, "angle": 1350,
			"power": 400, "weapon": "pulse_missile"})
	var types: Array[String] = U.types(ev)
	assert_eq(types[0], "fire")
	var i: int = types.find("sudden_death")
	assert_gt(i, 0)
	assert_eq(types.slice(types.size() - 2), ["wind", "turn"] as Array[String])
	assert_true(types.find("explosion") < i, "the shot resolves first, then sudden death starts")
	assert_eq(_drains(ev).size(), 2)


# --- round end ---------------------------------------------------------------------------------

func test_drain_killing_the_last_enemy_ends_the_round() -> void:
	var s: MatchState = _state(2, 19)
	s.current_tank = 1
	s.tanks[1].health = 100
	s.tanks[0].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.types(ev), ["sudden_death", "damage", "damage", "tank_destroyed", "round_end", "money", "money"] as Array[String])
	assert_eq(ev[4], {"type": "round_end", "tick": 0, "winner": 1, "winner_team": 1})
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq(s.tanks[1].round_wins, 1)
	assert_eq(s.tanks[1].money, 3500)
	assert_eq(s.tanks[0].money, 0)
	assert_eq(s.tanks[1].kills, 0, "the drain is nobody's kill")


func test_drain_killing_everyone_is_a_draw() -> void:
	var s: MatchState = _state(3, 29)
	s.current_tank = 2
	for t: TankState in s.tanks:
		t.health = 4
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.types(ev), ["sudden_death", "damage", "damage", "damage", "tank_destroyed", "tank_destroyed",
			"tank_destroyed", "round_end"] as Array[String])
	var ids: Array[int] = []
	for e: Dictionary in U.find(ev, "tank_destroyed"):
		ids.append(e["tank"])
	assert_eq(ids, [0, 1, 2] as Array[int], "destroyed in id order")
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [-1, -1])
	for t: TankState in s.tanks:
		assert_eq(t.money, 0, "no survive pay")
		assert_eq(t.round_wins, 0)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)


func test_the_full_default_health_run_ends_in_a_draw_on_the_sixth_cycle() -> void:
	var s: MatchState = _state(2)
	var all: Array[Dictionary] = []
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 100:
		all.append_array(_pass_turn(s))
		guard += 1
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq(guard, 20 + 2 * 5, "turn 20 is the first drain, then 5 more cycles of 2 turns")
	assert_eq(s.sudden_death_cycles, 6)
	var re: Dictionary = U.find(all, "round_end")[0]
	assert_eq(re["winner"], -1, "5+10+15+20+25+25 = 100 HP for everyone")


func test_a_team_wiped_out_by_the_drain_ends_the_round_for_the_other_team() -> void:
	var s: MatchState = _state(4, 39)
	s.settings.teams = PackedInt32Array([0, 0, 1, 1])
	for i: int in range(4):
		s.tanks[i].team = [0, 0, 1, 1][i]
	s.current_tank = 3
	s.tanks[0].health = 5
	s.tanks[1].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [2, 1])
	assert_eq(s.tanks[2].money, 3500)
	assert_eq(s.tanks[3].money, 3500)
	assert_eq(s.tanks[0].money, 0)


func test_drain_leaving_one_tank_of_each_of_two_teams_keeps_the_round_going() -> void:
	var s: MatchState = _state(4, 39)
	s.settings.teams = PackedInt32Array([0, 0, 1, 1])
	for i: int in range(4):
		s.tanks[i].team = [0, 0, 1, 1][i]
	s.current_tank = 3
	s.tanks[0].health = 5
	s.tanks[2].health = 5
	var ev: Array[Dictionary] = _pass_turn(s)
	assert_eq(U.find(ev, "round_end").size(), 0)
	assert_eq(s.current_tank, 1)
	assert_eq(s.phase, SimConstants.PHASE_AIM)


func test_the_cycle_counter_resets_at_round_start() -> void:
	var st := MatchSettings.new()
	st.seed = 3
	st.num_tanks = 2
	st.rounds = 3
	var s: MatchState = U.started_match(st)
	s.turn_number = 19
	s.sudden_death_cycles = 0
	_pass_turn(s)
	_pass_turn(s)
	assert_gt(s.sudden_death_cycles, 0)
	while s.phase == SimConstants.PHASE_AIM:
		_pass_turn(s)
	assert_gt(s.sudden_death_cycles, 0, "kept after the round, until the next one starts")
	U.begin_round(s)
	assert_eq(s.sudden_death_cycles, 0)
	assert_eq(s.turn_number, 0)


# --- love mode -----------------------------------------------------------------------------------

func test_love_mode_never_has_sudden_death() -> void:
	var st := MatchSettings.new()
	st.seed = 4
	st.mode = SimConstants.MODE_LOVE
	var s: MatchState = Simulation.new_match(st)
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	var all: Array[Dictionary] = _pass_n(s, 120)
	assert_eq(U.find(all, "sudden_death").size(), 0)
	assert_eq(_drains(all).size(), 0)
	assert_eq(s.sudden_death_cycles, 0)
	assert_eq(s.turn_number, 120)
	for t: TankState in s.tanks:
		assert_eq(t.health, 100)
	assert_eq(s.phase, SimConstants.PHASE_AIM)


# --- saves -----------------------------------------------------------------------------------------

func test_the_cycle_counter_survives_a_save_round_trip_and_play_continues_identically() -> void:
	var s: MatchState = _state(3, 29)
	s.settings.rounds = 3
	s.tanks[0].health = 100
	_pass_n(s, 7)
	assert_gt(s.sudden_death_cycles, 0)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_true(res["ok"], str(res["error"]))
	var r: MatchState = res["state"]
	assert_eq(r.sudden_death_cycles, s.sudden_death_cycles)
	assert_eq(Simulation.fingerprint(r), Simulation.fingerprint(s))
	for i: int in range(6):
		var ea: Array[Dictionary] = _pass_turn(s)
		var eb: Array[Dictionary] = _pass_turn(r)
		assert_eq(str(ea), str(eb), "step %d" % i)
	assert_eq(r.sudden_death_cycles, s.sudden_death_cycles)
	assert_eq(Simulation.fingerprint(r), Simulation.fingerprint(s))


func test_duplicate_state_copies_the_counter() -> void:
	var s: MatchState = _state(2)
	s.sudden_death_cycles = 3
	assert_eq(s.duplicate_state().sudden_death_cycles, 3)


func _validated(n: int, turn: int, cycles: int) -> String:
	var st := MatchSettings.new()
	st.seed = 8
	st.num_tanks = n
	st.rounds = 3
	var s: MatchState = U.started_match(st)
	s.turn_number = turn
	s.sudden_death_cycles = cycles
	return StateSerial.validate(s)


func test_validation_of_the_cycle_counter() -> void:
	assert_eq(_validated(2, 5, 0), "")
	assert_eq(_validated(2, 20, 1), "", "the wrap that reaches the threshold counts")
	assert_eq(_validated(2, 25, 6), "")
	assert_ne(_validated(2, 20, 2), "", "more cycles than turns since the threshold")
	assert_ne(_validated(2, 19, 1), "", "before the threshold")
	assert_ne(_validated(2, 5, 1), "")
	assert_ne(_validated(2, 30, -1), "", "negative")
	assert_ne(_validated(4, 20, 1), "", "4 tanks: threshold is 40")
	assert_eq(_validated(4, 40, 1), "")


func test_validation_rejects_cycles_before_the_first_round_and_in_love_mode() -> void:
	var s: MatchState = Simulation.new_match(MatchSettings.new())
	s.sudden_death_cycles = 1
	assert_ne(StateSerial.validate(s), "", "shop before round 0")
	var st := MatchSettings.new()
	st.mode = SimConstants.MODE_LOVE
	var l: MatchState = Simulation.new_match(st)
	l.turn_number = 30
	l.sudden_death_cycles = 1
	assert_ne(StateSerial.validate(l), "")
	l.sudden_death_cycles = 0
	assert_eq(StateSerial.validate(l), "")


func test_a_resealed_bad_counter_is_refused_by_decode() -> void:
	var st := MatchSettings.new()
	st.seed = 9
	var s: MatchState = U.started_match(st)
	s.sudden_death_cycles = 4
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_eq(res["error"], "invalid_state")
