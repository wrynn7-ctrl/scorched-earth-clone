@warning_ignore_start("integer_division")
extends GutTest
## Seeded fuzz of 100 team matches (docs/ARCHITECTURE.md sections 39 and 40): random team layouts (a quarter of
## the matches have none), friendly fire on and off, 2-8 tanks (free caps in some), shot/pass bots that also
## aim at teammates. After every action:
##  - the independent economy audit (qa_m3: team-aware round pay, no credit for team damage, nothing at all
##    for a protected teammate, the drain pays nobody), the timeline order check and the state invariants;
##  - StateSerial.validate accepts the state; every 15th step a SaveCodec round trip reproduces it;
##  - round end <=> at most one team alive; the turn goes to a living tank and aim has two teams alive;
##  - sudden death starts exactly at turn 10 x tanks, once per round; each drain takes
##    min(5 x cycles, 25) HP and the cycle counter only counts up within a round.
## One match in ten is replayed from its action log and must end in the identical fingerprint.
## Failures print the match index and seed.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const MATCHES: int = 100
const ROOT_SEED: int = 0x7EA30001

var _stats: Dictionary = {"fires": 0, "passes": 0, "round_ends": 0, "draws": 0, "team_wins": 0, "sudden": 0,
		"drain_kills": 0, "teams_matches": 0, "ff_off_matches": 0, "ff_blocked_hits": 0, "saves": 0, "replays": 0}


func _settings(rng: Rng, m: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = rng.next_u32()
	var free: bool = m % 5 == 0
	s.full_unlocked = not free
	s.num_tanks = rng.range_int(2, 4) if (free or m % 2 == 0) else rng.range_int(2, 8)
	s.rounds = rng.range_int(1, 3) if s.num_tanks <= 4 else rng.range_int(1, 2)
	s.wind_max = [100, 0, 37, 100][m % 4]
	s.start_money = [10000, 4000, 25000, 0][m % 4]
	s.friendly_fire = m % 2 == 0
	if m % 4 != 3:
		s.teams = _random_teams(rng, s.num_tanks)
	return s


## n entries 0..3 with at least two distinct values.
func _random_teams(rng: Rng, n: int) -> PackedInt32Array:
	var k: int = rng.range_int(2, mini(4, n))
	var t := PackedInt32Array()
	t.resize(n)
	for i: int in range(n):
		t[i] = rng.range_int(0, k - 1)
	if t.count(t[0]) == n:
		t[n - 1] = (t[0] + 1) % 4
	return t


func _teams_alive(state: MatchState) -> int:
	var seen: Dictionary = {}
	for t: TankState in state.tanks:
		if t.alive:
			seen[t.team] = true
	return seen.size()


func _action(state: MatchState, rng: Rng) -> Dictionary:
	if rng.range_int(0, 99) < 65:
		return {"kind": "pass", "tank": state.current_tank}
	return QaUtil.bot_action(state, rng)


func test_100_team_matches_hold_every_invariant() -> void:
	var rng := Rng.new(ROOT_SEED)
	var t0: int = Time.get_ticks_msec()
	for m: int in range(MATCHES):
		var st: MatchSettings = _settings(rng, m)
		var tag: String = "match %d seed %d (%d tanks, teams %s, ff %s, rounds %d, free %s)" % [m, st.seed,
				st.num_tanks, str(st.teams), str(st.friendly_fire), st.rounds, str(not st.full_unlocked)]
		_play(m, st, tag, rng.fork(m))
	gut.p("TEAMS FUZZ: %d matches in %d ms, %s" % [MATCHES, Time.get_ticks_msec() - t0, str(_stats)])
	assert_gt(_stats["round_ends"], 100, "plenty of round ends")
	assert_gt(_stats["team_wins"], 30, "team rounds were won")
	assert_gt(_stats["sudden"], 20, "sudden death was reached")
	assert_gt(_stats["teams_matches"], 60)
	assert_gt(_stats["ff_off_matches"], 20)
	assert_gt(_stats["drain_kills"], 5, "the drain killed tanks")
	assert_gt(_stats["ff_blocked_hits"], 3, "shots landed on protected teammates")
	assert_gt(_stats["saves"], 100)
	assert_gt(_stats["replays"], 5)


func _play(m: int, st: MatchSettings, tag: String, rng: Rng) -> void:
	var state: MatchState = Simulation.new_match(st)
	var actions_log: Array[Dictionary] = []  # applied actions, "enter_round" as {"kind": "enter_round"}
	if state.settings.has_teams():
		_stats["teams_matches"] += 1
		if not state.settings.friendly_fire:
			_stats["ff_off_matches"] += 1
	assert_eq(StateSerial.validate(state), "", "%s: a new match validates" % tag)
	var steps: int = 0
	var cap: int = 60 * state.settings.rounds * state.settings.num_tanks
	var sd_seen_this_round: bool = false
	var last_cycles: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and steps < cap:
		steps += 1
		if state.phase == SimConstants.PHASE_SHOP:
			QaUtil.shop_and_ready(state)
			var ev0: Array[Dictionary] = Simulation.start_round(state)
			actions_log.append({"kind": "enter_round"})
			assert_eq(QaUtil.types(ev0), ["round_start", "wind", "turn"] as Array[String], tag)
			assert_eq(state.sudden_death_cycles, 0, "%s: counter reset" % tag)
			sd_seen_this_round = false
			last_cycles = 0
			continue
		var action: Dictionary = _action(state, rng)
		var before: Dictionary = M3.snapshot(state)
		var ev: Array[Dictionary] = Simulation.apply_action(state, action)
		actions_log.append(action)
		_stats["fires" if action["kind"] == "fire" else "passes"] += 1
		_check(tag, before, state, action, ev)
		var drain_events: int = 0
		for e: Dictionary in ev:
			if e["type"] == "sudden_death":
				_stats["sudden"] += 1
				assert_false(sd_seen_this_round, "%s: sudden_death emitted twice in a round" % tag)
				sd_seen_this_round = true
				assert_eq(state.turn_number, Simulation.sudden_death_turn(state.settings), "%s: starts at the threshold" % tag)
			elif e["type"] == "damage" and e["cause"] == "sudden_death":
				drain_events += 1
				assert_eq(e["amount"], Simulation.sudden_death_amount(state.sudden_death_cycles),
						"%s: drain amount at cycle %d" % [tag, state.sudden_death_cycles])
			elif e["type"] == "tank_destroyed" and drain_events > 0:
				_stats["drain_kills"] += 1
		if state.sudden_death_cycles != last_cycles:
			assert_eq(state.sudden_death_cycles, last_cycles + 1, "%s: one cycle at a time" % tag)
			last_cycles = state.sudden_death_cycles
		assert_true(sd_seen_this_round or state.sudden_death_cycles == 0,
				"%s: a drain without the sudden_death event" % tag)
		if steps % 40 == 0:
			_save_round_trip(tag, state)
	assert_true(steps < cap, "%s: the match reaches its end (sudden death guarantees it)" % tag)
	if m % 10 == 0:
		_replay(tag, st, actions_log, state)


func _check(tag: String, before: Dictionary, state: MatchState, action: Dictionary,
		ev: Array[Dictionary]) -> void:
	var errs: Array[String] = []
	errs.append_array(M3.audit(before, state, action, ev))
	errs.append_array(M3.check_state(state))
	errs.append_array(QaUtil.check_event_fields(ev))
	if action["kind"] == "fire":
		errs.append_array(M3.check_timeline(action, ev))
	var v: String = StateSerial.validate(state)
	if v != "":
		errs.append("StateSerial.validate: %s" % v)
	var ends: Array[Dictionary] = QaUtil.find(ev, "round_end")
	var alive_teams: int = _teams_alive(state)
	if ends.is_empty():
		if state.phase != SimConstants.PHASE_AIM:
			errs.append("phase %s without a round_end" % state.phase)
		elif alive_teams < 2:
			errs.append("round continues with %d team(s) alive" % alive_teams)
		elif not state.tanks[state.current_tank].alive:
			errs.append("turn goes to a dead tank")
	else:
		_stats["round_ends"] += 1
		var re: Dictionary = ends[0]
		if alive_teams > 1:
			errs.append("round_end with %d teams alive" % alive_teams)
		if re["winner"] == -1:
			_stats["draws"] += 1
			if re["winner_team"] != -1 or QaUtil.alive_count(state) != 0:
				errs.append("draw with winner_team %s / %d alive" % [str(re["winner_team"]), QaUtil.alive_count(state)])
		else:
			_stats["team_wins"] += 1 if state.settings.has_teams() else 0
			var w: TankState = state.tanks[re["winner"] as int]
			if not w.alive or w.team != re["winner_team"]:
				errs.append("winner %d (alive %s, team %d) vs winner_team %s" % [w.id, str(w.alive), w.team, str(re["winner_team"])])
	# Friendly fire off: a teammate of the shooter changes only through the drain.
	if action["kind"] == "fire" and not state.settings.friendly_fire and state.settings.has_teams():
		var shooter: TankState = state.tanks[action["tank"] as int]
		var tb: Array = before["tanks"]
		for id: int in range(tb.size()):
			var t: Dictionary = tb[id]
			if id == shooter.id or t["team"] != shooter.team:
				continue
			for ex: Dictionary in QaUtil.find(ev, "explosion"):
				if t["alive"] and Damage.distance_to_tank(ex["x"] as int, ex["y"] as int, state.tanks[id]) < (ex["radius"] as int):
					_stats["ff_blocked_hits"] += 1
			var drained: int = 0
			for e: Dictionary in QaUtil.find(ev, "damage"):
				if e["tank"] == id:
					if e["cause"] != "sudden_death":
						errs.append("teammate %d took %s damage with friendly fire off" % [id, e["cause"]])
					else:
						drained += e["amount"] as int
			if t["alive"] and state.tanks[id].health != maxi(0, (t["health"] as int) - drained):
				errs.append("teammate %d health %d -> %d with %d drained" % [id, t["health"], state.tanks[id].health, drained])
			if t["shield_hp"] != state.tanks[id].shield_hp and state.tanks[id].alive:
				errs.append("teammate %d shield %d -> %d with friendly fire off" % [id, t["shield_hp"], state.tanks[id].shield_hp])
	assert_eq(errs.size(), 0, "%s, %s:\n%s" % [tag, str(action), "\n".join(errs.slice(0, 6))])


func _save_round_trip(tag: String, state: MatchState) -> void:
	_stats["saves"] += 1
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))
	assert_true(res["ok"], "%s: save round trip failed: %s" % [tag, str(res["error"])])
	if not res["ok"]:
		return
	var r: MatchState = res["state"]
	assert_eq(Simulation.fingerprint(r), Simulation.fingerprint(state), "%s: round trip changes the state" % tag)
	assert_eq(r.sudden_death_cycles, state.sudden_death_cycles)
	assert_eq(r.settings.teams, state.settings.teams)
	assert_eq(r.settings.friendly_fire, state.settings.friendly_fire)


func _replay(tag: String, st: MatchSettings, actions_log: Array[Dictionary], final_state: MatchState) -> void:
	_stats["replays"] += 1
	var state: MatchState = Simulation.new_match(st)
	for a: Dictionary in actions_log:
		if a["kind"] == "enter_round":
			QaUtil.shop_and_ready(state)
			Simulation.start_round(state)
		else:
			assert_ne(Simulation.apply_action(state, a).size(), 0, "%s: a logged action replays" % tag)
	assert_eq(Simulation.fingerprint(state), Simulation.fingerprint(final_state), "%s: replay from the action log" % tag)
