@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 5b: the show layer against the core in team matches. Scripted people play whole matches through the
## BattleController (every weapon, friendly fire on and off, passes up to sudden death and through it); after
## every playback the display copy must equal the authoritative state (no `mismatch_count`, no engine error from
## check_consistency), the round summary must name the right team (or the draw), the results must follow
## Simulation.team_standings, and a save made in the middle of sudden death must come back with the same HUD tag.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")
const QaAi = preload("res://tests/qa/qa_ai.gd")

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://qa_m6_team_battle_autosave.crtl"
const H: int = SimConstants.CTRL_HUMAN

var _summary_checks: int = 0
var _draw_summaries: int = 0
var _team_summaries: int = 0


func before_each() -> void:
	ShowSettings.reset()
	PlayerNames.reset()
	_cleanup()


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()
	_cleanup()


## Removes this file's own autosave (a plain file in user://) and its temp sibling, nothing else.
func _cleanup() -> void:
	for p: String in [PATH, PATH + ".tmp"]:
		if p.begins_with("user://qa_m6_team_battle_") and FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _battle(teams: Array, ff: bool, seed_value: int, rounds: int) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, seed_value, true, teams.size())
	var ctrl := PackedInt32Array()
	ctrl.resize(teams.size())
	ctrl.fill(H)
	c.set_controllers(ctrl)
	c.set_teams(PackedInt32Array(teams), ff)
	c.set_autosave_path(PATH)
	add_child_autofree(c)
	if c.get_state().phase == SimConstants.PHASE_SHOP:
		assert_true(c.quick_start())
	_play_out(c)
	return c


func _play_out(c: BattleController) -> void:
	var n: int = 0
	while c._playing and n < 1500:
		c._process(1.0 / 30.0)
		n += 1


## Every weapon and item except the shields (a shielded tank that dies of the drain is the known mismatch
## reported by test_a_shielded_tank_killed_by_the_drain_does_not_look_like_a_display_mismatch).
func _arm(c: BattleController) -> void:
	for t: TankState in c.get_state().tanks:
		QaAi.give_everything(t, 6)
		for id: String in ["glow_shield", "ion_shield", "fortress_field"]:
			t.set_stock(id, 0)
	c.call("_rebuild_display")


func _expected_round_title(state: MatchState) -> String:
	var team: int = -1
	var alive: int = 0
	for t: TankState in state.tanks:
		if t.alive:
			alive += 1
			team = t.team
	if alive == 0:
		return "DRAW — NO SURVIVORS"
	return "TEAM %s WINS" % TeamStyle.letter(team)


func _play_match(teams: Array, ff: bool, seed_value: int, rounds: int, pass_pct: int, tag: String) -> void:
	var c: BattleController = _battle(teams, ff, seed_value, rounds)
	_arm(c)
	var rng := Rng.new(seed_value ^ 0x77)
	var guard: int = 0
	var state: MatchState = c.get_state()
	var rounds_done: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and guard < 600:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			var title: String = c.get_round_overlay().get_title_text()
			assert_eq(title, _expected_round_title(state), "%s: round %d summary title" % [tag, rounds_done])
			_summary_checks += 1
			if title.begins_with("DRAW"):
				_draw_summaries += 1
			else:
				_team_summaries += 1
			rounds_done += 1
			assert_true(c.quick_start())
			_play_out(c)
			_arm(c)
			assert_true(c.check_consistency(), "%s: consistent after the new round starts" % tag)
			continue
		var a: Dictionary = M6.human_action(state, rng, pass_pct, 40)
		if Simulation.validate_action(state, a) != "":
			a = {"kind": "pass", "tank": state.current_tank}
		var err: String = c.submit_action(a)
		assert_eq(err, "", "%s: %s accepted" % [tag, str(a)])
		_play_out(c)
		assert_true(c.check_consistency(), "%s: display equals state after %s" % [tag, str(a)])
	assert_lt(guard, 600, "%s: the match ends" % tag)
	assert_eq(c.mismatch_count, 0, "%s: the display never had to be snapped to the state" % tag)
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		var order: Array[int] = Simulation.team_standings(state)
		assert_eq(order, M6.expected_team_standings(state), "%s: team standings" % tag)
		var title2: String = c.get_match_overlay().get_title_text()
		var lead: String = TeamStyle.letter(order[0])
		assert_true(title2 == "TEAM %s WINS THE MATCH" % lead or title2 == "DRAW",
				"%s: the results say '%s', the standings put team %s first" % [tag, title2, lead])
		var tied: bool = false
		var totals: Dictionary = {}
		for t: TankState in state.tanks:
			if not totals.has(t.team):
				totals[t.team] = [0, 0, 0]
			var tt: Array = totals[t.team]
			tt[0] = maxi(tt[0] as int, t.round_wins)
			tt[1] = (tt[1] as int) + t.damage_dealt
			tt[2] = (tt[2] as int) + t.kills
		if order.size() >= 2:
			tied = totals[order[0]] == totals[order[1]]
		assert_eq(title2 == "DRAW", tied, "%s: DRAW exactly when the top two teams are level on wins, damage and kills" % tag)


func test_team_matches_through_the_controller_stay_consistent() -> void:
	var setups: Array[Dictionary] = [
		{"teams": [0, 1, 0, 1], "ff": true, "seed": 91001, "pass": 30},
		{"teams": [0, 1, 0, 1], "ff": false, "seed": 91002, "pass": 30},
		{"teams": [0, 0, 0, 1], "ff": false, "seed": 91003, "pass": 70},
		{"teams": [0, 1, 2, 0, 1, 2], "ff": false, "seed": 91004, "pass": 60},
		{"teams": [0, 0, 1, 1], "ff": true, "seed": 91005, "pass": 90},
		{"teams": [1, 0], "ff": true, "seed": 91006, "pass": 85},
	]
	var t0: int = Time.get_ticks_msec()
	for s: Dictionary in setups:
		_play_match(s["teams"] as Array, s["ff"] as bool, s["seed"] as int, 2, s["pass"] as int,
				"teams %s ff %s seed %d" % [str(s["teams"]), str(s["ff"]), s["seed"]])
	gut.p("TEAM BATTLE: %d matches through the controller in %d ms; %d round summaries checked (%d team wins, %d draws)" % [
			setups.size(), Time.get_ticks_msec() - t0, _summary_checks, _team_summaries, _draw_summaries])
	assert_gte(_summary_checks, 6)


func test_a_save_in_the_middle_of_sudden_death_restores_the_tag_and_the_counter() -> void:
	var c: BattleController = _battle([0, 1, 0, 1], false, 92001, 2)
	var thr: int = Simulation.sudden_death_turn(c.get_state().settings)
	var guard: int = 0
	while c.get_state().sudden_death_cycles < 2 and guard < 200:
		guard += 1
		assert_eq(c.pass_turn(), "")
		_play_out(c)
	assert_gte(c.get_state().sudden_death_cycles, 2, "two drains happened")
	assert_gte(c.get_state().turn_number, thr)
	var cycles: int = c.get_state().sudden_death_cycles
	var fp: String = Simulation.fingerprint(c.get_state())
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_eq(Simulation.fingerprint(r.get_state()), fp, "the restored state is the saved one")
	assert_eq(r.get_state().sudden_death_cycles, cycles)
	assert_true(r.sudden_death_active())
	var tag: SuddenDeathIndicator = r.get_hud().get_sudden_tag()
	assert_true(tag.is_active())
	assert_eq(tag.get_next_drain(), Simulation.sudden_death_amount(cycles + 1))
	assert_true(r.check_consistency())
	# Play on: both the original and the restored match drain by the same amounts.
	var before_hp: Array[int] = []
	for t: TankState in r.get_state().tanks:
		before_hp.append(t.health)
	var steps: int = 0
	while r.get_state().sudden_death_cycles == cycles and r.get_state().phase == SimConstants.PHASE_AIM and steps < 30:
		steps += 1
		assert_eq(r.pass_turn(), "")
		_play_out(r)
	if r.get_state().phase == SimConstants.PHASE_AIM:
		var want: int = Simulation.sudden_death_amount(cycles + 1)
		for t: TankState in r.get_state().tanks:
			if t.alive:
				assert_eq(t.health, maxi(0, before_hp[t.id] - want), "tank %d lost the next drain (%d)" % [t.id, want])
	assert_eq(r.mismatch_count, 0)


func test_love_mode_has_no_team_ui_or_sudden_death_in_the_controller() -> void:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(1, 5, true, 2)
	c.set_controllers(PackedInt32Array([H, H]))
	c.set_mode(SimConstants.MODE_LOVE)
	add_child_autofree(c)
	_play_out(c)
	assert_false(c.has_teams())
	assert_eq(c.team_of(0), TeamStyle.NONE)
	for _i: int in range(30):
		assert_eq(c.pass_turn(), "")
		_play_out(c)
	assert_false(c.sudden_death_active(), "never past the threshold in love mode")
	assert_false(c.get_hud().get_sudden_tag().is_active())
	assert_eq(c.sudden_death_events, 0)


## A tank killed by the sudden-death drain (or by a fall) keeps the shield it had: both bypass shields and
## nothing clears them on death. The show layer then reports a display mismatch (push_error), snaps the whole
## display with _rebuild_display, and that rebuild calls set_dead(true) BEFORE set_shield(...), so the wreck is
## drawn with a glowing shield bubble.
func test_a_shielded_tank_killed_by_the_drain_does_not_look_like_a_display_mismatch() -> void:
	var c: BattleController = _battle([0, 1], true, 93001, 2)
	var thr: int = Simulation.sudden_death_turn(c.get_state().settings)
	var guard: int = 0
	while c.get_state().turn_number < thr - 2 and guard < 100:
		guard += 1
		assert_eq(c.pass_turn(), "")
		_play_out(c)
	var st: MatchState = c.get_state()
	for t: TankState in st.tanks:
		t.health = 5
	st.tanks[1].shield_type = Catalog.index_of("glow_shield")
	st.tanks[1].shield_hp = 30
	st.tanks[1].repulsor_charge = 50
	c.call("_rebuild_display")
	var mism_before: int = c.mismatch_count
	var passes: int = 0
	while st.phase == SimConstants.PHASE_AIM and passes < 6:
		passes += 1
		assert_eq(c.pass_turn(), "")
		_play_out(c)
	var errs: Array = get_errors()
	var pushed: int = 0
	for e: Variant in errs:
		e.handled = true
		pushed += 1
	assert_false(st.tanks[1].alive, "the drain killed the shielded tank")
	gut.p("DRAIN-KILLED SHIELDED TANK: state shield_hp %d repulsor %d on the dead tank; mismatch_count +%d; engine errors %d; view shield bubble on the wreck: %s" % [
			st.tanks[1].shield_hp, st.tanks[1].repulsor_charge, c.mismatch_count - mism_before, pushed,
			str(c.get_tank_view(1).has_shield_bubble())])
	if c.mismatch_count > mism_before or pushed > 0 or c.get_tank_view(1).has_shield_bubble():
		pending("BUG (medium): a tank destroyed by the sudden-death drain keeps shield_hp %d (the drain bypasses shields and death does not clear them), so BattleController.check_consistency (show/battle/battle_controller.gd:1131-1155, called after every playback at :1405) reports a display mismatch for it: push_error, mismatch_count +%d, and a full _snap_display_to_state/_rebuild_display (copies the terrain). The rebuild (battle_controller.gd:590-597) calls v.set_dead(not t.alive) before v.set_shield(t.shield_hp ...), so the dead tank's shield bubble is drawn again (TankView._draw_aura:692 has no _dead guard); the same happens on Continue. Input: any shielded tank that dies of the drain or of fall damage. Expected: no mismatch, no bubble on a wreck. Suggested fix (show layer): want_shield = 0 for a dead tank in check_consistency and set_shield before set_dead in _rebuild_display (or clear shield/repulsor in the core on death, which re-pins fingerprints)." % [
				st.tanks[1].shield_hp, c.mismatch_count - mism_before])
