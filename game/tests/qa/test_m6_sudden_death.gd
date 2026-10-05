@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 2: sudden death (section 40). Exact threshold turn for 2..8 tanks (every start rotation), the threshold
## using num_tanks and not the living count, one event per round, the 5/10/15/20/25/25 drain bypassing shields
## and paying nothing, the drain finishing the last enemy / a whole team / everybody, wells and terrain changes
## that outlive the shooter, a new round resetting the counter, love mode never draining, the counter surviving a
## save made mid-sudden-death, and tampered saves that must come back as invalid_state.
## Each pass / shot goes through the spec audit in qa_m6.gd.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

const AMOUNTS: Array[int] = [5, 10, 15, 20, 25, 25, 25]


func _started(n: int, teams: Array[int], ff: bool, rounds: int, seed_value: int) -> MatchState:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = n
	s.rounds = rounds
	s.wind_max = 0
	if not teams.is_empty():
		s.teams = PackedInt32Array(teams)
	s.friendly_fire = ff
	return QaUtil.started_match(s)


## Applies a pass for the current tank with the full audit; returns the events.
func _do_pass(state: MatchState, tag: String) -> Array[Dictionary]:
	var action: Dictionary = {"kind": "pass", "tank": state.current_tank}
	var before: Dictionary = M6.snap(state)
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	var errs: Array[String] = M6.audit(before, state, action, ev)
	errs.append_array(M3.check_state(state))
	var v: String = StateSerial.validate(state)
	if v != "":
		errs.append("StateSerial.validate: " + v)
	assert_eq(errs.size(), 0, "%s (turn %d):\n%s" % [tag, state.turn_number, "\n".join(errs.slice(0, 6))])
	return ev


## Makes the next pass by `state.current_tank` complete the threshold turn, wrapping the turn order, with `cycles`
## drains already done: current tank = the last living tank, turn_number = the turn before a wrap.
func _at_wrap(state: MatchState, cycles: int) -> void:
	var last: int = 0
	for t: TankState in state.tanks:
		if t.alive:
			last = t.id
	state.current_tank = last
	state.sudden_death_cycles = cycles
	state.turn_number = Simulation.sudden_death_turn(state.settings) + cycles * state.tanks.size() - 1


func test_threshold_table() -> void:
	var s := MatchSettings.new()
	for n: int in range(2, 9):
		s.num_tanks = n
		assert_eq(Simulation.sudden_death_turn(s), 10 * n, "%d tanks -> %d turns" % [n, 10 * n])
	assert_eq([Simulation.sudden_death_amount(0), Simulation.sudden_death_amount(1), Simulation.sudden_death_amount(5),
			Simulation.sudden_death_amount(6), Simulation.sudden_death_amount(100)], [0, 5, 25, 25, 25] as Array[int])


func test_exact_threshold_turn_and_drain_sequence_for_every_tank_count_and_start_rotation() -> void:
	var rounds_run: int = 0
	var report: PackedStringArray = PackedStringArray()
	for n: int in range(2, 9):
		var teams: Array[int] = []
		if n >= 4 and n % 2 == 0:
			for i: int in range(n):
				teams.append(i % 2)
		var state: MatchState = _started(n, teams, n % 4 == 0, 3, 900 + n)
		for round_i: int in range(3):
			var start: int = state.current_tank
			assert_eq(start, round_i % n, "n=%d round %d starts with tank %d" % [n, round_i, round_i % n])
			var thr: int = 10 * n
			var sd_events: int = 0
			var sd_turn: int = -1
			var drains: Array[int] = []
			var drain_turns: Array[int] = []
			var guard: int = 0
			while state.phase == SimConstants.PHASE_AIM and guard < 40 * n:
				guard += 1
				var ev: Array[Dictionary] = _do_pass(state, "n=%d round %d" % [n, round_i])
				for e: Dictionary in ev:
					if e["type"] == "sudden_death":
						sd_events += 1
						sd_turn = state.turn_number
					if e["type"] == "damage" and e["cause"] == "sudden_death" and (drains.is_empty() or drain_turns.back() != state.turn_number):
						drains.append(e["amount"])
						drain_turns.append(state.turn_number)
			assert_lt(guard, 40 * n, "n=%d round %d ends" % [n, round_i])
			assert_eq(sd_events, 1, "n=%d round %d: one sudden_death event" % [n, round_i])
			assert_eq(sd_turn, thr, "n=%d round %d: the event comes at turn %d" % [n, round_i, thr])
			assert_eq(drains, [5, 10, 15, 20, 25, 25] as Array[int], "n=%d round %d: drain amounts" % [n, round_i])
			var first: int = thr + ((n - start) % n)
			assert_eq(drain_turns[0], first, "n=%d start %d: the first drain is the first wrap at or after the threshold" % [n, start])
			for k: int in range(drain_turns.size()):
				assert_eq(drain_turns[k], first + k * n, "n=%d: one drain per orbit" % n)
			# Everybody had the same 100 HP and nothing else happened: all die together at the 6th drain: a draw.
			for t: TankState in state.tanks:
				assert_false(t.alive, "n=%d: all tanks died in the 6th cycle" % n)
				assert_eq(t.round_wins, 0, "a draw gives no round win")
			report.append("n=%d start %d: event@%d drains@%s" % [n, start, sd_turn, str(drain_turns)])
			rounds_run += 1
			if state.phase == SimConstants.PHASE_SHOP:
				QaUtil.shop_and_ready(state)
				Simulation.start_round(state)
				assert_eq(state.sudden_death_cycles, 0, "n=%d: a new round resets the counter" % n)
				assert_eq(state.turn_number, 0)
	gut.p("SUDDEN DEATH thresholds: %d rounds; %s" % [rounds_run, " | ".join(report)])


func test_threshold_uses_num_tanks_not_the_living_count() -> void:
	for kill: int in [1, 3, 5, 6]:
		var state: MatchState = _started(8, [], true, 1, 7700 + kill)
		for i: int in range(8 - kill, 8):
			state.tanks[i].health = 0
			state.tanks[i].alive = false
		if state.tanks[state.current_tank].alive == false:
			state.current_tank = 0
		var living: int = 8 - kill
		var events_at: int = -1
		var guard: int = 0
		while state.phase == SimConstants.PHASE_AIM and guard < 400:
			guard += 1
			var ev: Array[Dictionary] = _do_pass(state, "8 tanks, %d living" % living)
			if QaUtil.find(ev, "sudden_death").size() > 0:
				events_at = state.turn_number
			if events_at < 0:
				assert_eq(state.sudden_death_cycles, 0, "no drain before the event")
				for t: TankState in state.tanks:
					if t.alive:
						assert_eq(t.health, 100, "nobody is hurt before the threshold (turn %d)" % state.turn_number)
		assert_eq(events_at, 80, "%d living of 8: the threshold is still turn 80 (10 x num_tanks), not %d" % [living, 10 * living])


func test_the_drain_bypasses_shields_and_pays_nothing() -> void:
	var state: MatchState = _started(4, [], true, 1, 4141)
	var money: Array[int] = []
	for t: TankState in state.tanks:
		t.shield_type = Catalog.index_of("ion_shield")
		t.shield_hp = 60
		money.append(t.money)
	_at_wrap(state, 0)
	for cycle: int in range(1, 4):
		var ev: Array[Dictionary] = _do_pass(state, "drain cycle %d" % cycle)
		for t: TankState in state.tanks:
			assert_eq(t.shield_hp, 60, "cycle %d: the shield is untouched" % cycle)
			assert_true(t.has_shield())
		assert_eq(QaUtil.find(ev, "money").size(), 0, "the drain pays nobody")
		assert_eq(QaUtil.find(ev, "shield_hit").size() + QaUtil.find(ev, "shield_down").size(), 0)
		var hp_expect: int = 100 - (5 if cycle == 1 else (15 if cycle == 2 else 30))
		for t: TankState in state.tanks:
			assert_eq(t.health, hp_expect, "cycle %d: every tank lost the cumulative drain" % cycle)
			assert_eq(t.money, money[t.id], "no money moved")
			assert_eq(t.kills, 0)
			assert_eq(t.damage_dealt, 0)
		_at_wrap(state, cycle)


func test_friendly_fire_off_does_not_protect_teammates_from_the_drain() -> void:
	var state: MatchState = _started(4, [0, 0, 1, 1], false, 1, 4242)
	_at_wrap(state, 0)
	var ev: Array[Dictionary] = _do_pass(state, "ff off drain")
	var hit: Array[int] = []
	for e: Dictionary in QaUtil.find(ev, "damage"):
		hit.append(e["tank"])
		assert_eq(e["cause"], "sudden_death")
	assert_eq(hit, [0, 1, 2, 3] as Array[int], "everyone, in id order")
	for t: TankState in state.tanks:
		assert_eq(t.health, 95)


func _setup_end(teams: Array[int], hp: Array[int]) -> MatchState:
	var state: MatchState = _started(hp.size(), teams, true, 3, 5150 + hp.size())
	for i: int in range(hp.size()):
		state.tanks[i].health = hp[i]
		state.tanks[i].alive = hp[i] > 0
	return state


func _finish(state: MatchState, tag: String) -> Dictionary:
	_at_wrap(state, 0)
	var ev: Array[Dictionary] = _do_pass(state, tag)
	var ends: Array[Dictionary] = QaUtil.find(ev, "round_end")
	assert_eq(ends.size(), 1, "%s: the round ends" % tag)
	return {"ev": ev, "end": ends[0] if ends.size() == 1 else {}}


func test_drain_kills_the_last_enemy() -> void:
	var state: MatchState = _setup_end([], [100, 5])
	var m0: int = state.tanks[0].money
	var r: Dictionary = _finish(state, "last enemy")
	assert_eq(r["end"]["winner"], 0)
	assert_eq(r["end"]["winner_team"], 0)
	assert_eq(state.tanks[0].round_wins, 1)
	assert_eq(state.tanks[0].money, m0 + 3500, "survive + win only")
	assert_eq(state.tanks[0].kills, 0, "the drain gives no kill credit")
	assert_eq(state.tanks[1].round_wins, 0)


func test_drain_kills_a_whole_team_at_once() -> void:
	var state: MatchState = _setup_end([0, 0, 1, 1], [100, 100, 5, 5])
	var m: Array[int] = []
	for t: TankState in state.tanks:
		m.append(t.money)
	var r: Dictionary = _finish(state, "whole team")
	assert_eq(r["end"]["winner"], 0)
	assert_eq(r["end"]["winner_team"], 0)
	assert_eq(state.tanks[0].money, m[0] + 3500)
	assert_eq(state.tanks[1].money, m[1] + 3500)
	assert_eq(state.tanks[2].money, m[2], "the losers get nothing")
	assert_eq(state.tanks[3].money, m[3])
	assert_eq([state.tanks[0].round_wins, state.tanks[1].round_wins, state.tanks[2].round_wins, state.tanks[3].round_wins], [1, 1, 0, 0] as Array[int])


func test_drain_wipes_out_the_winning_side_member_but_the_team_still_wins() -> void:
	# Team A = {0 (5 HP), 1 (100 HP)}, team B = {2 (5 HP)}: the drain kills 0 and 2; A wins and the dead tank 0
	# still gets the win (not the survive pay).
	var state: MatchState = _setup_end([0, 0, 1], [5, 100, 5])
	var m0: int = state.tanks[0].money
	var r: Dictionary = _finish(state, "member of the winning team dies in the same drain")
	assert_eq(r["end"]["winner"], 1)
	assert_eq(r["end"]["winner_team"], 0)
	assert_eq(state.tanks[0].money, m0 + 2500, "dead winner: win pay only")
	assert_eq(state.tanks[0].round_wins, 1)
	assert_false(state.tanks[0].alive)


func test_drain_killing_everyone_is_a_draw_with_no_pay() -> void:
	for teams: Array[int] in [[] as Array[int], [0, 0, 1, 1] as Array[int], [0, 1, 1, 2] as Array[int]]:
		var state: MatchState = _setup_end(teams, [5, 3, 1, 5])
		var m: Array[int] = []
		for t: TankState in state.tanks:
			m.append(t.money)
		var r: Dictionary = _finish(state, "everyone dies, teams %s" % str(teams))
		assert_eq(r["end"]["winner"], -1)
		assert_eq(r["end"]["winner_team"], -1)
		for t: TankState in state.tanks:
			assert_eq(t.money, m[t.id], "a draw pays nothing")
			assert_eq(t.round_wins, 0)
		var order: Array[String] = []
		for e: Dictionary in r["ev"]:
			order.append(e["type"])
		assert_eq(order.slice(order.size() - 6), ["damage", "tank_destroyed", "tank_destroyed", "tank_destroyed", "tank_destroyed", "round_end"] as Array[String],
				"drain damage in id order, then the deaths, then round_end")


func test_late_cycles_cap_at_25_and_kill_in_id_order() -> void:
	var state: MatchState = _setup_end([], [30, 100, 26, 25])
	_at_wrap(state, 7)  # cycles 8 next: still 25
	var ev: Array[Dictionary] = _do_pass(state, "cycle 8")
	var dead: Array[int] = []
	for e: Dictionary in QaUtil.find(ev, "tank_destroyed"):
		dead.append(e["tank"])
	assert_eq(dead, [3] as Array[int], "25 HP dies, 26 survives with 1")
	assert_eq(state.tanks[0].health, 5)
	assert_eq(state.tanks[2].health, 1)
	assert_eq(state.sudden_death_cycles, 8)


func test_wells_and_terrain_changes_outlive_the_shots_through_sudden_death() -> void:
	var state: MatchState = _started(3, [], true, 2, 6060)
	state.tanks[0].set_stock("singularity_seed", 2)
	state.tanks[0].set_stock("sludge_shell", 2)
	state.tanks[1].set_stock("inferno_gel", 2)
	state.tanks[2].set_stock("nova_core", 2)
	# A well that is still active when sudden death begins (threshold 30): placed through the real weapon.
	state.turn_number = 27
	var shots: Array[Dictionary] = [
		{"kind": "fire", "tank": state.current_tank, "angle": 450, "power": 520, "weapon": "singularity_seed"}]
	var thr: int = 30
	var well_seen: bool = false
	var guard: int = 0
	while state.phase == SimConstants.PHASE_AIM and guard < 80:
		guard += 1
		var a: Dictionary
		if not shots.is_empty() and state.current_tank == shots[0]["tank"]:
			a = shots.pop_front()
		elif state.turn_number == 28 and state.tanks[state.current_tank].stock_of("sludge_shell") > 0:
			a = {"kind": "fire", "tank": state.current_tank, "angle": 450, "power": 500, "weapon": "sludge_shell"}
		elif state.turn_number == 29 and state.tanks[state.current_tank].stock_of("inferno_gel") > 0:
			a = {"kind": "fire", "tank": state.current_tank, "angle": 1350, "power": 500, "weapon": "inferno_gel"}
		else:
			a = {"kind": "pass", "tank": state.current_tank}
		if Simulation.validate_action(state, a) != "":
			a = {"kind": "pass", "tank": state.current_tank}
		var before: Dictionary = M6.snap(state)
		var wells_before: int = state.wells.size()
		var ev: Array[Dictionary] = Simulation.apply_action(state, a)
		var errs: Array[String] = M6.audit(before, state, a, ev)
		errs.append_array(M3.check_state(state))
		var v: String = StateSerial.validate(state)
		if v != "":
			errs.append(v)
		assert_eq(errs.size(), 0, "turn %d %s:\n%s" % [state.turn_number, str(a), "\n".join(errs.slice(0, 5))])
		if state.wells.size() > 0 and state.turn_number >= thr:
			well_seen = true
		assert_gte(wells_before + 0, 0)
	assert_lt(guard, 80, "the round ended")
	assert_true(well_seen, "a well was still active at the start of sudden death")
	assert_eq(state.wells.size() > 0 or state.phase != SimConstants.PHASE_AIM, true)
	if state.phase == SimConstants.PHASE_SHOP:
		QaUtil.shop_and_ready(state)
		Simulation.start_round(state)
		assert_eq(state.wells.size(), 0, "a new round clears the wells")
		assert_eq(state.sudden_death_cycles, 0)


func test_a_well_expiring_in_the_drain_turn_is_dropped_after_the_drain() -> void:
	var state: MatchState = _started(2, [], true, 1, 2020)
	_at_wrap(state, 0)
	state.wells = [{"owner": 0, "x": 800, "y": 300, "expires_turn": Simulation.sudden_death_turn(state.settings)}]
	var ev: Array[Dictionary] = _do_pass(state, "well expires with the drain")
	var order: Array[String] = QaUtil.types(ev)
	var i_drain: int = order.find("damage")
	var i_off: int = order.find("well_off")
	assert_gte(i_drain, 0)
	assert_gte(i_off, 0, "the well is announced off")
	assert_lt(i_drain, i_off, "the drain comes before the well expiry")
	assert_eq(state.wells.size(), 0)


func test_love_mode_never_drains_even_far_past_the_threshold() -> void:
	var s := MatchSettings.new()
	s.seed = 77
	s.mode = SimConstants.MODE_LOVE
	s.controllers = PackedInt32Array([0, 0])
	var state: MatchState = Simulation.new_match(s)
	assert_eq(state.phase, SimConstants.PHASE_AIM)
	var types: Dictionary = {}
	for i: int in range(120):
		var ev: Array[Dictionary] = Simulation.apply_action(state, {"kind": "pass", "tank": state.current_tank})
		for e: Dictionary in ev:
			types[e["type"]] = true
		assert_eq(state.sudden_death_cycles, 0)
	assert_false(types.has("sudden_death"), "no sudden_death event in love mode")
	assert_false(types.has("damage"))
	assert_gt(state.turn_number, 100)
	for t: TankState in state.tanks:
		assert_eq(t.health, 100)
	assert_eq(state.phase, SimConstants.PHASE_AIM)
	# A love shot after the threshold still works and the validator accepts the state.
	assert_eq(StateSerial.validate(state), "")
	var heart: Dictionary = M5.heart(state.current_tank, 450, 500)
	assert_eq(Simulation.validate_action(state, heart), "")


# --- the cycle counter across a save -----------------------------------------------------------------

func test_the_cycle_counter_survives_a_save_made_mid_sudden_death() -> void:
	for ff: bool in [true, false]:
		var teams: Array[int] = [0, 1, 0]
		if not ff:
			teams = [0, 0, 1]
		var live: MatchState = _started(3, teams, ff, 1, 3030 if ff else 3031)
		_at_wrap(live, 0)
		var log: Array[Dictionary] = []
		var checkpoints: int = 0
		var guard: int = 0
		while live.phase == SimConstants.PHASE_AIM and guard < 60:
			guard += 1
			if live.sudden_death_cycles >= 1 and live.phase == SimConstants.PHASE_AIM and checkpoints < 3:
				var bytes: PackedByteArray = SaveCodec.encode(live, log)
				var dec: Dictionary = SaveCodec.decode(bytes)
				assert_true(dec["ok"], "mid-sudden-death save decodes: %s" % str(dec["error"]))
				if not dec["ok"]:
					return
				var loaded: MatchState = dec["state"]
				assert_eq(loaded.sudden_death_cycles, live.sudden_death_cycles, "the counter is saved")
				assert_eq(Simulation.fingerprint(loaded), Simulation.fingerprint(live))
				# Both continue in lockstep: same events, same next drain.
				var twin: MatchState = loaded
				var steps: int = 0
				var ref: MatchState = live.duplicate_state()
				while ref.phase == SimConstants.PHASE_AIM and twin.phase == SimConstants.PHASE_AIM and steps < 12:
					steps += 1
					var a: Dictionary = {"kind": "pass", "tank": ref.current_tank}
					var e1: Array[Dictionary] = Simulation.apply_action(ref, a)
					var e2: Array[Dictionary] = Simulation.apply_action(twin, a)
					assert_eq(QaUtil.events_digest(e1), QaUtil.events_digest(e2), "ff=%s: identical events after the load" % str(ff))
				assert_eq(Simulation.fingerprint(ref), Simulation.fingerprint(twin))
				assert_eq(ref.phase, twin.phase)
				checkpoints += 1
			var a2: Dictionary = {"kind": "pass", "tank": live.current_tank}
			_do_pass_logged(live, a2, log)
		assert_gte(checkpoints, 2, "ff=%s: saved in the middle of sudden death at least twice" % str(ff))


func _do_pass_logged(state: MatchState, a: Dictionary, log: Array[Dictionary]) -> void:
	var before: Dictionary = M6.snap(state)
	var ev: Array[Dictionary] = Simulation.apply_action(state, a)
	log.append(a)
	var errs: Array[String] = M6.audit(before, state, a, ev)
	assert_eq(errs.size(), 0, "\n".join(errs.slice(0, 4)))


func test_a_drain_after_a_load_uses_the_saved_counter_not_a_fresh_one() -> void:
	var state: MatchState = _started(2, [], true, 1, 818)
	_at_wrap(state, 2)  # two drains done: the next one is 15
	state.tanks[0].health = 60
	state.tanks[1].health = 60
	var loaded: MatchState = SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))["state"]
	assert_not_null(loaded)
	var ev: Array[Dictionary] = Simulation.apply_action(loaded, {"kind": "pass", "tank": loaded.current_tank})
	var amounts: Array[int] = []
	for e: Dictionary in QaUtil.find(ev, "damage"):
		amounts.append(e["amount"])
	assert_eq(amounts, [15, 15] as Array[int])
	assert_eq(loaded.sudden_death_cycles, 3)


# --- tampered saves ---------------------------------------------------------------------------------

## Encodes (re-sealing checksum and fingerprint) a tampered copy and returns the decode error ("" if accepted).
func _tampered(state: MatchState, mutate: Callable) -> String:
	var copy: MatchState = state.duplicate_state()
	mutate.call(copy)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(copy, [] as Array[Dictionary]))
	return "" if res["ok"] else (res["error"] as String)


func _base_state() -> MatchState:
	var s: MatchState = _started(4, [0, 0, 1, 1], true, 2, 9191)
	return s


func test_tampered_sudden_death_counters_are_invalid_state() -> void:
	var base: MatchState = _base_state()
	assert_eq(_tampered(base, func(_s: MatchState) -> void: pass), "", "control: the untouched state loads")
	var thr: int = 40
	# cycles before the threshold
	assert_eq(_tampered(base, func(s: MatchState) -> void:
		s.sudden_death_cycles = 1
		s.turn_number = 5), "invalid_state", "cycles > 0 at turn 5")
	assert_eq(_tampered(base, func(s: MatchState) -> void:
		s.sudden_death_cycles = 1
		s.turn_number = thr - 1), "invalid_state", "cycles > 0 one turn before the threshold")
	# the bound: at most one cycle per turn since the threshold, the wrap that reaches it counting
	for extra: int in [0, 1, 7, 12]:
		var turn: int = thr + extra
		assert_eq(_tampered(base, func(s: MatchState) -> void:
			s.turn_number = turn
			s.sudden_death_cycles = extra + 1), "", "cycles %d at turn %d is the maximum and is accepted" % [extra + 1, turn])
		assert_eq(_tampered(base, func(s: MatchState) -> void:
			s.turn_number = turn
			s.sudden_death_cycles = extra + 2), "invalid_state", "cycles %d at turn %d is one too many" % [extra + 2, turn])
	for bad: int in [-1, -2147483648, 1 << 30, 2147483647]:
		assert_eq(_tampered(base, func(s: MatchState) -> void:
			s.turn_number = thr + 3
			s.sudden_death_cycles = bad), "invalid_state", "cycles %d" % bad)
	# a counter in the pre-start shop
	var fresh: MatchState = Simulation.new_match(base.settings)
	assert_eq(_tampered(fresh, func(s: MatchState) -> void: s.sudden_death_cycles = 1), "invalid_state", "counter before round 0")


func test_tampered_teams_are_invalid_state() -> void:
	var base: MatchState = _base_state()
	var cases: Array[Array] = [
		["tank team differs from the settings", func(s: MatchState) -> void: s.tanks[0].team = 1],
		["tank team 3 where settings say 0", func(s: MatchState) -> void: s.tanks[1].team = 3],
		["settings.teams shorter than num_tanks", func(s: MatchState) -> void: s.settings.teams = PackedInt32Array([0, 0, 1])],
		["settings.teams longer than num_tanks", func(s: MatchState) -> void: s.settings.teams = PackedInt32Array([0, 0, 1, 1, 1])],
		["team value 4", func(s: MatchState) -> void:
			s.settings.teams = PackedInt32Array([0, 0, 1, 4])
			s.tanks[3].team = 4],
		["team value -1", func(s: MatchState) -> void:
			s.settings.teams = PackedInt32Array([0, 0, 1, -1])
			s.tanks[3].team = -1],
		["a single team", func(s: MatchState) -> void:
			s.settings.teams = PackedInt32Array([1, 1, 1, 1])
			for t: TankState in s.tanks:
				t.team = 1],
		["teams emptied but tanks keep their team", func(s: MatchState) -> void: s.settings.teams = PackedInt32Array()],
		["teams set but tanks use ids", func(s: MatchState) -> void:
			for t: TankState in s.tanks:
				t.team = t.id],
	]
	for c: Array in cases:
		assert_eq(_tampered(base, c[1] as Callable), "invalid_state", c[0] as String)
	# Positive controls: four teams for four tanks, friendly fire flipped, teams removed consistently.
	assert_eq(_tampered(base, func(s: MatchState) -> void:
		s.settings.teams = PackedInt32Array([3, 2, 1, 0])
		for t: TankState in s.tanks:
			t.team = s.settings.teams[t.id]), "", "four different teams are fine")
	assert_eq(_tampered(base, func(s: MatchState) -> void: s.settings.friendly_fire = false), "", "friendly fire is free")
	assert_eq(_tampered(base, func(s: MatchState) -> void:
		s.settings.teams = PackedInt32Array()
		for t: TankState in s.tanks:
			t.team = t.id), "", "no teams, team = id")


func test_tampered_love_plus_teams_and_flow_are_invalid_state() -> void:
	var s := MatchSettings.new()
	s.seed = 5
	s.mode = SimConstants.MODE_LOVE
	s.controllers = PackedInt32Array([0, 0])
	var love: MatchState = Simulation.new_match(s)
	assert_eq(_tampered(love, func(_x: MatchState) -> void: pass), "", "control: a love match loads")
	assert_eq(_tampered(love, func(x: MatchState) -> void:
		x.settings.teams = PackedInt32Array([0, 1])
		x.tanks[0].team = 0
		x.tanks[1].team = 1), "invalid_state", "love mode with teams")
	assert_eq(_tampered(love, func(x: MatchState) -> void:
		x.turn_number = 50
		x.sudden_death_cycles = 1), "invalid_state", "love mode with a sudden-death counter")
	# Flow: aim with a single team alive, and a finished round with two teams alive.
	var base: MatchState = _base_state()
	assert_eq(_tampered(base, func(x: MatchState) -> void:
		x.tanks[2].alive = false
		x.tanks[2].health = 0
		x.tanks[3].alive = false
		x.tanks[3].health = 0), "invalid_state", "aim phase with only teammates alive")
	assert_eq(_tampered(base, func(x: MatchState) -> void:
		x.tanks[2].alive = false
		x.tanks[2].health = 0
		x.tanks[3].alive = false
		x.tanks[3].health = 0
		x.current_tank = 0
		x.phase = SimConstants.PHASE_SHOP
		x.round_index = 0), "", "a finished round with one team alive is fine (shop)")
	assert_eq(_tampered(base, func(x: MatchState) -> void:
		x.phase = SimConstants.PHASE_SHOP), "invalid_state", "shop with two teams alive")
	assert_eq(_tampered(base, func(x: MatchState) -> void:
		x.tanks[2].alive = false
		x.tanks[2].health = 0
		x.tanks[3].alive = false
		x.tanks[3].health = 0
		x.tanks[0].alive = false
		x.tanks[0].health = 0
		x.current_tank = 1), "invalid_state", "the current tank is the only survivor of a one-team aim phase")
