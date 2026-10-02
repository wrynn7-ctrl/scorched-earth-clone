extends GutTest
## A whole scripted match (shopping, walking, shields, repulsors, firing, passing) played
## twice must give identical fingerprints after every step; so must a save/load in the middle.

const U = preload("res://tests/core/sim_test_util.gd")
const START: Dictionary = {"kind": "start_round"}  # script marker for Simulation.start_round
const MAX_STEPS: int = 120


func _settings() -> MatchSettings:
	var st := MatchSettings.new()
	st.seed = 5150
	st.num_tanks = 3
	st.rounds = 3
	st.start_money = 40000
	return st


## Applies one script entry. The start_round marker also turns every tank into a glass
## cannon (health 30) so that rounds end within the script; everything else is a real action.
func _apply_entry(state: MatchState, a: Dictionary) -> void:
	if a["kind"] == "start_round":
		Simulation.start_round(state)
		for t: TankState in state.tanks:
			t.health = 30
	else:
		assert_eq(Simulation.validate_action(state, a), "", "script action must be legal: %s" % str(a))
		Simulation.apply_action(state, a)


## Applies one scripted action (or the start_round marker) and records it.
func _do(state: MatchState, a: Dictionary, log: Array[Dictionary], prints: Array[String]) -> void:
	_apply_entry(state, a)
	log.append(a)
	prints.append(Simulation.fingerprint(state))


## Buys only what the tank can afford and carry (the money situation depends on the play).
func _buy(state: MatchState, tank: int, item: String, qty: int, log: Array[Dictionary], prints: Array[String]) -> void:
	if Simulation.validate_action(state, U.buy(tank, item, qty)) == "":
		_do(state, U.buy(tank, item, qty), log, prints)


func _shop_script(state: MatchState, round_no: int, log: Array[Dictionary], prints: Array[String]) -> void:
	for t: TankState in state.tanks:
		_buy(state, t.id, "pulse_missile", 2, log, prints)
		_buy(state, t.id, ["glow_shield", "ion_shield", "fortress_field"][(t.id + round_no) % 3], 1, log, prints)
		_buy(state, t.id, "fuel_cell", 1, log, prints)
		if t.id != 1:
			_buy(state, t.id, "drift_chute", 1, log, prints)
		if t.id == 2:
			_buy(state, t.id, "repulsor_field", 1, log, prints)
			_buy(state, t.id, "nanorepair_kit", 1, log, prints)
		if round_no == 1 and t.id == 0:
			_do(state, U.sell(t.id, "fuel_cell", 1), log, prints)
		_do(state, U.ready(t.id), log, prints)
	_do(state, START, log, prints)


func _turn_script(state: MatchState, step: int, rng: Rng, log: Array[Dictionary], prints: Array[String]) -> void:
	var me: TankState = state.tanks[state.current_tank]
	for item: String in ["glow_shield", "ion_shield", "fortress_field"]:
		if me.stock_of(item) > 0 and step % 3 != 2:
			_do(state, U.use_item(me.id, item), log, prints)
			break
	if me.stock_of("repulsor_field") > 0:
		_do(state, U.use_item(me.id, "repulsor_field"), log, prints)
	var dx: int = rng.range_int(-40, 40)
	if dx != 0 and (me.fuel > 0 or me.stock_of("fuel_cell") > 0):
		_do(state, U.move(me.id, dx), log, prints)
	if me.health < 70 and me.stock_of("nanorepair_kit") > 0:
		_do(state, U.use_item(me.id, "nanorepair_kit"), log, prints)
		return
	if step % 11 == 10:
		_do(state, U.pass_turn(me.id), log, prints)
		return
	var weapon: String = "pulse_missile" if me.stock_of("pulse_missile") > 0 else "spark_dart"
	var a: Dictionary = _aimed_shot(state, me, weapon, rng)
	_do(state, a, log, prints)


## A shot at the next living enemy: range-formula guess, two refinement traces, a little noise.
func _aimed_shot(state: MatchState, me: TankState, weapon: String, rng: Rng) -> Dictionary:
	var tgt: TankState = me
	for step: int in range(1, state.tanks.size()):
		var cand: TankState = state.tanks[(me.id + step) % state.tanks.size()]
		if cand.alive:
			tgt = cand
			break
	var angle: int = 520 if tgt.x >= me.x else 1280
	var dist: int = maxi(1, absi(tgt.x - me.x))
	var sin2: int = absi(FixedMath.sin10(2 * angle))
	var power: int = clampi(FixedMath.isqrt(519 * dist * FixedMath.ONE / maxi(1, sin2)), 10, 1000)
	for _i: int in range(2):
		var tr: Dictionary = Ballistics.trace(state, me.id, angle, power, weapon, SimConstants.WIND_USE_STATE,
				SimConstants.MAX_FLIGHT_TICKS)
		var hit: int = maxi(1, absi((tr["end_x"] as int) - me.x))
		power = clampi(FixedMath.isqrt(power * power * dist / hit), 10, 1000)
	power = clampi(power + rng.range_int(-12, 12), 1, 1000)
	var a: Dictionary = U.fire(me.id, angle, power)
	a["weapon"] = weapon
	return a


## Plays the script until match_over or `stop_after` log entries. Returns the final state.
func _play(log: Array[Dictionary], prints: Array[String], stop_after: int = 1 << 30) -> MatchState:
	var state: MatchState = Simulation.new_match(_settings())
	prints.append(Simulation.fingerprint(state))
	var rng := Rng.new(777)
	var step: int = 0
	while state.phase != "match_over" and step < MAX_STEPS and log.size() < stop_after:
		if state.phase == "shop":
			_shop_script(state, state.round_index + 1, log, prints)
		else:
			_turn_script(state, step, rng, log, prints)
		step += 1
	return state


func test_scripted_match_twice_gives_identical_fingerprints_at_every_step() -> void:
	var log_a: Array[Dictionary] = []
	var log_b: Array[Dictionary] = []
	var prints_a: Array[String] = []
	var prints_b: Array[String] = []
	var a: MatchState = _play(log_a, prints_a)
	var b: MatchState = _play(log_b, prints_b)
	assert_eq(prints_a.size(), log_a.size() + 1)
	assert_gt(prints_a.size(), 100, "a long script")
	assert_eq(prints_a, prints_b, "same fingerprint after every action")
	assert_eq(log_a, log_b)
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))


func test_the_script_really_exercises_the_new_rules() -> void:
	var log: Array[Dictionary] = []
	var prints: Array[String] = []
	var state: MatchState = _play(log, prints)
	var kinds: Dictionary = {}
	for a: Dictionary in log:
		kinds[a["kind"]] = (kinds.get(a["kind"], 0) as int) + 1
	for k: String in ["buy", "sell", "ready", "start_round", "move", "use_item", "fire", "pass"]:
		assert_true(kinds.has(k), "script uses %s" % k)
	assert_gt(state.round_index, 0, "more than one round")
	var distinct: Dictionary = {}
	for f: String in prints:
		distinct[f] = true
	assert_gt(distinct.size(), prints.size() * 3 / 4, "the state keeps evolving")
	var total_money: int = 0
	var total_damage: int = 0
	for t: TankState in state.tanks:
		total_money += t.money
		total_damage += t.damage_dealt
	assert_ne(total_money, 3 * 40000, "money moved")
	assert_gt(total_damage, 0, "somebody was hurt")


func test_replaying_the_action_log_reproduces_every_fingerprint() -> void:
	var log: Array[Dictionary] = []
	var prints: Array[String] = []
	_play(log, prints)
	var state: MatchState = Simulation.new_match(_settings())
	var got: Array[String] = [Simulation.fingerprint(state)]
	for a: Dictionary in log:
		_apply_entry(state, Simulation.normalize_action(JSON.parse_string(JSON.stringify(a))))
		got.append(Simulation.fingerprint(state))
	assert_eq(got, prints, "a replay from JSON-decoded actions matches step for step")


func test_save_and_load_in_the_middle_continues_identically() -> void:
	var full_log: Array[Dictionary] = []
	var full_prints: Array[String] = []
	var full: MatchState = _play(full_log, full_prints)
	var cut: int = 60
	var log: Array[Dictionary] = []
	var prints: Array[String] = []
	var half: MatchState = _play(log, prints, cut)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(half, log))
	assert_true(res["ok"], str(res["error"]))
	var resumed: MatchState = res["state"]
	assert_eq(Simulation.fingerprint(resumed), Simulation.fingerprint(half))
	# continue both with the remaining script entries
	var rest: Array[Dictionary] = full_log.slice(log.size())
	assert_gt(rest.size(), 20)
	for i: int in range(rest.size()):
		_apply_entry(resumed, rest[i])
		assert_eq(Simulation.fingerprint(resumed), full_prints[log.size() + 1 + i], "step %d after load" % i)
	assert_eq(Simulation.fingerprint(resumed), Simulation.fingerprint(full))


func test_state_copy_stays_in_lockstep_through_shop_and_play() -> void:
	var log: Array[Dictionary] = []
	var prints: Array[String] = []
	var s: MatchState = _play(log, prints, 12)
	var copy: MatchState = s.duplicate_state()
	for a: Dictionary in _play_tail(s):
		if a["kind"] == "start_round":
			_apply_entry(s, a)
			_apply_entry(copy, a)
		else:
			assert_eq(Simulation.apply_action(s, a), Simulation.apply_action(copy, a))
		assert_eq(Simulation.fingerprint(s), Simulation.fingerprint(copy))


func _play_tail(s: MatchState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: TankState in s.tanks:
		if not t.ready:
			out.append(U.ready(t.id))
	out.append(START)
	return out


func test_performance_numbers() -> void:
	var s: MatchState = U.started_match(_settings())
	s.tanks[0].set_stock("pulse_missile", 5)
	s.current_tank = 0
	var worst: int = 0
	for i: int in range(5):
		s.current_tank = 0
		var t0: int = Time.get_ticks_usec()
		var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450 + i * 20, 800))
		worst = maxi(worst, Time.get_ticks_usec() - t0)
		assert_gt(ev.size(), 3)
	var f0: int = Time.get_ticks_usec()
	Simulation.fingerprint(s)
	var fp_us: int = Time.get_ticks_usec() - f0
	print("PERF M3 apply_action(fire) worst of 5: %.1f ms, fingerprint: %.1f ms" % [worst / 1000.0, fp_us / 1000.0])
	assert_lt(worst, 30000, "apply_action under 30 ms")
	assert_lt(fp_us, 30000, "fingerprint under 30 ms")
