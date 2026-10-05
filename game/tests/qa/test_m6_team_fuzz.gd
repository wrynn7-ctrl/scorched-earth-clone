@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 1: team fuzz. 200 seeded matches over 2-8 tanks with random team splits (2v2, 4v4, 7v1, 2v2v2, uneven,
## four teams, plus a few no-team controls), friendly fire on and off, human bots (that also shoot at their own
## teammates) mixed with CPUs of every level, free and full caps. After EVERY action the audit in qa_m6.gd
## (written from sections 39 and 40, not from the code) checks:
##  - the round ends exactly when at most one team lives; winner / winner_team; pay (survive to the living, win +
##    round_wins to the whole winning team alive or dead, nothing on a draw); standings and team_standings;
##  - friendly fire off: no teammate HP / shield / chute change from any cause, no money, no strip;
##  - friendly fire on: the teammate penalty only (no credit, no kill, no kills / damage_dealt);
##  - the sudden-death event / drain / cycle counter, shields bypassed, no money;
##  - the event field contract, the economy ledger and StateSerial.validate.
## Every 3rd match is replayed from its action log (same fingerprint) and also continued from a mid-match
## SaveCodec round trip; a save round trip is taken a few times per match.
## Failures name the match index and seed. QA_M6_SCALE=n runs n times as many matches.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")

const MATCHES: int = 200
const ROOT_SEED: int = 0x6D360001
const MAX_ERRS_PER_MATCH: int = 6

var _stats: Dictionary = {"actions": 0, "fires": 0, "passes": 0, "moves": 0, "items": 0, "round_ends": 0, "draws": 0,
		"team_wins": 0, "sudden": 0, "drains": 0, "drain_kills": 0, "matches_teams": 0, "matches_ff_off": 0,
		"matches_free": 0, "mate_hit_shots_ff_on": 0, "blocked_mate_blasts_ff_off": 0, "saves": 0, "replays": 0,
		"resumes": 0, "cpu_decisions": 0, "mate_repulsor_changed": 0, "illegal_bot": 0, "stalled": 0,
		"max_round_turns": 0, "audit_errors": 0}
var _weapons: Dictionary = {}
var _by_label: Dictionary = {}
var _audit_notes: Dictionary = {}
var _setup_log: Array[String] = []
var _t_audit: int = 0


## The first matches are the named setups the owner cares about (free ones, m % 5 == 0, stay within 4 tanks).
const NAMED: Array = [
	[0, 1, 0, 1], [0, 0, 0, 0, 1, 1, 1, 1], [0, 0, 1, 1, 2, 2], [0, 0, 0, 1, 0, 0, 0, 0], [0, 0, 0, 1, 1],
	[0, 0, 0, 1], [0, 1, 0, 1, 0, 1, 0, 1], [0, 0, 0, 0, 0, 0, 1], [0, 1, 2, 0, 1, 2], [],
	[0, 0, 1, 1], [0, 1, 2, 3, 0, 1, 2, 3], [0, 0, 0, 1, 1, 1], [1, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 1, 1, 1],
	[0, 0, 1], [0, 0, 0, 0, 0, 1, 1, 1], [0, 0, 0, 0, 1, 1], [0, 0, 0, 0, 1], [],
	[0, 0, 1, 2], [0, 0, 0, 0, 0, 0, 1, 2], [0, 0, 1, 1, 2, 3], [0, 0, 0, 1, 1, 1, 2, 2],
]


func _settings(rng: Rng, m: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = rng.next_u32() + m
	var free: bool = m % 5 == 0
	s.full_unlocked = not free
	var named: Array[int] = []
	var has_named: bool = m < NAMED.size() and not (NAMED[m] as Array).is_empty()
	if has_named:
		for v: int in (NAMED[m] as Array):
			named.append(v)
	if has_named:
		s.num_tanks = named.size()
	elif free:
		s.num_tanks = rng.range_int(2, 4)
	elif m % 4 == 1:
		var forced_big: Array[int] = [8, 7, 6, 8, 5, 6]
		s.num_tanks = forced_big[(m / 4) % forced_big.size()]
	else:
		s.num_tanks = rng.range_int(2, 8)
	s.rounds = rng.range_int(1, 2) if s.num_tanks <= 4 else 1
	s.wind_max = [100, 0, 37, 100, 1][m % 5]
	s.start_money = [10000, 4000, 25000, 0, 100000][m % 5]
	s.friendly_fire = m % 2 == 0
	if has_named:
		s.teams = M6.relabel(rng, named)
	elif m % 10 != 9:  # one match in ten has no teams at all (control group)
		s.teams = M6.team_layout(rng, s.num_tanks, m / 2)
	var ctrl := PackedInt32Array()
	for _i: int in range(s.num_tanks):
		match m % 4:
			0:
				ctrl.append(SimConstants.CTRL_HUMAN)
			1:
				ctrl.append(rng.range_int(1, 4))
			2:
				ctrl.append(rng.range_int(0, 4))
			_:
				ctrl.append(rng.range_int(0, 2))
	s.controllers = ctrl
	return s


func test_200_team_matches_hold_every_audit() -> void:
	var rng := Rng.new(ROOT_SEED)
	var t0: int = Time.get_ticks_msec()
	var total: int = MATCHES * M6.scale()
	for m: int in range(total):
		var st: MatchSettings = _settings(rng, m)
		var tag: String = "match %d seed %d (%d tanks, teams %s, ff %s, rounds %d, full %s, ctrl %s)" % [m, st.seed,
				st.num_tanks, str(st.teams), str(st.friendly_fire), st.rounds, str(st.full_unlocked), str(st.controllers)]
		_play(m, st, tag, Rng.new(st.seed ^ 0x51ED))
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("M6 TEAM FUZZ: %d matches, %d actions in %d ms (audit %d ms)" % [total, _stats["actions"], ms, _t_audit / 1000])
	gut.p("   counters: %s" % str(_stats))
	gut.p("   weapons fired: %s" % str(_weapons))
	gut.p("   audit notes: %s" % str(_audit_notes))
	_report_labels()
	assert_eq(_stats["audit_errors"], 0, "no audit violations")
	assert_eq(_stats["stalled"], 0, "every match reached its end")
	assert_gt(_stats["round_ends"], 200, "plenty of round ends")
	assert_gt(_stats["team_wins"], 100, "team rounds were won")
	assert_gt(_stats["draws"], 5, "draws happened (mutual kills / drain wipe-outs)")
	assert_gt(_stats["sudden"], 40, "sudden death was reached")
	assert_gt(_stats["drain_kills"], 20, "the drain killed tanks")
	assert_gt(_stats["mate_hit_shots_ff_on"], 10, "shots hurt teammates with friendly fire on")
	assert_gt(_stats["blocked_mate_blasts_ff_off"], 10, "blasts reached protected teammates with friendly fire off")
	assert_gt(_stats["matches_free"], 30)
	assert_gt(_stats["replays"], 50)
	assert_gt(_stats["resumes"], 40)
	assert_gt(_weapons.size(), 9, "many weapon kinds were fired")


func _report_labels() -> void:
	var keys: Array = _by_label.keys()
	keys.sort()
	var text: String = "   turns per round by team setup (turn-ending actions; sudden death starts at 10 x tanks):\n"
	for k: Variant in keys:
		var d: Dictionary = _by_label[k]
		text += "      %-8s matches %3d  rounds %3d  avg %3d  max %3d  sudden-death rounds %d  draws %d\n" % [str(k),
				d["matches"], d["rounds"], (d["turns"] as int) / maxi(1, d["rounds"] as int), d["max"], d["sudden"], d["draws"]]
	gut.p(text)


func _play(m: int, st: MatchSettings, tag: String, rng: Rng) -> void:
	var state: MatchState = Simulation.new_match(st)
	var s: MatchSettings = state.settings
	var label: String = M6.label(s.teams, s.num_tanks)
	if not _by_label.has(label):
		_by_label[label] = {"matches": 0, "rounds": 0, "turns": 0, "max": 0, "sudden": 0, "draws": 0}
	var lb: Dictionary = _by_label[label]
	lb["matches"] = (lb["matches"] as int) + 1
	if s.has_teams():
		_stats["matches_teams"] += 1
		if not s.friendly_fire:
			_stats["matches_ff_off"] += 1
	if not s.full_unlocked:
		_stats["matches_free"] += 1
	assert_eq(StateSerial.validate(state), "", "%s: a new match validates" % tag)
	var log: Array[Dictionary] = []
	var expected_wins: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
	var errs_here: int = 0
	var steps: int = 0
	var cap: int = 90 * s.rounds * s.num_tanks
	var round_turns: int = 0
	var round_sd: bool = false
	var mid_bytes: PackedByteArray = PackedByteArray()
	var mid_log_len: int = -1
	var do_replay: bool = m % 3 == 0
	var pass_pct: int = [55, 70, 40, 85][m % 4]
	var mate_pct: int = 40
	while state.phase != SimConstants.PHASE_MATCH_OVER and steps < cap:
		steps += 1
		if state.phase == SimConstants.PHASE_SHOP:
			M6.shop_phase(state, rng, log)
			var ev0: Array[Dictionary] = Simulation.start_round(state)
			log.append({"kind": "start_round"})
			assert_eq(QaUtil.types(ev0), ["round_start", "wind", "turn"] as Array[String], tag)
			assert_eq(state.sudden_death_cycles, 0, "%s: counter reset at round start" % tag)
			assert_eq(state.turn_number, 0)
			round_turns = 0
			round_sd = false
			continue
		var tank: int = state.current_tank
		var action: Dictionary
		if s.controllers[tank] != SimConstants.CTRL_HUMAN:
			action = AiPlayer.next_action(state, tank)
			_stats["cpu_decisions"] += 1
		else:
			action = M6.human_action(state, rng, pass_pct, mate_pct)
		if Simulation.validate_action(state, action) != "":
			_stats["illegal_bot"] += 1
			assert_eq(s.controllers[tank], SimConstants.CTRL_HUMAN, "%s: the CPU sent an illegal action %s -> %s" % [tag, str(action),
					Simulation.validate_action(state, action)])
			action = {"kind": "pass", "tank": tank}
		var before: Dictionary = M6.snap(state)
		var ev: Array[Dictionary] = Simulation.apply_action(state, action)
		log.append(action)
		_stats["actions"] += 1
		var kind: String = action["kind"]
		var key: String = "fires" if kind == "fire" else ("passes" if kind == "pass" else ("moves" if kind == "move" else "items"))
		_stats[key] += 1
		if kind == "fire":
			_weapons[action["weapon"]] = (_weapons.get(action["weapon"], 0) as int) + 1
		var ta: int = Time.get_ticks_usec()
		var errs: Array[String] = M6.audit(before, state, action, ev, _audit_notes)
		var v: String = StateSerial.validate(state)
		if v != "":
			errs.append("StateSerial.validate: %s" % v)
		errs.append_array(M3.check_state(state))
		_t_audit += Time.get_ticks_usec() - ta
		if not errs.is_empty():
			_stats["audit_errors"] += errs.size()
			errs_here += 1
			if errs_here <= MAX_ERRS_PER_MATCH:
				assert_eq(errs.size(), 0, "%s, action %s:\n%s" % [tag, str(action), "\n".join(errs.slice(0, 6))])
		if kind == "fire" or kind == "pass":
			round_turns += 1
		_note_events(state, action, ev, before)
		if QaUtil.find(ev, "sudden_death").size() > 0:
			round_sd = true
		var ends: Array[Dictionary] = QaUtil.find(ev, "round_end")
		if not ends.is_empty():
			_stats["round_ends"] += 1
			lb["rounds"] = (lb["rounds"] as int) + 1
			lb["turns"] = (lb["turns"] as int) + round_turns
			lb["max"] = maxi(lb["max"] as int, round_turns)
			_stats["max_round_turns"] = maxi(_stats["max_round_turns"] as int, round_turns)
			if round_sd:
				lb["sudden"] = (lb["sudden"] as int) + 1
			var wt: int = ends[0]["winner_team"]
			if wt < 0:
				_stats["draws"] += 1
				lb["draws"] = (lb["draws"] as int) + 1
			elif s.has_teams():
				_stats["team_wins"] += 1
			if wt >= 0:
				for t: TankState in state.tanks:
					if t.team == wt:
						expected_wins[t.id] += 1
			_save_round_trip(tag, state, log)
		elif steps % 60 == 0:
			_save_round_trip(tag, state, log)
		if do_replay and mid_log_len < 0 and state.phase == SimConstants.PHASE_AIM and steps >= 25 \
				and round_turns >= 3:
			mid_bytes = SaveCodec.encode(state, log)
			mid_log_len = log.size()
	if steps >= cap:
		_stats["stalled"] += 1
	assert_true(steps < cap, "%s: the match reaches its end" % tag)
	# round_wins ledger: every member of a winning team got every round win.
	for t: TankState in state.tanks:
		assert_eq(t.round_wins, expected_wins[t.id], "%s: tank %d round_wins" % [tag, t.id])
	if state.phase == SimConstants.PHASE_MATCH_OVER and s.has_teams():
		var ts: Array[int] = Simulation.team_standings(state)
		assert_eq(ts, M6.expected_team_standings(state), "%s: final team_standings" % tag)
		assert_eq(ts.size(), _distinct(s.teams), "%s: team_standings lists every team once" % tag)
	if do_replay:
		_replay(tag, st, log, state, mid_bytes, mid_log_len)


func _distinct(teams: PackedInt32Array) -> int:
	var seen: Dictionary = {}
	for t: int in teams:
		seen[t] = true
	return seen.size()


## Counters for the report and the coverage asserts: drains, drain kills, teammate hits per mode.
func _note_events(state: MatchState, action: Dictionary, ev: Array[Dictionary], before: Dictionary) -> void:
	var drained: bool = false
	for e: Dictionary in ev:
		if e["type"] == "damage" and e["cause"] == "sudden_death":
			drained = true
		elif e["type"] == "tank_destroyed" and drained:
			_stats["drain_kills"] += 1
		elif e["type"] == "sudden_death":
			_stats["sudden"] += 1
	if drained:
		_stats["drains"] += 1
	if action["kind"] != "fire" or not state.settings.has_teams():
		return
	var shooter: TankState = state.tanks[action["tank"] as int]
	if state.settings.friendly_fire:
		for e: Dictionary in ev:
			if e["type"] == "damage" and e["cause"] != "sudden_death" and (e["tank"] as int) != shooter.id \
					and state.tanks[e["tank"] as int].team == shooter.team:
				_stats["mate_hit_shots_ff_on"] += 1
				break
		return
	var bt: Array = before["tanks"]
	for ex: Dictionary in QaUtil.find(ev, "explosion"):
		var hit: bool = false
		for t: TankState in state.tanks:
			if t.id != shooter.id and t.team == shooter.team and (bt[t.id]["alive"] as bool) \
					and Damage.distance_to_tank(ex["x"] as int, ex["y"] as int, t) < (ex["radius"] as int):
				hit = true
		if hit:
			_stats["blocked_mate_blasts_ff_off"] += 1
			break


func _save_round_trip(tag: String, state: MatchState, log: Array[Dictionary]) -> void:
	_stats["saves"] += 1
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
	assert_true(res["ok"], "%s: save round trip failed: %s" % [tag, str(res["error"])])
	if not res["ok"]:
		return
	var r: MatchState = res["state"]
	assert_eq(Simulation.fingerprint(r), Simulation.fingerprint(state), "%s: the round trip changes the state" % tag)
	assert_eq(r.sudden_death_cycles, state.sudden_death_cycles)
	assert_eq(r.settings.teams, state.settings.teams)
	assert_eq(r.settings.friendly_fire, state.settings.friendly_fire)
	assert_eq((res["actions"] as Array).size(), log.size(), "%s: the action log survives" % tag)
	for i: int in range(r.tanks.size()):
		assert_eq(r.tanks[i].team, state.tanks[i].team)


## Replays the log on a fresh match (fingerprint equal), then continues from the mid-match save with the rest
## of the log (fingerprint equal again): determinism across runs and across save / load.
func _replay(tag: String, st: MatchSettings, log: Array[Dictionary], final_state: MatchState,
		mid_bytes: PackedByteArray, mid_log_len: int) -> void:
	_stats["replays"] += 1
	var final_fp: String = Simulation.fingerprint(final_state)
	var state: MatchState = Simulation.new_match(st)
	for a: Dictionary in log:
		if not _apply_logged(state, a):
			assert_true(false, "%s: a logged action no longer applies: %s" % [tag, str(a)])
			return
	assert_eq(Simulation.fingerprint(state), final_fp, "%s: replay from the action log" % tag)
	if mid_log_len < 0:
		return
	_stats["resumes"] += 1
	var res: Dictionary = SaveCodec.decode(mid_bytes)
	assert_true(res["ok"], "%s: mid-match save decodes (%s)" % [tag, str(res["error"])])
	if not res["ok"]:
		return
	var resumed: MatchState = res["state"]
	for i: int in range(mid_log_len, log.size()):
		if not _apply_logged(resumed, log[i]):
			assert_true(false, "%s: logged action %d does not apply after a load: %s" % [tag, i, str(log[i])])
			return
	assert_eq(Simulation.fingerprint(resumed), final_fp, "%s: continuing after save/load reaches the same state" % tag)


func _apply_logged(state: MatchState, a: Dictionary) -> bool:
	if a["kind"] == "start_round":
		return not Simulation.start_round(state).is_empty()
	if Simulation.validate_action(state, a) != "":
		return false
	Simulation.apply_action(state, a)
	return true
