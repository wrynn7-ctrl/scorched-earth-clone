@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 3: the CPUs in team matches (sections 39-41). 1000+ CPU decisions at every level, each validated
## and applied:
##  - never an illegal action, never more than 3 calls in a turn;
##  - never deliberately aims at a teammate (the decision's target is an enemy; shells that come down on a
##    teammate standing clear of every enemy are counted and must stay under 1% of the shots);
##  - pass rate <= 5% outside sudden death, ZERO passes in sudden death (rounds are fast-forwarded into it);
##  - self hits 0; teammate-hit shots <= 6% (Easy / Normal) and <= 2% (Hard / Expert) with friendly fire on;
##  - decisions equal on a deep copy and after a SaveCodec round trip (sampled).
## Plus the 'enemy next to a teammate' sweep, and 2v2 matches with CPUs only on one team and scripted bots only
## on the other, played to the end under the spec audit of qa_m6.gd.
## The statistics are printed in the log.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")
const QaAi = preload("res://tests/qa/qa_ai.gd")

const LEVEL_NAMES: Array[String] = ["", "Easy", "Normal", "Hard", "Expert"]
const SHOTS_PER_LEVEL: int = 320
const MAX_MATCHES: int = 60
const ALLY_MAX_PERMILLE_EASY: int = 60
const ALLY_MAX_PERMILLE_HARD: int = 20
const PASS_MAX_PERCENT: int = 5

var _by_level: Dictionary = {}
var _setups: Dictionary = {}


func _blank() -> Dictionary:
	return {"decisions": 0, "fires": 0, "passes": 0, "sd_decisions": 0, "sd_passes": 0, "ally": 0, "ally_direct": 0,
			"self": 0, "self_fall": 0, "illegal": 0, "aimed_at_mate": 0, "bad_target": 0, "max_calls": 0, "det": 0,
			"det_fail": 0, "turn_end": 0, "spark_fallbacks": 0}


func _lv(level: int) -> Dictionary:
	if not _by_level.has(level):
		_by_level[level] = _blank()
	return _by_level[level]


func _settings(seed_value: int, ctrl: PackedInt32Array, teams: PackedInt32Array, ff: bool, rounds: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = ctrl.size()
	s.rounds = rounds
	s.controllers = ctrl
	s.teams = teams
	s.friendly_fire = ff
	s.wind_max = 100
	return s


## Plays a match where every seat is a CPU (the level in `controllers`). `rush` fast-forwards each round with
## passes until the next turn is a sudden-death turn. Fills `_by_level` and returns {state, errors}.
func _cpu_match(st: MatchSettings, rush: bool, tag: String, det_every: int) -> Dictionary:
	var state: MatchState = Simulation.new_match(st)
	var s: MatchSettings = state.settings
	var errors: Array[String] = []
	var log: Array[Dictionary] = []
	var guard: int = 0
	var calls: int = 0
	var last_key: int = -1
	var decisions: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and guard < 1500:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			for t: TankState in state.tanks:
				for a: Dictionary in AiPlayer.shop_actions(state, t.id):
					Simulation.apply_action(state, a)
			if Simulation.start_round(state).is_empty():
				errors.append("%s: start_round failed" % tag)
				break
			last_key = -1
			if rush:
				var thr: int = Simulation.sudden_death_turn(s)
				while state.phase == SimConstants.PHASE_AIM and state.turn_number < thr - 1:
					Simulation.apply_action(state, {"kind": "pass", "tank": state.current_tank})
			continue
		var id: int = state.current_tank
		var me: TankState = state.tanks[id]
		var level: int = state.settings.controllers[id]
		var rec: Dictionary = _lv(level)
		var key: int = state.round_index * 100000 + state.turn_number
		calls = calls + 1 if key == last_key else 1
		last_key = key
		rec["max_calls"] = maxi(rec["max_calls"] as int, calls)
		var picked: TankState = AiTargets.pick(state, me, level)
		if picked == null or picked.team == me.team or not picked.alive:
			rec["bad_target"] += 1
		var sudden: bool = state.turn_number >= Simulation.sudden_death_turn(s)
		var action: Dictionary = AiPlayer.next_action(state, id)
		decisions += 1
		rec["decisions"] += 1
		if sudden:
			rec["sd_decisions"] += 1
		var verr: String = Simulation.validate_action(state, action)
		if verr != "":
			rec["illegal"] += 1
			errors.append("%s: illegal %s -> %s" % [tag, str(action), verr])
			break
		if det_every > 0 and decisions % det_every == 0:
			rec["det"] += 1
			var copy_action: Dictionary = AiPlayer.next_action(state.duplicate_state(), id)
			var loaded: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
			var load_action: Dictionary = AiPlayer.next_action(loaded["state"], id) if loaded["ok"] else {}
			if copy_action != action or load_action != action:
				rec["det_fail"] += 1
				errors.append("%s: decision differs on a copy / after a save: %s vs %s vs %s" % [tag, str(action), str(copy_action), str(load_action)])
		var enemies_before: Array[Vector2i] = []
		var mates_before: Array[Vector2i] = []
		for t: TankState in state.tanks:
			if t.alive and t.id != id:
				(mates_before if t.team == me.team else enemies_before).append(Vector2i(t.x, t.id))
		var before: Dictionary = M6.snap(state)
		var ev: Array[Dictionary] = Simulation.apply_action(state, action)
		log.append(action)
		var audit: Array[String] = M6.audit(before, state, action, ev)
		if not audit.is_empty():
			errors.append("%s: audit after %s:\n%s" % [tag, str(action), "\n".join(audit.slice(0, 4))])
		var kind: String = action["kind"]
		if kind == "pass":
			rec["passes"] += 1
			if sudden:
				rec["sd_passes"] += 1
		if kind == "fire":
			rec["fires"] += 1
			if action["weapon"] == "spark_dart" and (action["power"] as int) == SimConstants.DEFAULT_POWER \
					and (action["angle"] as int) in [SimConstants.DEFAULT_ANGLE_LEFT, SimConstants.DEFAULT_ANGLE_RIGHT]:
				rec["spark_fallbacks"] += 1
			_note_shot(rec, ev, id, me.team, state, enemies_before, mates_before)
		if kind == "fire" or kind == "pass" or (kind == "use_item" and action["item"] == "nanorepair_kit"):
			rec["turn_end"] += 1
	if guard >= 1500:
		errors.append("%s: match did not finish" % tag)
	return {"state": state, "errors": errors}


func _note_shot(rec: Dictionary, ev: Array[Dictionary], id: int, team: int, state: MatchState,
		enemies_before: Array[Vector2i], mates_before: Array[Vector2i]) -> void:
	var ally: bool = false
	var ally_direct: bool = false
	for e: Dictionary in ev:
		if e["type"] != "damage" or e["cause"] == "sudden_death":
			continue
		var victim: int = e["tank"]
		if victim == id:
			if e["cause"] == "fall":
				rec["self_fall"] += 1
			else:
				rec["self"] += 1
				break
		elif state.tanks[victim].team == team:
			ally = true
			if e["cause"] != "fall":
				ally_direct = true
	if ally and not state.settings.friendly_fire:
		ally = false  # the core ignores the hit; nothing happened
		ally_direct = false
	if ally:
		rec["ally"] += 1
	if ally_direct:
		rec["ally_direct"] += 1
	# Deliberately at a teammate: the first shell came down within 14 cells of a teammate that stands more
	# than 60 cells from every enemy, while an enemy was on the field.
	if enemies_before.is_empty() or mates_before.is_empty():
		return
	for e: Dictionary in ev:
		if e["type"] != "projectile_end":
			continue
		var reason: String = e["reason"]
		if reason != "terrain" and reason != "tank" and reason != "shield":
			return
		var x: int = e["x"]
		for m: Vector2i in mates_before:
			if absi(m.x - x) <= 14:
				var clear: bool = true
				for en: Vector2i in enemies_before:
					if absi(en.x - m.x) <= 60:
						clear = false
				if clear:
					rec["aimed_at_mate"] += 1
					var det: Array = rec.get("aimed_cases", []) as Array
					det.append("shooter x=%d impact x=%d mate x=%d enemies %s wind %d" % [state.tanks[id].x, x, m.x, str(enemies_before), state.wind])
					rec["aimed_cases"] = det
		return


func _row(level: int) -> String:
	var r: Dictionary = _lv(level)
	return "%-7s decisions %4d (turn-ending %4d) fires %4d passes %2d (%s) | SD decisions %3d, SD passes %d | teammate-hit shots %2d (%s of fires; direct %d) | self hits %d (+%d falls) | aimed-at-teammate %d | illegal %d | bad targets %d | max calls %d | det checks %d (fail %d) | spark fallbacks %d" % [
			LEVEL_NAMES[level], r["decisions"], r["turn_end"], r["fires"], r["passes"], M6.pct10(r["passes"] as int, r["turn_end"] as int),
			r["sd_decisions"], r["sd_passes"], r["ally"], M6.pct10(r["ally"] as int, r["fires"] as int), r["ally_direct"],
			r["self"], r["self_fall"], r["aimed_at_mate"], r["illegal"], r["bad_target"], r["max_calls"], r["det"], r["det_fail"],
			r["spark_fallbacks"]]


# --- the big statistics run -----------------------------------------------------------------------------

func test_cpu_decisions_in_team_matches_are_legal_enemy_aimed_and_safe() -> void:
	var t0: int = Time.get_ticks_msec()
	var all_errors: Array[String] = []
	var setups: Array[Array] = [
		["2v2", PackedInt32Array([0, 1, 0, 1])], ["2v2 adjacent", PackedInt32Array([0, 0, 1, 1])],
		["3v1", PackedInt32Array([0, 0, 0, 1])], ["1v1", PackedInt32Array([0, 1])],
		["2v2v2", PackedInt32Array([0, 1, 2, 0, 1, 2])],
	]
	var matches: int = 0
	var m: int = 0
	while matches < MAX_MATCHES:
		var done: bool = true
		for level: int in range(1, 5):
			if (_lv(level)["fires"] as int) < SHOTS_PER_LEVEL * M6.scale():
				done = false
		if done:
			break
		var setup: Array = setups[m % setups.size()]
		var teams: PackedInt32Array = setup[1]
		var n: int = teams.size()
		var ctrl := PackedInt32Array()
		for i: int in range(n):
			ctrl.append(1 + ((i + m) % 4) if m % 3 != 2 else 1 + (m / 3) % 4)
		var ff: bool = m % 5 != 4  # friendly fire on in 4 of 5 matches (the limits are for friendly fire on)
		var st: MatchSettings = _settings(31000 + m * 7, ctrl, teams, ff, 2)
		var r: Dictionary = _cpu_match(st, false, "match %d %s ff=%s ctrl=%s" % [m, str(setup[0]), str(ff), str(ctrl)], 9)
		all_errors.append_array(r["errors"] as Array[String])
		var s: String = setup[0]
		_setups[s] = (_setups.get(s, 0) as int) + 1
		matches += 1
		m += 1
	gut.p("M6 AI natural matches: %d matches in %d ms, setups %s" % [matches, Time.get_ticks_msec() - t0, str(_setups)])
	var tot_decisions: int = 0
	var tot_passes: int = 0
	var tot_turn_end: int = 0
	for level: int in range(1, 5):
		gut.p("   " + _row(level))
		var r2: Dictionary = _lv(level)
		tot_decisions += r2["decisions"] as int
		tot_passes += r2["passes"] as int
		tot_turn_end += r2["turn_end"] as int
		assert_gte(r2["fires"], SHOTS_PER_LEVEL, "level %d: at least %d shots" % [level, SHOTS_PER_LEVEL])
		assert_eq(r2["illegal"], 0, "level %d: no illegal action" % level)
		assert_eq(r2["bad_target"], 0, "level %d: the target is always an enemy" % level)
		# A shell that comes down on a teammate standing clear of every enemy is a heuristic (a blocked or wild
		# shot looks the same); the exact guarantee is bad_target == 0 above. Allow 1% noise.
		assert_lte((r2["aimed_at_mate"] as int) * 100, (r2["fires"] as int), "level %d: shells landing on a lone teammate" % level)
		assert_eq(r2["self"], 0, "level %d: no self hit" % level)
		assert_lte(r2["max_calls"], 3, "level %d: a turn ends within 3 calls" % level)
		assert_eq(r2["det_fail"], 0, "level %d: decisions are the same on a copy and after a save" % level)
		var limit: int = ALLY_MAX_PERMILLE_HARD if level >= 3 else ALLY_MAX_PERMILLE_EASY
		assert_lte((r2["ally"] as int) * 1000, limit * (r2["fires"] as int),
				"level %d: teammate-hit shots %d of %d fires over %d per mille" % [level, r2["ally"], r2["fires"], limit])
	for level: int in range(1, 5):
		for c: String in (_lv(level).get("aimed_cases", []) as Array):
			gut.p("   aimed-at-teammate case, level %d: %s" % [level, c])
	gut.p("   total: %d CPU decisions, passes %d of %d turn-ending decisions (%s)" % [tot_decisions, tot_passes, tot_turn_end,
			M6.pct10(tot_passes, tot_turn_end)])
	assert_gt(tot_decisions, 1000, "more than 1000 CPU decisions")
	assert_lte(tot_passes * 100, PASS_MAX_PERCENT * tot_turn_end, "passes <= 5% of turns")
	assert_eq(all_errors.size(), 0, "\n".join(all_errors.slice(0, 5)))


func test_cpus_never_pass_in_sudden_death_and_never_hurt_themselves() -> void:
	var before: Dictionary = {}
	for level: int in range(1, 5):
		before[level] = (_lv(level)["sd_decisions"] as int)
	var errors: Array[String] = []
	var t0: int = Time.get_ticks_msec()
	var setups: Array[PackedInt32Array] = [PackedInt32Array([0, 1, 0, 1]), PackedInt32Array([0, 0, 1]),
			PackedInt32Array([0, 1, 2, 0, 1, 2]), PackedInt32Array([0, 1]), PackedInt32Array([0, 0, 0, 1])]
	var sd_total: int = 0
	var passes: int = 0
	var rushed: Array[Dictionary] = []
	for m: int in range(12):
		var teams: PackedInt32Array = setups[m % setups.size()]
		var ctrl := PackedInt32Array()
		for i: int in range(teams.size()):
			ctrl.append(1 + (i + m) % 4)
		var st: MatchSettings = _settings(52000 + m * 11, ctrl, teams, m % 3 != 0, 2)
		var r: Dictionary = _cpu_match(st, true, "rush %d teams %s ctrl %s" % [m, str(teams), str(ctrl)], 0)
		errors.append_array(r["errors"] as Array[String])
		rushed.append({"m": m, "phase": (r["state"] as MatchState).phase})
	for level: int in range(1, 5):
		var rec: Dictionary = _lv(level)
		var sd: int = (rec["sd_decisions"] as int) - (before[level] as int)
		sd_total += sd
		passes += rec["sd_passes"] as int
	gut.p("M6 AI sudden death: %d rounds fast-forwarded in %d ms; %d CPU decisions taken in sudden death, %d passes" % [
			rushed.size() * 2, Time.get_ticks_msec() - t0, sd_total, passes])
	for level: int in range(1, 5):
		gut.p("   " + _row(level))
		assert_eq(_lv(level)["sd_passes"], 0, "level %d: zero passes in sudden death" % level)
		assert_eq(_lv(level)["self"], 0, "level %d: no self hits in sudden death either" % level)
		assert_eq(_lv(level)["illegal"], 0)
	assert_gt(sd_total, 150, "plenty of sudden-death decisions were exercised")
	assert_eq(errors.size(), 0, "\n".join(errors.slice(0, 5)))
	for r: Dictionary in rushed:
		assert_eq(r["phase"], SimConstants.PHASE_MATCH_OVER, "rush match %d finished" % r["m"])


# --- an enemy next to a teammate -------------------------------------------------------------------------

var _flat: MatchState = null


func _field(level: int, mate_x: int, enemy_x: int, ff: bool, wind: int) -> MatchState:
	if _flat == null:
		_flat = SimTestUtil.flat_state(3)
	var s: MatchState = _flat.duplicate_state()
	var xs: Array[int] = [300, mate_x, enemy_x]
	var teams: Array[int] = [0, 0, 1]
	var ctrl := PackedInt32Array()
	var tl := PackedInt32Array()
	for i: int in range(3):
		s.tanks[i].x = xs[i]
		s.tanks[i].y = TankState.rest_y(s.terrain, xs[i])
		s.tanks[i].team = teams[i]
		s.tanks[i].set_stock("pulse_missile", 20 if i == 0 else 0)
		ctrl.append(level if i == 0 else SimConstants.CTRL_HUMAN)
		tl.append(teams[i])
	s.settings.controllers = ctrl
	s.settings.teams = tl
	s.settings.friendly_fire = ff
	s.wind = wind
	s.current_tank = 0
	return s


func test_enemy_next_to_a_teammate_sweep() -> void:
	var rows: PackedStringArray = PackedStringArray()
	var cases: int = 0
	var self_hits: int = 0
	var illegal: int = 0
	var off_passes: int = 0
	var on_passes: int = 0
	var on_ally: int = 0
	var on_turns: int = 0
	var off_turns: int = 0
	var enemy_hit_off: int = 0
	for level: int in range(1, 5):
		for ff: bool in [true, false]:
			var passes: int = 0
			var ally: int = 0
			var enemy_hits: int = 0
			var turns: int = 0
			for d: int in [6, 12, 20, 30, 50]:
				for side: int in [-1, 1]:
					for wind: int in [0, 60, -60]:
						var enemy_x: int = 1000
						var s: MatchState = _field(level, enemy_x + side * d, enemy_x, ff, wind)
						var turn: Dictionary = QaAi.play_turn(s, 0)
						cases += 1
						turns += 1
						if not (turn["errors"] as Array).is_empty():
							illegal += 1
							continue
						var act: Dictionary = (turn["actions"] as Array)[(turn["actions"] as Array).size() - 1]
						if act["kind"] == "pass":
							passes += 1
						var ev: Array[Dictionary] = turn["events"]
						if QaAi.damage_to(ev, 0) > 0:
							self_hits += 1
						if QaAi.damage_to(ev, 1) > 0 and ff:
							ally += 1
						if QaAi.damage_to(ev, 2) > 0:
							enemy_hits += 1
			rows.append("%-6s ff %-3s: %2d turns, passes %2d, teammate hit %2d, enemy hit %2d" % [LEVEL_NAMES[level], "on" if ff else "off",
					turns, passes, ally, enemy_hits])
			if ff:
				on_passes += passes
				on_ally += ally
				on_turns += turns
			else:
				off_passes += passes
				off_turns += turns
				enemy_hit_off += enemy_hits
	gut.p("M6 AI enemy next to a teammate (teammate 6..50 cells beside the enemy, both sides, wind 0/+-60):\n      %s" % "\n      ".join(rows))
	assert_eq(illegal, 0, "every decision legal")
	assert_eq(self_hits, 0, "no self hit")
	assert_eq(off_passes, 0, "friendly fire off: a teammate beside the enemy is no reason to pass")
	assert_gt(enemy_hit_off, off_turns / 4, "friendly fire off: the CPUs really hit the enemy next to their teammate")
	gut.p("   friendly fire on: passes %d of %d, teammate hits %d" % [on_passes, on_turns, on_ally])


# --- CPU team against bot team ---------------------------------------------------------------------------

func test_cpu_team_against_a_bot_team_runs_to_the_end_under_audit() -> void:
	var errors: Array[String] = []
	var stats: PackedStringArray = PackedStringArray()
	var finished: int = 0
	var t0: int = Time.get_ticks_msec()
	for k: int in range(8):
		var ff: bool = k % 2 == 0
		var teams: PackedInt32Array = PackedInt32Array([0, 1, 0, 1]) if k % 4 < 2 else PackedInt32Array([0, 0, 1, 1])
		var cpu_team: int = 0
		var ctrl := PackedInt32Array()
		for i: int in range(4):
			ctrl.append((1 + (k + i) % 4) if teams[i] == cpu_team else SimConstants.CTRL_HUMAN)
		var st: MatchSettings = _settings(77000 + k, ctrl, teams, ff, 3)
		var state: MatchState = Simulation.new_match(st)
		var rng := Rng.new(st.seed ^ 0xBEEF)
		var log: Array[Dictionary] = []
		var turns: int = 0
		var round_turns: Array[int] = []
		var cur_round: int = 0
		var guard: int = 0
		while state.phase != SimConstants.PHASE_MATCH_OVER and guard < 1200:
			guard += 1
			if state.phase == SimConstants.PHASE_SHOP:
				M6.shop_phase(state, rng, log)
				Simulation.start_round(state)
				cur_round = 0
				continue
			var id: int = state.current_tank
			var action: Dictionary = AiPlayer.next_action(state, id) if state.settings.controllers[id] != SimConstants.CTRL_HUMAN \
					else M6.human_action(state, rng, 30, 25)
			if Simulation.validate_action(state, action) != "":
				errors.append("match %d: illegal %s" % [k, str(action)])
				break
			var before: Dictionary = M6.snap(state)
			var ev: Array[Dictionary] = Simulation.apply_action(state, action)
			var audit: Array[String] = M6.audit(before, state, action, ev)
			if not audit.is_empty():
				errors.append("match %d: %s" % [k, "\n".join(audit.slice(0, 3))])
				break
			if action["kind"] == "fire" or action["kind"] == "pass":
				turns += 1
				cur_round += 1
			if not QaUtil.find(ev, "round_end").is_empty():
				round_turns.append(cur_round)
		if state.phase == SimConstants.PHASE_MATCH_OVER:
			finished += 1
			var order: Array[int] = Simulation.team_standings(state)
			assert_eq(order, M6.expected_team_standings(state), "match %d final team standings" % k)
			var wins: Array[int] = []
			for t: int in order:
				for tk: TankState in state.tanks:
					if tk.team == t:
						wins.append(tk.round_wins)
						break
			stats.append("match %d ff %s ctrl %s: %d turns, rounds %s, team order %s, wins %s" % [k, str(ff), str(ctrl), turns,
					str(round_turns), str(order), str(wins)])
		else:
			errors.append("match %d did not finish" % k)
	gut.p("M6 AI CPU team vs bot team (%d ms):\n      %s" % [Time.get_ticks_msec() - t0, "\n      ".join(stats)])
	assert_eq(errors.size(), 0, "\n".join(errors.slice(0, 4)))
	assert_eq(finished, 8, "all matches ran to the end")
