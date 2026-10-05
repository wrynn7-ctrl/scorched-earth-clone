@warning_ignore_start("integer_division")
extends GutTest
## M6-A (docs/ARCHITECTURE.md section 41): the AI with teams and sudden death.
##  * targets are enemies (other team) only: target choice, aim, weapon choice, the out-of-reach rule, memory;
##  * the self-damage guard protects teammates while friendly fire is on and ignores them while it is off
##    (itself always protected);
##  * in sudden death the AI never passes, and the guard still holds;
##  * matches without teams are unchanged (the other AI tests and the golden fixtures prove that).

const LEVEL_NAMES: Array[String] = ["", "Easy", "Normal", "Hard", "Expert"]
## Shots per (setup, level) cell of the statistics tables.
const SHOTS_WANTED: int = 500
const MAX_MATCHES: int = 60
## Teammate-hit ceilings (share of shots, per mille) for friendly fire on: Hard/Expert, Easy/Normal.
const ALLY_HIT_MAX_HARD: int = 20
const ALLY_HIT_MAX_EASY: int = 60


# --- scenario helpers ---------------------------------------------------------------------------------

## A flat field with `xs.size()` tanks at `xs`, tank 0 the CPU at `level` (the others idle humans),
## `teams` per tank, friendly fire as given. Tank 0 owns the given stock.
func _field(xs: Array[int], teams: Array[int], level: int, ff: bool, stock: Dictionary) -> MatchState:
	var state: MatchState = SimTestUtil.flat_state(xs.size())
	var ctrl := PackedInt32Array()
	var team_list := PackedInt32Array()
	for i: int in range(xs.size()):
		state.tanks[i].x = xs[i]
		state.tanks[i].team = teams[i]
		state.tanks[i].set_stock("pulse_missile", 0)
		ctrl.append(level if i == 0 else SimConstants.CTRL_HUMAN)
		team_list.append(teams[i])
	state.settings.controllers = ctrl
	state.settings.teams = team_list
	state.settings.friendly_fire = ff
	state.settings.num_tanks = xs.size()
	for id: String in stock.keys():
		state.tanks[0].set_stock(id, stock[id])
	return state


func _sit(state: MatchState, level: int) -> AiSituation:
	var me: TankState = state.tanks[0]
	return AiPlayer.situation(state, me, level, AiProfile.for_level(level), AiTargets.enemies_of(state, me))


func _damage_to(events: Array[Dictionary], tank: int) -> int:
	var total: int = 0
	for e: Dictionary in events:
		if e["type"] == "damage" and (e["tank"] as int) == tank:
			total += e["amount"] as int
	return total


# --- targets are enemies only --------------------------------------------------------------------------

func test_enemies_of_and_target_choice_use_the_team_not_the_id() -> void:
	# Teams [A, B, A, B]: tank 2 (higher id than enemy 1) is my teammate.
	var state: MatchState = _field([300, 700, 900, 1200], [0, 1, 0, 1], 4, true, {})
	var me: TankState = state.tanks[0]
	var ids: Array[int] = []
	for e: TankState in AiTargets.enemies_of(state, me):
		ids.append(e.id)
	assert_eq(ids, [1, 3], "enemies are the other team: tanks 1 and 3")
	for level: int in [1, 2, 3, 4]:
		var picked: TankState = AiTargets.pick(state, me, level)
		assert_ne(picked.team, me.team, "level %d picked an enemy" % level)
	# The teammate is the nearest tank to me, yet the nearest ENEMY is the target of Easy.
	state.tanks[2].x = 340
	assert_eq(AiTargets.pick(state, me, 1).id, 1, "Easy shoots the nearest enemy, not the nearer teammate")
	assert_eq(AiTargets.nearest_tank_to_x(state, me, 345), 1, "the 'last shot' memory reads enemies only")


func test_last_shot_memory_is_keyed_by_the_enemy_not_a_teammate_beside_it() -> void:
	# A shell that came down 30 cells short of the enemy with my teammate standing 6 cells from that impact still
	# reads as a miss at the enemy (and is corrected), instead of "a shot at the teammate".
	var state: MatchState = _field([300, 1000, 970], [0, 1, 0], 4, true, {"pulse_missile": 10})
	var me: TankState = state.tanks[0]
	me.last_fire_weapon = Catalog.index_of("pulse_missile")
	me.last_fire_x = 976
	me.last_fire_y = me.y
	me.last_fire_angle = 450
	me.last_fire_power = 500
	me.last_fire_turn = 0
	state.turn_number = 1
	var sit: AiSituation = _sit(state, 4)
	assert_eq(sit.target.id, 1)
	assert_false(sit.corr.is_empty(), "the last shot is read as a miss at the enemy")


func test_a_cpu_never_shoots_at_a_teammate_even_when_it_is_the_nearest_tank() -> void:
	# Teammate 20 cells away on flat ground, the only enemy far away: every level lands near the enemy side.
	var cases: int = 0
	var bad: int = 0
	for level: int in [1, 2, 3, 4]:
		for ff: bool in [true, false]:
			for k: int in range(5):
				var enemy_x: int = 900 + 60 * k
				var state: MatchState = _field([300, 330, enemy_x], [0, 0, 1], level, ff, {"pulse_missile": 20})
				var turn: Dictionary = AiTestUtil.play_turn(state, 0)
				cases += 1
				if turn["action"].get("kind", "") != "fire":
					continue
				var landed: int = -1
				for e: Dictionary in (turn["events"] as Array[Dictionary]):
					if e["type"] == "projectile_end":
						landed = e["x"]
						break
				# Aimed at the enemy: it comes down nearer to the enemy than to the teammate (or flies off the map).
				if landed >= 0 and absi(landed - enemy_x) > absi(landed - 330):
					bad += 1
				assert_eq(_damage_to(turn["events"], 1), 0, "level %d: the teammate was not hurt" % level)
	gut.p("TEAMS   nearest-tank-is-a-teammate duels: %d shots, %d came down nearer the teammate than the enemy" % [cases, bad])
	assert_eq(bad, 0)


func test_out_of_reach_walks_towards_the_nearest_enemy_not_a_teammate() -> void:
	# The enemy is 1400 cells away behind a tall ridge in a headwind, a teammate stands close on the LEFT: whatever
	# walk the CPU makes must go right (towards the enemy).
	var moves: int = 0
	for level: int in [1, 2, 3, 4]:
		var state: MatchState = _field([200, 150, 1600 - 100], [0, 0, 1], level, true, {})
		state.tanks[0].fuel = 200
		state.terrain.flatten(740, 860, 80)
		for t: TankState in state.tanks:
			t.y = TankState.rest_y(state.terrain, t.x)
		state.wind = -100
		for _i: int in range(2):
			var a: Dictionary = AiPlayer.next_action(state, 0)
			if a["kind"] == "move":
				moves += 1
				assert_gt(a["dx"], 0, "level %d walks towards the enemy (right), not the teammate" % level)
				Simulation.apply_action(state, a)
	gut.p("TEAMS   out of reach with a teammate on the far side: %d walks, all towards the enemy" % moves)
	assert_gt(moves, 0, "the scenario really makes the CPUs walk")


func test_a_lone_teammate_left_means_the_cpu_has_nobody_to_shoot_at_but_does_not_crash() -> void:
	var state: MatchState = _field([300, 900], [0, 0], 4, true, {})
	state.settings.teams = PackedInt32Array([0, 0])
	assert_true(AiTargets.enemies_of(state, state.tanks[0]).is_empty())
	assert_eq(AiPlayer.next_action(state, 0)["kind"], "pass", "no enemy alive: the round is over, a pass is legal")


# --- the self-damage guard with teams --------------------------------------------------------------------

func test_guard_counts_a_teammate_by_team_with_friendly_fire_on() -> void:
	# Teams [A, B, A]: tank 2 stands next to enemy 1. A Nova on the enemy would splash the teammate.
	for level: int in [1, 2, 3, 4]:
		var state: MatchState = _field([300, 1000, 1030], [0, 1, 0], level, true, {"nova_core": 3, "hyperpulse": 3})
		var sit: AiSituation = _sit(state, level)
		assert_eq(sit.target.id, 1)
		var h: Dictionary = AiWeapons.estimate_harm(sit, AiWeapons.plan_for(sit, "nova_core"), "nova_core")
		assert_gt(h["self"], 0, "level %d: the teammate counts as harm with friendly fire on" % level)
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		assert_eq(_damage_to(turn["events"], 2), 0, "level %d: teammate not hurt" % level)


func test_guard_ignores_a_teammate_with_friendly_fire_off_and_still_protects_itself() -> void:
	for level: int in [1, 2, 3, 4]:
		var on: MatchState = _field([300, 1000, 1030], [0, 1, 0], level, true, {"nova_core": 3, "hyperpulse": 3})
		var off: MatchState = _field([300, 1000, 1030], [0, 1, 0], level, false, {"nova_core": 3, "hyperpulse": 3})
		var sit_on: AiSituation = _sit(on, level)
		var sit_off: AiSituation = _sit(off, level)
		var h_on: Dictionary = AiWeapons.estimate_harm(sit_on, AiWeapons.plan_for(sit_on, "nova_core"), "nova_core")
		var h_off: Dictionary = AiWeapons.estimate_harm(sit_off, AiWeapons.plan_for(sit_off, "nova_core"), "nova_core")
		assert_gt(h_on["self"], 0)
		assert_eq(h_off["self"], 0, "level %d: a teammate cannot be hurt, so it is no harm" % level)
		assert_eq(h_on["enemy"], h_off["enemy"], "the enemy side of the estimate is unchanged")
		# Self is always protected: the shooter 30 cells from the enemy would take the blast itself.
		var close: MatchState = _field([300, 330, 1000], [0, 1, 0], level, false, {"nova_core": 3, "hyperpulse": 3})
		var sc: AiSituation = _sit(close, level)
		var hc: Dictionary = AiWeapons.estimate_harm(sc, AiWeapons.plan_for(sc, "nova_core"), "nova_core")
		assert_gt(hc["self"], 0, "level %d: self damage still counts with friendly fire off" % level)


func test_an_enemy_next_to_a_teammate_is_shot_only_when_friendly_fire_is_off() -> void:
	var fired_off: int = 0
	var refused_on: int = 0
	var cases: int = 0
	var lines: String = ""
	for level: int in [2, 3, 4]:
		for enemy_gap: int in [28, 40]:
			var on: MatchState = _field([300, 1000, 1000 + enemy_gap], [0, 0, 1], level, true,
					{"nova_core": 3, "hyperpulse": 3, "pulse_missile": 3})
			var off: MatchState = _field([300, 1000, 1000 + enemy_gap], [0, 0, 1], level, false,
					{"nova_core": 3, "hyperpulse": 3, "pulse_missile": 3})
			var t_on: Dictionary = AiTestUtil.play_turn(on, 0)
			var t_off: Dictionary = AiTestUtil.play_turn(off, 0)
			cases += 1
			var strong_off: bool = t_off["action"]["kind"] == "fire" and t_off["action"]["weapon"] != "spark_dart"
			var enemy_hit_off: bool = _damage_to(t_off["events"], 2) > 0
			var strong_on: bool = t_on["action"]["kind"] == "fire" and t_on["action"]["weapon"] != "spark_dart" \
					and _damage_to(t_on["events"], 1) > 0
			if strong_off and enemy_hit_off:
				fired_off += 1
			if not strong_on:
				refused_on += 1
			lines += "          level %d gap %2d: off -> %s %s, enemy damage %d | on -> %s %s, teammate damage %d\n" % [
					level, enemy_gap, t_off["action"]["kind"], t_off["action"].get("weapon", "-"), _damage_to(t_off["events"], 2),
					t_on["action"]["kind"], t_on["action"].get("weapon", "-"), _damage_to(t_on["events"], 1)]
			assert_eq(_damage_to(t_on["events"], 1), 0, "friendly fire on: the teammate is never splashed (level %d)" % level)
	gut.p(("TEAMS   enemy beside a teammate, friendly fire off vs on (%d cases): off fired a real shot that hurt the enemy in %d, "
			+ "on refused the splashy shot in %d\n%s") % [cases, fired_off, refused_on, lines])
	assert_gte(fired_off, cases - 2, "with friendly fire off the shot is taken (almost always)")
	assert_gte(refused_on, cases - 1, "with friendly fire on the splashy shot is refused")


# --- items and weapons ----------------------------------------------------------------------------------

func test_shield_and_repair_choices_are_unchanged_by_teams() -> void:
	for level: int in [2, 3, 4]:
		for teams_on: bool in [false, true]:
			var xs: Array[int] = [300, 1000, 1400]
			var tm: Array[int] = [0, 1, 2]
			if teams_on:
				tm = [0, 1, 0]
			var state: MatchState = _field(xs, tm, level, true, {"pulse_missile": 5, "ion_shield": 1, "nanorepair_kit": 1})
			state.tanks[0].health = 15
			var a: Dictionary = AiPlayer.next_action(state, 0)
			if level == 2:
				assert_eq(a["kind"], "use_item", "Normal raises a shield when hurt")
				assert_eq(a["item"], "ion_shield")
			else:
				assert_eq(a["kind"], "use_item")
				assert_eq(a["item"], "nanorepair_kit", "Hard/Expert heal at critical health (teams %s)" % str(teams_on))


func test_a_seeker_is_only_chosen_for_the_nearest_enemy() -> void:
	# The nearest tank is a teammate: a Seeker would lock onto the nearest ENEMY, which must be the target.
	var state: MatchState = _field([300, 360, 800, 1300], [0, 0, 1, 1], 3, true, {"seeker": 3, "pulse_missile": 5})
	state.wind = 80
	var sit: AiSituation = _sit(state, 3)
	assert_eq(sit.nearest_id, 2, "nearest enemy, not the teammate at 360")
	var ids: Array[String] = AiWeapons._candidates(sit)
	if sit.target.id != 2:
		assert_false(ids.has("seeker"), "a Seeker is not used on a target that is not the nearest enemy")


func test_every_action_in_a_team_setup_is_a_legal_ordinary_action() -> void:
	var checked: int = 0
	for i: int in range(40):
		var r: Rng = Rng.derive(i * 13 + 1, 5150)
		var n: int = r.range_int(3, 6)
		var settings := MatchSettings.new()
		settings.seed = 800 + i
		settings.num_tanks = n
		settings.rounds = 2
		var ctrl := PackedInt32Array()
		var teams := PackedInt32Array()
		for k: int in range(n):
			ctrl.append(r.range_int(1, 4))
			teams.append(k % 2)
		settings.controllers = ctrl
		settings.teams = teams
		settings.friendly_fire = r.chance(1, 2)
		var state: MatchState = Simulation.new_match(settings)
		SimTestUtil.begin_round(state)
		for k: int in range(8):
			if state.phase != SimConstants.PHASE_AIM:
				break
			var turn: Dictionary = AiTestUtil.play_turn(state, state.current_tank)
			assert_lte(turn["calls"], 3, "a turn ends within 3 calls")
			checked += 1
	gut.p("TEAMS   %d team turns checked: each ended within 3 calls with a legal action" % checked)


# --- statistics ----------------------------------------------------------------------------------------

func _stats(setup: String, teams: PackedInt32Array, level: int, ff: bool, wanted: int = SHOTS_WANTED) -> Dictionary:
	var shots: int = 0
	var ally: int = 0
	var selfhit: int = 0
	var target_ok: bool = true
	var errors: int = 0
	var max_round_turns: int = 0
	var stalled: int = 0
	var passes: int = 0
	var sudden_passes: int = 0
	var sudden_turns: int = 0
	var matches: int = 0
	var ctrl := PackedInt32Array()
	for _i: int in range(teams.size()):
		ctrl.append(level)
	while shots < wanted and matches < MAX_MATCHES:
		var r: Dictionary = AiTestUtil.run_team_match(1000 * level + 17 * matches + (7 if ff else 0), ctrl, teams, ff, 3)
		matches += 1
		shots += r["shots"] as int
		ally += r["ally_hit_shots"] as int
		selfhit += r["self_hit_shots"] as int
		target_ok = target_ok and (r["enemy_target_ok"] as bool)
		errors += (r["errors"] as Array[String]).size()
		max_round_turns = maxi(max_round_turns, r["max_round_turns"] as int)
		stalled += 1 if r["stalled"] else 0
		passes += r["passes"] as int
		sudden_passes += r["sudden_passes"] as int
		sudden_turns += r["sudden_turns"] as int
	return {"sudden_passes": sudden_passes, "sudden_turns": sudden_turns, "setup": setup, "level": level, "ff": ff, "shots": shots, "ally": ally, "self": selfhit, "ok": target_ok,
			"errors": errors, "max_round_turns": max_round_turns, "stalled": stalled, "passes": passes, "matches": matches}


func _table(title: String, rows: Array[Dictionary]) -> String:
	var text: String = title + "\n"
	text += "          setup  level   ff   matches  shots  ally-hit shots (rate)  self-hit shots  passes  sudden-death turns (passes)  longest round\n"
	for r: Dictionary in rows:
		var shots: int = r["shots"]
		text += "          %-5s  %-6s %-4s %7d %6d %9d (%d.%d%%) %14d %7d %12d (%d) %14d\n" % [r["setup"], LEVEL_NAMES[r["level"]],
				"on" if r["ff"] else "off", r["matches"], shots, r["ally"], (r["ally"] as int) * 100 / maxi(1, shots),
				((r["ally"] as int) * 1000 / maxi(1, shots)) % 10, r["self"], r["passes"], r["sudden_turns"], r["sudden_passes"], r["max_round_turns"]]
	return text


func test_team_matches_never_target_a_teammate_and_teammate_hits_are_rare_with_friendly_fire_on() -> void:
	var rows: Array[Dictionary] = []
	var setups: Array[Array] = [["2v2", PackedInt32Array([0, 1, 0, 1])], ["3v1", PackedInt32Array([0, 0, 0, 1])]]
	for s: Array in setups:
		for level: int in [1, 2, 3, 4]:
			var row: Dictionary = _stats(s[0], s[1], level, true)
			rows.append(row)
			assert_true(row["ok"], "%s level %d: every decision picked an enemy" % [row["setup"], level])
			assert_gte(row["shots"], SHOTS_WANTED, "%s level %d: at least %d shots" % [row["setup"], level, SHOTS_WANTED])
			assert_eq(row["errors"], 0, "no illegal action")
			assert_eq(row["stalled"], 0, "rounds end")
			assert_eq(row["sudden_passes"], 0, "%s level %d: never passes in sudden death" % [row["setup"], level])
			var limit: int = ALLY_HIT_MAX_HARD if level >= 3 else ALLY_HIT_MAX_EASY
			assert_lte((row["ally"] as int) * 1000, limit * (row["shots"] as int),
					"%s level %d: teammate-hit rate %d / %d shots over %d per mille" % [row["setup"], level, row["ally"], row["shots"], limit])
			assert_eq(row["self"], 0, "%s level %d: no self hits" % [row["setup"], level])
	gut.p(_table("TEAMS   friendly fire ON, all seats the same level, 3 rounds per match:", rows))


func test_team_matches_with_friendly_fire_off_run_clean() -> void:
	var rows: Array[Dictionary] = []
	var setups: Array[Array] = [["2v2", PackedInt32Array([0, 1, 0, 1])], ["3v1", PackedInt32Array([0, 0, 0, 1])]]
	for s: Array in setups:
		for level: int in [1, 2, 3, 4]:
			var row: Dictionary = _stats(s[0], s[1], level, false, 250)
			rows.append(row)
			assert_true(row["ok"])
			assert_eq(row["errors"], 0)
			assert_eq(row["stalled"], 0, "rounds end")
			assert_eq(row["sudden_passes"], 0, "never passes in sudden death")
			assert_eq(row["self"], 0, "%s level %d: no self hits with friendly fire off either" % [row["setup"], level])
	gut.p(_table("TEAMS   friendly fire OFF (teammate hits are ignored by the core, so 'ally-hit' counts nothing):", rows))


func test_mixed_level_team_matches_end_and_report_the_longest_round() -> void:
	var longest: int = 0
	var sudden_rounds: int = 0
	var played: int = 0
	var passes: int = 0
	for m: int in range(12):
		var ctrl := PackedInt32Array([1 + m % 4, 1 + (m + 1) % 4, 1 + (m + 2) % 4, 1 + (m + 3) % 4])
		var teams := PackedInt32Array([0, 1, 0, 1]) if m % 3 != 2 else PackedInt32Array([0, 0, 0, 1])
		var r: Dictionary = AiTestUtil.run_team_match(4000 + m, ctrl, teams, m % 2 == 0, 3)
		assert_eq(r["errors"], [], "match %d legal" % m)
		assert_false(r["stalled"], "match %d finished" % m)
		assert_eq(r["state"].phase, SimConstants.PHASE_MATCH_OVER)
		assert_eq(r["sudden_passes"], 0, "match %d: no pass in sudden death" % m)
		assert_lte(r["max_calls"], 3)
		longest = maxi(longest, r["max_round_turns"] as int)
		played += r["rounds_played"] as int
		passes += r["passes"] as int
		if (r["sudden_turns"] as int) > 0:
			sudden_rounds += 1
	gut.p("TEAMS   12 mixed-level team matches (%d rounds): longest round %d turns (sudden death at %d for 4 tanks); matches that reached sudden death %d; passes %d"
			% [played, longest, 40, sudden_rounds, passes])
	assert_lte(longest, 400, "no round runs on for ever")


# --- sudden death ---------------------------------------------------------------------------------------

func _sudden(state: MatchState) -> void:
	state.turn_number = Simulation.sudden_death_turn(state.settings)


func test_in_sudden_death_the_cpu_never_passes_at_any_range_and_never_hurts_itself() -> void:
	# Packed fields (tanks 24-30 cells apart, enemies beside teammates) where a CPU outside sudden death refuses to
	# shoot with friendly fire on, plus the old point-blank duels.
	var layouts: Array[Array] = [
		[[300, 330, 360], [0, 0, 1]], [[300, 324, 348], [0, 0, 1]], [[300, 330, 360, 390], [0, 0, 1, 0]],
		[[300, 326, 352, 378], [0, 1, 0, 1]], [[300, 326, 352, 378, 404], [0, 1, 0, 1, 1]], [[300, 340, 380], [0, 1, 0]],
		[[300, 330], [0, 1]], [[300, 350], [0, 1]], [[300, 380], [0, 1]], [[300, 330, 1500], [0, 1, 1]]]
	var cases: int = 0
	var passes_normal: int = 0
	var self_hits: int = 0
	var fires: int = 0
	for level: int in [1, 2, 3, 4]:
		for layout: Array in layouts:
			for ff: bool in [true, false]:
				var xs: Array[int] = []
				for x: int in (layout[0] as Array):
					xs.append(x)
				var tm: Array[int] = []
				for t: int in (layout[1] as Array):
					tm.append(t)
				var state: MatchState = _field(xs, tm, level, ff, {"nova_core": 5, "hyperpulse": 5})
				if AiPlayer.next_action(state.duplicate_state(), 0)["kind"] == "pass":
					passes_normal += 1
				_sudden(state)
				var turn: Dictionary = AiTestUtil.play_turn(state, 0)
				cases += 1
				assert_ne(turn["action"].get("kind", ""), "pass", "level %d layout %s (ff %s): sudden death never passes" % [level, str(xs), str(ff)])
				assert_lte(turn["calls"], 3)
				if turn["action"].get("kind", "") == "fire":
					fires += 1
				if _damage_to(turn["events"], 0) > 0:
					self_hits += 1
	gut.p("SUDDEN  packed-field sweep (%d cases): %d fires, 0 passes (the same cases outside sudden death: %d passes), self hits %d" % [
			cases, fires, passes_normal, self_hits])
	assert_gt(passes_normal, 0, "the sweep really contains cases where the ordinary rule would pass")
	assert_eq(self_hits, 0, "the guard still holds in sudden death")


func test_sudden_death_does_not_change_an_ordinary_good_shot() -> void:
	# (The rng stream depends on the turn number, so only the choice, not the exact noise, is compared.)
	for level: int in [1, 2, 3, 4]:
		var a: MatchState = _field([300, 900], [0, 1], level, true, {"pulse_missile": 5})
		var b: MatchState = _field([300, 900], [0, 1], level, true, {"pulse_missile": 5})
		_sudden(b)
		var x: Dictionary = AiPlayer.next_action(a, 0)
		var y: Dictionary = AiPlayer.next_action(b, 0)
		assert_eq(y["kind"], "fire")
		assert_eq(x["kind"], y["kind"], "level %d: both fire" % level)
		assert_eq(x["weapon"], y["weapon"], "level %d: same weapon when the guard is happy" % level)
		assert_lt(absi((x["power"] as int) - (y["power"] as int)), 120, "level %d: about the same power" % level)


func test_sudden_death_never_applies_in_love_mode() -> void:
	var settings := MatchSettings.new()
	settings.mode = SimConstants.MODE_LOVE
	settings.controllers = PackedInt32Array([2, 2])
	var state: MatchState = Simulation.new_match(settings)
	state.turn_number = 500
	assert_false(AiPlayer.in_sudden_death(state))


func test_team_decisions_are_deterministic_and_survive_a_state_copy() -> void:
	var compared: int = 0
	for i: int in range(30):
		var r: Rng = Rng.derive(i + 3, 6161)
		var level: int = r.range_int(1, 4)
		var ff: bool = r.chance(1, 2)
		var state: MatchState = _field([300, 700 + r.range_int(0, 300), 1100 + r.range_int(0, 200), 1400], [0, 1, 0, 1],
				level, ff, {"pulse_missile": 5, "nova_core": 2})
		state.wind = r.range_int(-100, 100)
		if i % 3 == 0:
			_sudden(state)
		var a: Dictionary = AiPlayer.next_action(state, 0)
		var b: Dictionary = AiPlayer.next_action(state.duplicate_state(), 0)
		assert_eq(a, b, "case %d: same state, same action" % i)
		compared += 1
	gut.p("TEAMS   %d team states: identical action from the state and from a copy of it" % compared)
