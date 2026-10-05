@warning_ignore_start("integer_division")
extends GutTest
## Teams (docs/ARCHITECTURE.md section 39): settings, round end and pay, friendly fire,
## standings, saves.

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


## Hand-built flat-ground match with the given team per tank.
func _teams_state(teams: Array[int], friendly_fire: bool = true) -> MatchState:
	var s: MatchState = U.flat_state(teams.size())
	s.settings.teams = PackedInt32Array(teams)
	s.settings.friendly_fire = friendly_fire
	for i: int in range(teams.size()):
		s.tanks[i].team = teams[i]
	return s


func _settings(n: int, teams: Array[int]) -> MatchSettings:
	var st := MatchSettings.new()
	st.seed = 5
	st.num_tanks = n
	st.rounds = 3
	st.teams = PackedInt32Array(teams)
	return st


## Shoots tank `shooter` so that the shell lands on tank 1 at x = 800 (flat ground).
func _hit_tank_one(s: MatchState, weapon: String, shooter: int = 0) -> Array[Dictionary]:
	s.tanks[1].x = 800
	s.current_tank = shooter
	var p: int = WU.power_for_landing(s, 450, 800, shooter)
	var reason: String = Ballistics.trace(s, shooter, 450, p, "pulse_missile", SimConstants.WIND_USE_STATE,
			SimConstants.MAX_FLIGHT_TICKS)["end_reason"]
	assert_true(reason == "tank" or reason == "shield", "the shell lands on the tank (or its bubble)")
	return WU.fire(s, weapon, 450, p)


func _money_events(ev: Array[Dictionary], tank: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in U.find(ev, "money"):
		if e["tank"] == tank:
			out.append(e)
	return out


# --- settings -------------------------------------------------------------------------

func test_defaults_are_no_teams_and_friendly_fire_on() -> void:
	var st := MatchSettings.new()
	assert_eq(st.teams.size(), 0)
	assert_true(st.friendly_fire)
	assert_false(st.has_teams())
	assert_eq(st.team_of(3), 3, "without teams a tank is its own team")
	assert_eq(st.validate(), "")


func test_duplicate_copies_teams_and_friendly_fire_deeply() -> void:
	var st: MatchSettings = _settings(4, [0, 0, 1, 1])
	st.friendly_fire = false
	var d: MatchSettings = st.duplicate_settings()
	assert_eq(d.teams, PackedInt32Array([0, 0, 1, 1]))
	assert_false(d.friendly_fire)
	d.teams[0] = 3
	assert_eq(st.teams[0], 0, "the copy owns its array")
	var s: MatchState = Simulation.new_match(st)
	var c: MatchState = s.duplicate_state()
	c.settings.teams[1] = 2
	assert_eq(s.settings.teams[1], 0)


func test_validate_accepts_and_rejects() -> void:
	assert_eq(_settings(4, [0, 0, 1, 1]).validate(), "")
	assert_eq(_settings(2, [3, 0]).validate(), "")
	assert_eq(_settings(4, [0, 1, 2, 3]).validate(), "", "four singleton teams")
	assert_eq(_settings(3, [] as Array[int]).validate(), "", "empty = no teams")
	assert_eq(_settings(4, [0, 0, 1]).validate(), "invalid_settings", "too short")
	assert_eq(_settings(2, [0, 0, 1]).validate(), "invalid_settings", "too long")
	assert_eq(_settings(2, [0, 4]).validate(), "invalid_settings", "team 4 does not exist")
	assert_eq(_settings(2, [-1, 0]).validate(), "invalid_settings", "negative team")
	assert_eq(_settings(3, [2, 2, 2]).validate(), "invalid_settings", "a single team")
	assert_eq(_settings(2, [0, 0]).validate(), "invalid_settings")
	var love: MatchSettings = _settings(2, [0, 1])
	love.mode = SimConstants.MODE_LOVE
	assert_eq(love.validate(), "invalid_settings", "love mode requires empty teams")
	love.teams = PackedInt32Array()
	assert_eq(love.validate(), "")


func test_teams_error_helper() -> void:
	assert_eq(MatchSettings.teams_error(PackedInt32Array(), 5), "")
	assert_eq(MatchSettings.teams_error(PackedInt32Array([0, 1]), 2), "")
	assert_eq(MatchSettings.teams_error(PackedInt32Array([0, 1]), 3), "invalid_settings")
	assert_eq(MatchSettings.teams_error(PackedInt32Array([1, 1, 1]), 3), "invalid_settings")


func test_clamped_keeps_legal_teams_and_drops_the_rest() -> void:
	assert_eq(_settings(4, [0, 0, 1, 1]).clamped().teams, PackedInt32Array([0, 0, 1, 1]))
	assert_eq(_settings(4, [0, 0, 1]).clamped().teams.size(), 0, "too short is dropped")
	assert_eq(_settings(3, [0, 1, 9]).clamped().teams.size(), 0, "bad value is dropped")
	assert_eq(_settings(3, [1, 1, 1]).clamped().teams.size(), 0, "single team is dropped")
	var love: MatchSettings = _settings(2, [0, 1])
	love.mode = SimConstants.MODE_LOVE
	assert_eq(love.clamped().teams.size(), 0, "love mode clears teams")
	var wide: MatchSettings = _settings(4, [0, 0, 1, 1])
	wide.num_tanks = 2
	assert_eq(wide.clamped().teams.size(), 0, "cut to num_tanks it is a single team, so it is dropped")
	wide.teams = PackedInt32Array([0, 1, 1, 1])
	assert_eq(wide.clamped().teams, PackedInt32Array([0, 1]), "a longer list is cut to num_tanks")


func test_free_version_cap_cuts_the_team_list() -> void:
	var st: MatchSettings = _settings(8, [0, 1, 0, 1, 2, 2, 3, 3])
	st.full_unlocked = false
	var c: MatchSettings = st.clamped()
	assert_eq(c.num_tanks, 4)
	assert_eq(c.teams, PackedInt32Array([0, 1, 0, 1]), "teams are allowed in the free version, cut with the tanks")
	st.full_unlocked = true
	assert_eq(st.clamped().teams.size(), 8)


func test_clamped_does_not_touch_the_original() -> void:
	var st: MatchSettings = _settings(3, [1, 1, 1])
	st.clamped()
	assert_eq(st.teams, PackedInt32Array([1, 1, 1]))


func test_new_match_assigns_teams_from_the_settings() -> void:
	var s: MatchState = Simulation.new_match(_settings(4, [1, 0, 0, 3]))
	assert_eq([s.tanks[0].team, s.tanks[1].team, s.tanks[2].team, s.tanks[3].team], [1, 0, 0, 3])
	var plain := MatchSettings.new()
	plain.num_tanks = 3
	var p: MatchState = Simulation.new_match(plain)
	assert_eq([p.tanks[0].team, p.tanks[1].team, p.tanks[2].team], [0, 1, 2], "no teams: team = id")


func test_new_match_in_love_mode_ignores_teams() -> void:
	var st: MatchSettings = _settings(2, [0, 1])
	st.mode = SimConstants.MODE_LOVE
	var s: MatchState = Simulation.new_match(st)
	assert_eq(s.settings.teams.size(), 0)
	assert_eq([s.tanks[0].team, s.tanks[1].team], [0, 1])


func test_friendly_fire_is_kept_by_new_match() -> void:
	var st: MatchSettings = _settings(4, [0, 0, 1, 1])
	st.friendly_fire = false
	assert_false(Simulation.new_match(st).settings.friendly_fire)


# --- fingerprint and saves ---------------------------------------------------------------

func test_fingerprint_depends_on_teams_and_friendly_fire() -> void:
	var a: MatchState = Simulation.new_match(_settings(4, [0, 0, 1, 1]))
	var b: MatchState = Simulation.new_match(_settings(4, [0, 1, 0, 1]))
	var plain := MatchSettings.new()
	plain.seed = 5
	plain.num_tanks = 4
	plain.rounds = 3
	var c: MatchState = Simulation.new_match(plain)
	var st: MatchSettings = _settings(4, [0, 0, 1, 1])
	st.friendly_fire = false
	var d: MatchState = Simulation.new_match(st)
	var fps: Dictionary = {}
	for s: MatchState in [a, b, c, d]:
		fps[Simulation.fingerprint(s)] = true
	assert_eq(fps.size(), 4, "four distinct fingerprints")
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(a.duplicate_state()))


func test_fingerprint_depends_on_sudden_death_cycles() -> void:
	var s: MatchState = U.flat_state(2)
	var before: String = Simulation.fingerprint(s)
	s.sudden_death_cycles = 2
	assert_ne(Simulation.fingerprint(s), before)


func test_save_version_is_4_and_round_trips_teams() -> void:
	assert_eq(SaveCodec.SAVE_VERSION, 4)
	var st: MatchSettings = _settings(4, [2, 0, 2, 0])
	st.friendly_fire = false
	var s: MatchState = Simulation.new_match(st)
	U.begin_round(s)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_true(res["ok"], str(res["error"]))
	var r: MatchState = res["state"]
	assert_eq(r.settings.teams, PackedInt32Array([2, 0, 2, 0]))
	assert_false(r.settings.friendly_fire)
	assert_eq([r.tanks[0].team, r.tanks[1].team, r.tanks[2].team, r.tanks[3].team], [2, 0, 2, 0])
	assert_eq(Simulation.fingerprint(r), Simulation.fingerprint(s))


func test_a_version_3_save_is_refused() -> void:
	var s: MatchState = Simulation.new_match(_settings(2, [0, 1]))
	var bytes: PackedByteArray = SaveCodec.encode(s, [] as Array[Dictionary])
	bytes[4] = 3
	assert_eq(SaveCodec.decode(bytes)["error"], "bad_version")


func _invalid(mutate: Callable) -> String:
	var s: MatchState = Simulation.new_match(_settings(4, [0, 0, 1, 1]))
	U.begin_round(s)
	mutate.call(s)
	return StateSerial.validate(s)


func test_validation_of_teams_in_a_state() -> void:
	assert_eq(_invalid(func(_s: MatchState) -> void: pass), "")
	assert_ne(_invalid(func(s: MatchState) -> void: s.settings.teams = PackedInt32Array([0, 0, 1])), "", "wrong length")
	assert_ne(_invalid(func(s: MatchState) -> void: s.settings.teams = PackedInt32Array([0, 0, 1, 7])), "", "bad value")
	assert_ne(_invalid(func(s: MatchState) -> void: s.settings.teams = PackedInt32Array([0, 0, 0, 0])), "", "single team")
	assert_ne(_invalid(func(s: MatchState) -> void: s.tanks[2].team = 0), "", "tank team differs from the settings")
	assert_ne(_invalid(func(s: MatchState) -> void: s.settings.teams = PackedInt32Array()), "", "tanks have teams the settings no longer explain")
	assert_ne(_invalid(func(s: MatchState) -> void:
		s.settings.mode = SimConstants.MODE_LOVE), "", "love mode with teams")


func test_decode_reports_invalid_state_for_a_resealed_bad_team_list() -> void:
	var s: MatchState = Simulation.new_match(_settings(4, [0, 0, 1, 1]))
	s.settings.teams = PackedInt32Array([0, 0, 0, 0])
	for t: TankState in s.tanks:
		t.team = 0
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_false(res["ok"])
	assert_eq(res["error"], "invalid_state")


func test_validation_of_aim_with_one_team_left() -> void:
	assert_ne(_invalid(func(s: MatchState) -> void:
		s.tanks[2].alive = false
		s.tanks[2].health = 0
		s.tanks[3].alive = false
		s.tanks[3].health = 0), "", "aim with a single team alive")
	assert_eq(_invalid(func(s: MatchState) -> void:
		s.tanks[0].alive = false
		s.tanks[0].health = 0
		s.tanks[2].alive = false
		s.tanks[2].health = 0
		s.current_tank = 1), "", "two teams still alive")


func test_validation_of_a_finished_round_with_two_teams_alive() -> void:
	assert_ne(_invalid(func(s: MatchState) -> void: s.phase = SimConstants.PHASE_SHOP), "", "shop after a round with 2 teams alive")
	assert_ne(_invalid(func(s: MatchState) -> void:
		s.round_index = s.settings.rounds - 1
		s.phase = SimConstants.PHASE_MATCH_OVER), "")


# --- round end -------------------------------------------------------------------------------

func test_2v2_round_continues_until_one_team_remains() -> void:
	var s: MatchState = _teams_state([0, 0, 1, 1])
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 0, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 2, 1000, "explosion", 0, ev)
	s.current_tank = 1
	ev = Simulation.apply_action(s, U.pass_turn(1))
	assert_eq(U.find(ev, "round_end").size(), 0, "a tank of each team is alive")
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_eq(s.current_tank, 3)
	Simulation.apply_damage(s, -1, 3, 1000, "explosion", 0, ev)
	s.current_tank = 1
	ev = Simulation.apply_action(s, U.pass_turn(1))
	var re: Array[Dictionary] = U.find(ev, "round_end")
	assert_eq(re.size(), 1)
	assert_eq(re[0]["winner"], 1)
	assert_eq(re[0]["winner_team"], 0)
	assert_eq(s.phase, SimConstants.PHASE_SHOP)


func test_round_end_event_field_order_and_types() -> void:
	var s: MatchState = _teams_state([0, 0, 1])
	U.kill_all_but(s, 1)
	s.tanks[0].alive = false
	s.tanks[0].health = 0
	s.current_tank = 1
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(1))
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq(re.keys(), ["type", "tick", "winner", "winner_team"])
	assert_eq(typeof(re["winner_team"]), TYPE_INT)


func test_3v1_the_lone_tank_wins_when_the_trio_is_gone() -> void:
	var s: MatchState = _teams_state([0, 0, 0, 1])
	var ev: Array[Dictionary] = []
	for i: int in range(3):
		Simulation.apply_damage(s, -1, i, 1000, "explosion", 0, ev)
	s.current_tank = 3
	ev = Simulation.apply_action(s, U.pass_turn(3))
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [3, 1])
	assert_eq(s.tanks[3].round_wins, 1)
	for i: int in range(3):
		assert_eq(s.tanks[i].round_wins, 0)


func test_3v1_the_trio_wins_when_the_lone_tank_is_gone_lowest_id_is_the_winner() -> void:
	var s: MatchState = _teams_state([0, 1, 0, 0])
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 1, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 0, 1000, "explosion", 0, ev)
	s.current_tank = 2
	ev = Simulation.apply_action(s, U.pass_turn(2))
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [2, 0], "lowest living id of the winning team")


func test_round_pay_includes_destroyed_teammates() -> void:
	var s: MatchState = _teams_state([0, 0, 1, 1])
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 0, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 2, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 3, 1000, "explosion", 0, ev)
	s.current_tank = 1
	ev = Simulation.apply_action(s, U.pass_turn(1))
	var pay: Array[Dictionary] = U.find(ev, "money")
	var got: Array = []
	for e: Dictionary in pay:
		got.append([e["tank"], e["delta"], e["reason"]])
	assert_eq(got, [[0, 2500, "win"], [1, 1000, "survive"], [1, 2500, "win"]],
			"id order; the destroyed teammate gets the win pay only, the losers nothing")
	assert_eq([s.tanks[0].money, s.tanks[1].money, s.tanks[2].money, s.tanks[3].money], [2500, 3500, 0, 0])
	assert_eq([s.tanks[0].round_wins, s.tanks[1].round_wins, s.tanks[2].round_wins, s.tanks[3].round_wins], [1, 1, 0, 0])
	var types: Array[String] = U.types(ev)
	assert_eq(types.slice(types.find("round_end")), ["round_end", "money", "money", "money"] as Array[String])


func test_round_pay_survive_goes_to_every_living_winner() -> void:
	var s: MatchState = _teams_state([0, 0, 0, 1])
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 3, 1000, "explosion", 0, ev)
	ev = Simulation.apply_action(s, U.pass_turn(0))
	for i: int in range(3):
		assert_eq(s.tanks[i].money, 3500, "tank %d" % i)
		assert_eq(s.tanks[i].round_wins, 1)
	assert_eq(s.tanks[3].money, 0)


func test_pay_round_direct_calls() -> void:
	var s: MatchState = _teams_state([0, 0, 1])
	s.tanks[1].alive = false
	var ev: Array[Dictionary] = []
	Economy.pay_round(s, 0, 4, ev)
	assert_eq(s.tanks[0].money, 3500)
	assert_eq(s.tanks[1].money, 2500, "destroyed teammate: win only")
	assert_eq(s.tanks[2].money, 1000, "living loser: survive only")
	var d: MatchState = _teams_state([0, 0, 1])
	var ev2: Array[Dictionary] = []
	for t: TankState in d.tanks:
		t.alive = false
	Economy.pay_round(d, -1, 4, ev2)
	assert_eq(ev2.size(), 0, "a draw pays nobody")


func test_match_over_after_the_last_round_and_shop_otherwise() -> void:
	var st: MatchSettings = _settings(4, [0, 0, 1, 1])
	st.rounds = 2
	var s: MatchState = U.started_match(st)
	for k: int in range(2):
		var ev: Array[Dictionary] = []
		Simulation.apply_damage(s, -1, 2, 1000, "explosion", 0, ev)
		Simulation.apply_damage(s, -1, 3, 1000, "explosion", 0, ev)
		Simulation.apply_action(s, U.pass_turn(s.current_tank))
		assert_eq(s.phase, SimConstants.PHASE_SHOP if k == 0 else SimConstants.PHASE_MATCH_OVER)
		if k == 0:
			assert_eq(U.begin_round(s).size(), 3)
			assert_true(s.tanks[2].alive, "round-scoped state is restored")
	assert_eq([s.tanks[0].round_wins, s.tanks[1].round_wins, s.tanks[2].round_wins, s.tanks[3].round_wins], [2, 2, 0, 0])


func test_a_draw_when_the_last_two_tanks_blast_each_other() -> void:
	var s: MatchState = _teams_state([0, 1], true)
	s.tanks[0].x = 500
	s.tanks[1].x = 530
	s.tanks[1].health = 20
	s.tanks[0].set_stock("nova_core", 1)
	var ev: Array[Dictionary] = WU.fire(s, "nova_core", 900, 60)
	assert_false(s.tanks[0].alive, "the shell fell back on its own tank")
	assert_false(s.tanks[1].alive)
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [-1, -1])
	assert_eq(U.find(ev, "tank_destroyed").size(), 2)
	assert_eq(U.find(ev, "wind").size(), 0)
	assert_eq(s.tanks[0].round_wins + s.tanks[1].round_wins, 0)
	for e: Dictionary in U.find(ev, "money"):
		assert_ne(e["reason"], "survive")
		assert_ne(e["reason"], "win")


func test_a_team_draw_when_everyone_is_gone() -> void:
	# A move can kill the walker, who is the last tank alive of the last team: nobody is left.
	var s: MatchState = _teams_state([0, 0, 1, 1])
	var ev: Array[Dictionary] = []
	for i: int in range(4):
		Simulation.apply_damage(s, -1, i, 1000, "explosion", 0, ev)
	ev.clear()
	Simulation._finish_turn(s, 3, ev)
	assert_eq(U.types(ev), ["round_end"] as Array[String], "no pay for anyone")
	assert_eq(ev[0], {"type": "round_end", "tick": 3, "winner": -1, "winner_team": -1})
	assert_eq(s.tanks[0].money + s.tanks[1].money + s.tanks[2].money + s.tanks[3].money, 0)
	assert_eq(s.tanks[0].round_wins + s.tanks[2].round_wins, 0)


func test_no_teams_round_end_matches_the_old_rule() -> void:
	var s: MatchState = U.flat_state(3)
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 1, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 2, 1000, "explosion", 0, ev)
	ev = Simulation.apply_action(s, U.pass_turn(0))
	var re: Dictionary = U.find(ev, "round_end")[0]
	assert_eq([re["winner"], re["winner_team"]], [0, 0])
	assert_eq(s.tanks[0].money, 3500)


func test_distinct_teams_play_exactly_like_no_teams() -> void:
	# Four singleton teams are the same game as no teams: identical timelines for identical actions.
	var a: MatchState = U.flat_state(4)
	var b: MatchState = _teams_state([0, 1, 2, 3], false)
	var rng := Rng.new(77)
	var steps: int = 0
	while a.phase == SimConstants.PHASE_AIM and steps < 60:
		var me: int = a.current_tank
		var act: Dictionary = {"kind": "fire", "tank": me, "angle": rng.range_int(300, 1500),
				"power": rng.range_int(300, 900), "weapon": "pulse_missile"}
		var ea: Array[Dictionary] = Simulation.apply_action(a, act)
		var eb: Array[Dictionary] = Simulation.apply_action(b, act)
		assert_eq(str(ea), str(eb), "step %d" % steps)
		steps += 1
	assert_eq(a.phase, b.phase)
	assert_gt(steps, 3)
	for i: int in range(4):
		assert_eq(a.tanks[i].money, b.tanks[i].money)
		assert_eq(a.tanks[i].health, b.tanks[i].health)


# --- friendly fire ---------------------------------------------------------------------------

func test_friendly_fire_on_direct_hit_hurts_and_costs_the_shooter() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[0].money = 5000
	var ev: Array[Dictionary] = _hit_tank_one(s, "pulse_missile")
	var removed: int = 100 - s.tanks[1].health
	assert_gt(removed, 40, "the blast, plus the fall into its crater")
	assert_eq(s.tanks[0].damage_dealt, 0, "no credit")
	assert_eq(s.tanks[0].kills, 0)
	var m: Array[Dictionary] = _money_events(ev, 0)
	assert_gt(m.size(), 0)
	for e: Dictionary in m:
		assert_eq(e["reason"], "self_damage")
	assert_eq(s.tanks[0].money, 5000 - removed * 15)


func test_friendly_fire_on_a_teammate_kill_gives_no_bonus_and_no_kill() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[1].health = 20
	s.tanks[0].money = 5000
	var ev: Array[Dictionary] = _hit_tank_one(s, "pulse_missile")
	assert_false(s.tanks[1].alive)
	assert_eq(s.tanks[0].kills, 0)
	assert_eq(s.tanks[0].damage_dealt, 0)
	assert_eq(s.tanks[0].money, 5000 - 20 * 15, "only the self-damage penalty for the 20 HP actually removed")
	for e: Dictionary in _money_events(ev, 0):
		assert_eq(e["reason"], "self_damage")
	assert_eq(U.find(ev, "tank_destroyed").size(), 1)


func test_friendly_fire_off_a_direct_hit_does_nothing_to_the_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[0].money = 1000
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var before: MatchState = s.duplicate_state()
	var ev: Array[Dictionary] = _hit_tank_one(s, "pulse_missile")
	# The shell hits the shield bubble first; the explosion still happens, but the teammate is untouched.
	assert_eq(s.tanks[1].health, 100)
	assert_eq(s.tanks[1].shield_hp, 30, "no shield loss")
	assert_eq(s.tanks[1].shield_type, before.tanks[1].shield_type)
	assert_eq(s.tanks[0].money, 1000, "no money")
	assert_eq(U.find(ev, "damage").size(), 0)
	assert_eq(U.find(ev, "shield_hit").size(), 0)
	assert_eq(U.find(ev, "shield_down").size(), 0)
	assert_eq(U.find(ev, "money").size(), 0)
	assert_eq(U.find(ev, "explosion").size(), 1, "the blast itself still carves the terrain")
	assert_eq(U.find(ev, "terrain_carve").size(), 1)


func test_friendly_fire_off_an_unshielded_teammate_is_untouched_too() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].health = 5
	var ev: Array[Dictionary] = _hit_tank_one(s, "pulse_missile")
	assert_true(s.tanks[1].alive)
	assert_eq(s.tanks[1].health, 5)
	assert_eq(U.types(ev), ["fire", "projectile", "projectile_end", "explosion", "terrain_carve", "terrain_settle", "tank_fall", "wind", "turn"] as Array[String],
			"no damage, no money; the tank still drops into the crater")


func test_friendly_fire_off_splash_hits_the_enemy_but_not_the_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].x = 800
	s.tanks[2].x = 830
	var ev: Array[Dictionary] = _hit_tank_one(s, "hyperpulse")
	assert_eq(s.tanks[1].health, 100)
	assert_lt(s.tanks[2].health, 100, "the enemy next to it is hurt")
	var dmg: Array[Dictionary] = U.find(ev, "damage")
	assert_eq(dmg.size(), 1)
	assert_eq(dmg[0]["tank"], 2)
	assert_gt(s.tanks[0].damage_dealt, 0)
	assert_eq(_money_events(ev, 0).size(), 1)
	assert_eq(_money_events(ev, 0)[0]["reason"], "damage")


func test_friendly_fire_on_splash_hurts_both_with_credit_only_for_the_enemy() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[2].x = 830
	s.tanks[0].money = 10000
	var ev: Array[Dictionary] = _hit_tank_one(s, "hyperpulse")
	assert_lt(s.tanks[1].health, 100)
	assert_lt(s.tanks[2].health, 100)
	var removed_enemy: int = 100 - s.tanks[2].health
	var removed_mate: int = 100 - s.tanks[1].health
	assert_eq(s.tanks[0].damage_dealt, removed_enemy)
	assert_eq(s.tanks[0].money, 10000 + 15 * removed_enemy - 15 * removed_mate)
	var reasons: Array[String] = []
	for e: Dictionary in _money_events(ev, 0):
		reasons.append(e["reason"])
	assert_eq(reasons.slice(0, 2), ["self_damage", "damage"] as Array[String], "hits in tank-id order: teammate 1, enemy 2")
	assert_false(reasons.has("kill"))


func test_self_damage_is_unchanged_with_friendly_fire_off() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[0].money = 5000
	var ev: Array[Dictionary] = []
	var removed: int = Simulation.apply_damage(s, 0, 0, 30, "explosion", 0, ev)
	assert_eq(removed, 30)
	assert_eq(s.tanks[0].health, 70)
	assert_eq(s.tanks[0].money, 5000 - 450)
	assert_eq(U.types(ev), ["damage", "money"] as Array[String])


func test_apply_damage_direct_friendly_fire_off_returns_zero_and_emits_nothing() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].shield_type = Catalog.index_of("ion_shield")
	s.tanks[1].shield_hp = 60
	var ev: Array[Dictionary] = []
	assert_eq(Simulation.apply_damage(s, 0, 1, 40, "explosion", 0, ev), 0)
	assert_eq(Simulation.apply_damage(s, 0, 1, 4000, "burn", 0, ev), 0)
	assert_eq(Simulation.apply_damage(s, 0, 1, 4000, "beam", 0, ev), 0)
	assert_eq(Simulation.apply_damage(s, 0, 1, 4000, "fall", 0, ev), 0)
	assert_eq(ev.size(), 0)
	assert_eq(s.tanks[1].health, 100)
	assert_eq(s.tanks[1].shield_hp, 60)
	# An enemy, no attacker, and the sudden-death drain are all unaffected.
	assert_gt(Simulation.apply_damage(s, 2, 1, 10, "explosion", 0, ev), -1)
	assert_eq(s.tanks[1].shield_hp, 50, "an enemy still hits the shield")
	assert_eq(Simulation.apply_damage(s, -1, 1, 10, "fall", 0, ev), 10)


func test_is_friendly_fire_immune() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	assert_true(Simulation.is_friendly_fire_immune(s, 0, 1))
	assert_false(Simulation.is_friendly_fire_immune(s, 0, 0), "self")
	assert_false(Simulation.is_friendly_fire_immune(s, 0, 2), "enemy")
	assert_false(Simulation.is_friendly_fire_immune(s, -1, 1), "no attacker")
	assert_false(Simulation.is_friendly_fire_immune(s, 9, 1), "unknown attacker")
	s.settings.friendly_fire = true
	assert_false(Simulation.is_friendly_fire_immune(s, 0, 1))


func test_friendly_fire_off_burn_does_nothing_to_a_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].health = 30
	s.tanks[0].money = 500
	var ev: Array[Dictionary] = _hit_tank_one(s, "ember_rain")
	assert_eq(s.tanks[0].money, 500)
	assert_eq(s.tanks[1].health, 30)
	assert_eq(U.find(ev, "damage").size(), 0)
	assert_eq(U.find(ev, "money").size(), 0)
	assert_eq(U.find(ev, "flames").size(), 1, "the flames themselves still burn")


func test_friendly_fire_on_burn_hurts_a_teammate_at_a_cost() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[0].money = 5000
	var ev: Array[Dictionary] = _hit_tank_one(s, "ember_rain")
	assert_eq(s.tanks[1].health, 60, "burn is capped at 40")
	assert_eq(U.find(ev, "damage")[0]["cause"], "burn")
	assert_eq(s.tanks[0].money, 5000 - 40 * 15)
	assert_eq(s.tanks[0].damage_dealt, 0)


func test_friendly_fire_off_beam_does_nothing_to_a_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].x = 600
	s.tanks[2].x = 900
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	assert_eq(s.tanks[1].health, 100)
	assert_eq(s.tanks[1].shield_hp, 30)
	assert_eq(U.find(ev, "damage").size(), 0)
	assert_eq(U.find(ev, "shield_hit").size(), 0)
	assert_eq(s.tanks[2].health, 100, "the beam still stops at the first tank")


func test_friendly_fire_on_beam_hurts_a_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[1].x = 600
	s.tanks[2].x = 900
	s.tanks[0].money = 1000
	WU.fire(s, "photon_lance", 0, 500)
	assert_eq(s.tanks[1].health, 65)
	assert_eq(s.tanks[0].money, 1000 - 35 * 15)


func _strip_state(friendly_fire: bool) -> MatchState:
	var s: MatchState = _teams_state([0, 0, 1], friendly_fire)
	s.tanks[1].x = 800
	s.tanks[2].x = 815
	for i: int in [1, 2]:
		s.tanks[i].shield_type = Catalog.index_of("glow_shield")
		s.tanks[i].shield_hp = 30
		s.tanks[i].repulsor_charge = 50
	return s


func test_friendly_fire_off_strip_fields_leaves_a_teammates_fields_alone() -> void:
	var s: MatchState = _strip_state(false)
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 805, 594, 40, 0, ev, 0)
	assert_eq(s.tanks[1].shield_hp, 30, "teammate keeps the shield")
	assert_eq(s.tanks[1].repulsor_charge, 50)
	assert_eq(s.tanks[2].shield_hp, 0, "the enemy is stripped")
	assert_eq(s.tanks[2].repulsor_charge, 0)
	assert_eq(U.types(ev), ["shield_down", "repulsor_down"] as Array[String])
	for e: Dictionary in ev:
		assert_eq(e["tank"], 2)


func test_friendly_fire_on_strip_fields_strips_a_teammate() -> void:
	var s: MatchState = _strip_state(true)
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 805, 594, 40, 0, ev, 0)
	assert_eq(s.tanks[1].shield_hp, 0)
	assert_eq(s.tanks[1].repulsor_charge, 0)
	assert_eq(s.tanks[2].shield_hp, 0)
	assert_eq(ev.size(), 4)


func test_strip_fields_without_an_attacker_strips_everyone() -> void:
	var s: MatchState = _strip_state(false)
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 805, 594, 40, 0, ev)
	assert_eq(ev.size(), 4)


func test_friendly_fire_off_static_burst_shot_spares_a_teammates_shield() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var ev: Array[Dictionary] = _hit_tank_one(s, "static_burst")
	assert_eq(s.tanks[1].shield_hp, 30)
	assert_eq(s.tanks[1].health, 100)
	assert_eq(U.find(ev, "shield_down").size(), 0)
	assert_eq(U.find(ev, "damage").size(), 0)


func test_friendly_fire_on_static_burst_shot_strips_and_damages_a_teammate() -> void:
	var s: MatchState = _teams_state([0, 0, 1], true)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var ev: Array[Dictionary] = _hit_tank_one(s, "static_burst")
	assert_eq(s.tanks[1].shield_hp, 0)
	assert_eq(U.find(ev, "shield_down").size(), 1)
	assert_lt(s.tanks[1].health, 100, "stripped first, so the blast reaches health")


func test_static_burst_on_your_own_field_still_works_with_friendly_fire_off() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	s.tanks[0].shield_type = Catalog.index_of("glow_shield")
	s.tanks[0].shield_hp = 30
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, s.tanks[0].x, s.tanks[0].y - 6, 40, 0, ev, 0)
	assert_eq(s.tanks[0].shield_hp, 0)
	assert_eq(U.find(ev, "shield_down").size(), 1)


# A plateau for tank 1 at y = 500; the shot carves the ground below it, so it falls ~58 cells.
func _plateau_state(teams: Array[int], friendly_fire: bool) -> MatchState:
	var s: MatchState = _teams_state(teams, friendly_fire)
	s.terrain.flatten(0, SimConstants.WORLD_W - 1, 600)
	s.terrain.flatten(770, 830, 500)
	s.tanks[1].x = 800
	s.tanks[1].y = TankState.rest_y(s.terrain, 800)
	return s


func _carve_under(s: MatchState, attacker: int) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	WeaponResolver.blast(s, attacker, 800, 540, 30, 10, "pulse_missile", 0, ev)
	return ev


func test_teammate_caused_fall_with_friendly_fire_off_costs_nothing() -> void:
	var s: MatchState = _plateau_state([0, 0, 1], false)
	s.tanks[1].set_stock("drift_chute", 1)
	s.tanks[0].money = 700
	var y0: int = s.tanks[1].y
	var ev: Array[Dictionary] = _carve_under(s, 0)
	var falls: Array[Dictionary] = U.find(ev, "tank_fall")
	assert_eq(falls.size(), 1, "the tank still falls physically")
	assert_gt(s.tanks[1].y, y0 + SimConstants.FALL_SAFE + 2, "a damaging fall")
	assert_eq(s.tanks[1].health, 100)
	assert_eq(s.tanks[1].stock_of("drift_chute"), 1, "the chute is not spent: nothing happened")
	assert_eq(U.find(ev, "chute").size(), 0)
	assert_eq(U.find(ev, "damage").size(), 0)
	assert_eq(s.tanks[0].money, 700)
	assert_eq(U.find(ev, "money").size(), 0)


func test_teammate_caused_fall_with_friendly_fire_on_hurts_the_teammate_and_costs_the_attacker() -> void:
	var s: MatchState = _plateau_state([0, 0, 1], true)
	s.tanks[0].money = 5000
	var ev: Array[Dictionary] = _carve_under(s, 0)
	var d: Array[Dictionary] = U.find(ev, "damage")
	assert_eq(d.size(), 1)
	assert_eq(d[0]["cause"], "fall")
	assert_eq(d[0]["tank"], 1)
	var removed: int = 100 - s.tanks[1].health
	assert_gt(removed, 0)
	assert_eq(s.tanks[0].money, 5000 - removed * 15)
	assert_eq(s.tanks[0].damage_dealt, 0)


func test_enemy_caused_fall_still_credits_the_attacker_with_friendly_fire_off() -> void:
	var s: MatchState = _plateau_state([0, 1, 1], false)
	var ev: Array[Dictionary] = _carve_under(s, 0)
	var removed: int = 100 - s.tanks[1].health
	assert_gt(removed, 0)
	assert_eq(s.tanks[0].damage_dealt, removed)
	assert_eq(U.find(ev, "damage")[0]["cause"], "fall")


func test_a_chute_is_still_used_when_an_enemy_caused_the_fall() -> void:
	var s: MatchState = _plateau_state([0, 1, 1], false)
	s.tanks[1].set_stock("drift_chute", 1)
	var ev: Array[Dictionary] = _carve_under(s, 0)
	assert_eq(s.tanks[1].stock_of("drift_chute"), 0)
	assert_eq(U.find(ev, "chute").size(), 1)
	assert_eq(s.tanks[1].health, 100)


func test_fall_attributed_to_a_teammate_is_free_with_friendly_fire_off() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	var ev: Array[Dictionary] = []
	var from_y: int = s.tanks[1].y
	Settle.apply_fall(s, 1, from_y, from_y + 100, 0, 0, ev)
	assert_eq(U.types(ev), ["tank_fall"] as Array[String])
	assert_eq(s.tanks[1].health, 100)
	var on: MatchState = _teams_state([0, 0, 1], true)
	on.tanks[0].money = 1000
	var ev2: Array[Dictionary] = []
	Settle.apply_fall(on, 1, from_y, from_y + 100, 0, 0, ev2)
	assert_eq(U.types(ev2), ["tank_fall", "damage", "money"] as Array[String])
	assert_eq(on.tanks[1].health, 100 - 44)


func test_a_walking_fall_has_no_attacker_whatever_the_friendly_fire_setting() -> void:
	var s: MatchState = _teams_state([0, 0, 1], false)
	var ev: Array[Dictionary] = []
	Settle.apply_fall(s, 1, 500, 600, -1, 0, ev)
	assert_eq(s.tanks[1].health, 100 - 44, "nobody's shot: ordinary fall damage")


# --- enemy logic ------------------------------------------------------------------------------

func test_seeker_nearest_enemy_skips_teammates() -> void:
	var s: MatchState = _teams_state([0, 0, 1, 1])
	s.tanks[0].x = 300
	s.tanks[1].x = 400
	s.tanks[2].x = 1200
	s.tanks[3].x = 900
	var shooter: TankState = s.tanks[0]
	var px: int = FixedMath.from_cell(300)
	var py: int = FixedMath.from_cell(500)
	var t: TankState = Ballistics._nearest_enemy(s, shooter, px, py)
	assert_eq(t.id, 3, "tank 1 is nearer but a teammate")
	s.tanks[3].alive = false
	assert_eq(Ballistics._nearest_enemy(s, shooter, px, py).id, 2)
	s.tanks[2].alive = false
	assert_null(Ballistics._nearest_enemy(s, shooter, px, py), "only teammates left")


func test_no_teams_nearest_enemy_is_any_other_tank() -> void:
	var s: MatchState = U.flat_state(3)
	var t: TankState = Ballistics._nearest_enemy(s, s.tanks[0], FixedMath.from_cell(300), FixedMath.from_cell(500))
	assert_eq(t.id, 1)


# --- standings -------------------------------------------------------------------------------

func _set_score(s: MatchState, id: int, wins: int, dmg: int, kills: int) -> void:
	s.tanks[id].round_wins = wins
	s.tanks[id].damage_dealt = dmg
	s.tanks[id].kills = kills


func test_team_standings_is_empty_without_teams() -> void:
	assert_eq(Simulation.team_standings(U.flat_state(3)).size(), 0)
	var s: MatchState = Simulation.new_match(_settings(3, [] as Array[int]))
	assert_eq(Simulation.team_standings(s).size(), 0)


func test_team_standings_most_round_wins_first() -> void:
	var s: MatchState = _teams_state([0, 0, 1, 1])
	_set_score(s, 0, 1, 0, 0)
	_set_score(s, 1, 1, 0, 0)
	_set_score(s, 2, 2, 0, 0)
	_set_score(s, 3, 2, 0, 0)
	assert_eq(Simulation.team_standings(s), [1, 0] as Array[int])


func test_team_standings_tie_breaks_summed_damage_then_kills_then_lowest_team() -> void:
	var s: MatchState = _teams_state([0, 0, 1, 1, 2])
	# Equal wins; team 1 has more summed damage even though team 0's best tank dealt more.
	_set_score(s, 0, 1, 90, 0)
	_set_score(s, 1, 1, 0, 0)
	_set_score(s, 2, 1, 50, 0)
	_set_score(s, 3, 1, 50, 0)
	_set_score(s, 4, 1, 100, 0)
	var order: Array[int] = Simulation.team_standings(s)
	assert_eq(order, [1, 2, 0] as Array[int], "teams 1 and 2 sum to 100 (lower id first), team 0 only 90")
	# Same damage: kills decide.
	_set_score(s, 0, 1, 50, 1)
	_set_score(s, 1, 1, 50, 2)
	_set_score(s, 2, 1, 50, 1)
	_set_score(s, 3, 1, 50, 1)
	_set_score(s, 4, 1, 100, 0)
	assert_eq(Simulation.team_standings(s), [0, 1, 2] as Array[int], "all damage 100: kills 3, 2, 0")


func test_team_standings_full_tie_goes_to_the_lowest_team_id() -> void:
	var s: MatchState = _teams_state([3, 3, 1, 2])
	assert_eq(Simulation.team_standings(s), [1, 2, 3] as Array[int])


func test_team_standings_3v1_sums_across_the_trio() -> void:
	var s: MatchState = _teams_state([0, 0, 0, 1])
	_set_score(s, 0, 1, 20, 0)
	_set_score(s, 1, 1, 20, 1)
	_set_score(s, 2, 1, 20, 0)
	_set_score(s, 3, 1, 59, 3)
	assert_eq(Simulation.team_standings(s), [0, 1] as Array[int], "60 > 59")
	_set_score(s, 3, 1, 61, 0)
	assert_eq(Simulation.team_standings(s), [1, 0] as Array[int])


func test_team_standings_uses_the_highest_member_win_count() -> void:
	var s: MatchState = _teams_state([0, 0, 1])
	_set_score(s, 0, 0, 0, 0)
	_set_score(s, 1, 2, 0, 0)
	_set_score(s, 2, 1, 0, 0)
	assert_eq(Simulation.team_standings(s), [0, 1] as Array[int])


func test_team_standings_after_real_rounds_shares_wins() -> void:
	var st: MatchSettings = _settings(4, [0, 1, 1, 0])
	st.rounds = 3
	var s: MatchState = U.started_match(st)
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, -1, 0, 1000, "explosion", 0, ev)
	Simulation.apply_damage(s, -1, 3, 1000, "explosion", 0, ev)
	s.current_tank = 1
	Simulation.apply_action(s, U.pass_turn(1))
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq([s.tanks[0].round_wins, s.tanks[1].round_wins, s.tanks[2].round_wins, s.tanks[3].round_wins], [0, 1, 1, 0])
	assert_eq(Simulation.team_standings(s), [1, 0] as Array[int])
	assert_eq(Simulation.standings(s).size(), 4, "per-tank standings are unchanged")
