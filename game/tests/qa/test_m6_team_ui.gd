@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 5: team UI invariants on the setup screen (sections 39 and 42), headless.
##  - START is enabled iff the teams are valid, for random chip states, player counts and free / full tier,
##    judged by an independent oracle (none = fine; any chip set means every visible slot needs one and two
##    different teams must be used); the hint, the friendly-fire toggle and the built MatchSettings agree, and the
##    settings the screen builds are accepted unchanged by the core (teams survive new_match, validate() is "").
##  - free-cap trimming: dropping to the free version cuts the slots and their teams, keeps the others, and
##    START follows; unlocking again does not bring the cut teams back.
##  - SetupPrefs / SettingsStore round trip of random chips and the friendly-fire flag.
##  - the chip cycle, the colours, the badge letters.

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const PREFS_PATH: String = "user://qa_m6_team_ui_prefs.cfg"
const NONE: int = TeamStyle.NONE

var _screen_node: SetupScreen = null


func before_each() -> void:
	SettingsStore.path = PREFS_PATH
	_cleanup()
	SetupPrefs.reset()
	PlayerNames.reset()
	BattleConfig.reset()


func after_each() -> void:
	_cleanup()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SetupPrefs.reset()
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


## Deletes this file's own scratch preference file (a plain file inside user://), nothing else.
func _cleanup() -> void:
	if PREFS_PATH.begins_with("user://qa_m6_") and FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(PREFS_PATH)


func _screen() -> SetupScreen:
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


## The rule from section 42, written out from scratch: "" or the error for the first `n` chips.
func _oracle(chips: Array[int], n: int) -> String:
	var any_set: bool = false
	for i: int in range(n):
		if chips[i] != NONE:
			any_set = true
	if not any_set:
		return ""
	var distinct: Dictionary = {}
	for i: int in range(n):
		if chips[i] == NONE:
			return "need_all"
		distinct[chips[i]] = true
	return "need_two" if distinct.size() < 2 else ""


func _random_chips(rng: Rng) -> Array[int]:
	var chips: Array[int] = []
	var style: int = rng.range_int(0, 9)
	var k: int = rng.range_int(1, 4)
	for _i: int in range(SimConstants.MAX_TANKS):
		match style:
			0, 1, 2:
				chips.append(NONE)
			3, 4, 5:
				chips.append(rng.range_int(0, k - 1))  # fully set, few teams
			6:
				chips.append(rng.range_int(0, 3))
			_:
				chips.append(rng.range_int(-1, 3))  # a mix of none and teams
	return chips


func test_start_is_enabled_exactly_when_the_teams_are_valid() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	var rng := Rng.new(0x6D360006)
	var seen: Dictionary = {"": 0, "need_all": 0, "need_two": 0}
	var by_n: Dictionary = {}
	var free_runs: int = 0
	for iter: int in range(400):
		var full: bool = iter % 4 != 3
		s.set_full_unlocked(full)
		var want_n: int = rng.range_int(2, 8)
		if not full:
			want_n = mini(want_n, SimConstants.FREE_MAX_TANKS)
			free_runs += 1
		s.set_players(want_n)
		var n: int = s.get_players()
		assert_eq(n, want_n, "iter %d: the player count could be set" % iter)
		var chips: Array[int] = _random_chips(rng)
		for i: int in range(SimConstants.MAX_TANKS):
			if s.get_team(i) != chips[i]:  # each call refreshes the whole screen: only touch what changes
				assert_true(s.set_team(i, chips[i]))
		var ff: bool = rng.range_int(0, 1) == 1
		s.set_friendly_fire(ff)
		var tag: String = "iter %d (full %s, %d players, chips %s)" % [iter, str(full), n, str(chips.slice(0, n))]
		var want: String = _oracle(chips, n)
		seen[want] = (seen[want] as int) + 1
		by_n[n] = (by_n.get(n, 0) as int) + 1
		assert_eq(s.team_error(), want, "%s: team_error" % tag)
		assert_eq(s.get_start_button().disabled, want != "", "%s: START disabled iff the teams are invalid" % tag)
		var any_on: bool = false
		for i: int in range(n):
			any_on = any_on or chips[i] != NONE
		assert_eq(s.teams_on(), any_on, "%s: teams_on" % tag)
		assert_eq(s.get_friendly_fire_button().visible, any_on, "%s: the toggle shows exactly with teams" % tag)
		assert_eq(s.get_team_hint_text() != "", want != "", "%s: the hint shows exactly when START is blocked" % tag)
		# What START would use.
		var st: MatchSettings = s.build_settings()
		assert_eq(st.validate(), "", "%s: the built settings validate" % tag)
		assert_eq(st.num_tanks, n)
		assert_eq(st.full_unlocked, full)
		assert_eq(st.controllers.size(), n)
		if want == "" and any_on:
			assert_eq(st.teams, PackedInt32Array(chips.slice(0, n)), "%s: chips become the team list" % tag)
			assert_eq(st.friendly_fire, ff, "%s: the toggle becomes friendly_fire" % tag)
		else:
			assert_true(st.teams.is_empty(), "%s: no teams without a usable chip set" % tag)
		# The core takes the settings as they are: nothing is dropped or clamped.
		var state: MatchState = Simulation.new_match(st)
		assert_eq(state.settings.teams, st.teams, "%s: the core keeps the teams" % tag)
		assert_eq(state.settings.friendly_fire, st.friendly_fire)
		for t: TankState in state.tanks:
			assert_eq(t.team, state.settings.team_of(t.id))
		# Pressing START while blocked does nothing (it must not touch BattleConfig).
		if want != "":
			var before_settings: MatchSettings = BattleConfig.settings
			s.start_match()
			assert_eq(BattleConfig.settings, before_settings, "%s: a blocked START changed nothing" % tag)
	gut.p("TEAM UI: 400 random chip states (%d in the free tier): ok %d, need_all %d, need_two %d; player counts %s" % [free_runs,
			seen[""], seen["need_all"], seen["need_two"], str(by_n)])
	assert_gt(seen[""], 100)
	assert_gt(seen["need_all"], 50)
	assert_gt(seen["need_two"], 20)
	for n: int in range(2, 9):
		assert_true(by_n.has(n) or n > 4, "player count %d was exercised" % n)


func test_every_two_chip_pair_exhaustively_for_two_players() -> void:
	var s: SetupScreen = _screen()
	s.set_players(2)
	var options: Array[int] = [NONE, 0, 1, 2, 3]
	for a: int in options:
		for b: int in options:
			s.set_team(0, a)
			s.set_team(1, b)
			var chips: Array[int] = [a, b, NONE, NONE, NONE, NONE, NONE, NONE]
			var want: String = _oracle(chips, 2)
			assert_eq(s.team_error(), want, "chips %d %d" % [a, b])
			assert_eq(s.get_start_button().disabled, want != "", "START for %d %d" % [a, b])


func test_free_cap_trimming_cuts_slots_and_their_teams_and_start_follows() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_full_unlocked(true)
	s.set_players(8)
	var chips: Array[int] = [0, 0, 1, 1, 0, 1, 2, 2]
	for i: int in range(8):
		s.set_team(i, chips[i])
	assert_false(s.get_start_button().disabled)
	s.set_full_unlocked(false)
	assert_eq(s.get_players(), 4, "the free version has 4 slots")
	for i: int in range(4):
		assert_eq(s.get_team(i), chips[i], "visible slot %d keeps its team" % i)
	for i: int in range(4, 8):
		assert_eq(s.get_team(i), NONE, "slot %d is gone with its team" % i)
	assert_false(s.get_start_button().disabled, "[A,A,B,B] is a valid split")
	var st: MatchSettings = s.build_settings()
	assert_eq(st.teams, PackedInt32Array([0, 0, 1, 1]))
	assert_eq(st.num_tanks, 4)
	assert_eq(Simulation.new_match(st).settings.teams, st.teams)
	# Unlocking again does not bring the cut slots' teams back, nor the players.
	s.set_full_unlocked(true)
	for i: int in range(4, 8):
		assert_eq(s.get_team(i), NONE)
	assert_eq(s.get_players(), 4)
	# A layout that collapses to one team after the cut: START blocked with the "two teams" hint.
	s.set_players(8)
	var lopsided: Array[int] = [0, 0, 0, 0, 1, 1, 1, 1]
	for i: int in range(8):
		s.set_team(i, lopsided[i])
	assert_false(s.get_start_button().disabled)
	s.set_full_unlocked(false)
	assert_eq(s.team_error(), "need_two", "[A,A,A,A] left after the cut")
	assert_true(s.get_start_button().disabled)
	assert_ne(s.get_team_hint_text(), "")
	assert_true(s.build_settings().teams.is_empty(), "no team list is built for a single team")
	assert_eq(s.build_settings().validate(), "")
	# Fixing one chip enables START again.
	s.set_team(3, 1)
	assert_eq(s.team_error(), "")
	assert_false(s.get_start_button().disabled)
	assert_eq(s.build_settings().teams, PackedInt32Array([0, 0, 0, 1]))


func test_the_core_clamp_agrees_with_the_screen_for_oversized_team_lists() -> void:
	# What the core does with a list the screen would never build: longer than the free cap, wrong length, one team.
	var s := MatchSettings.new()
	s.full_unlocked = false
	s.num_tanks = 6
	s.teams = PackedInt32Array([0, 0, 1, 1, 2, 2])
	var st: MatchState = Simulation.new_match(s)
	assert_eq(st.settings.num_tanks, 4, "free cap")
	assert_eq(st.settings.teams, PackedInt32Array([0, 0, 1, 1]), "the list is cut to the capped size")
	s.teams = PackedInt32Array([0, 0, 0, 0, 1, 1])
	var st2: MatchState = Simulation.new_match(s)
	assert_true(st2.settings.teams.is_empty(), "after the cut only one team is left: no teams at all (silently)")
	s.num_tanks = 3
	s.full_unlocked = true
	s.teams = PackedInt32Array([0, 1])
	assert_true(Simulation.new_match(s).settings.teams.is_empty(), "a list that is too short is dropped")
	assert_eq(s.validate(), "invalid_settings", "validate() is strict about the same list")
	s.teams = PackedInt32Array([0, 1, 4])
	assert_true(Simulation.new_match(s).settings.teams.is_empty())
	assert_eq(s.validate(), "invalid_settings")


# --- prefs ----------------------------------------------------------------------------------------------

func test_random_team_setups_round_trip_through_the_settings_file() -> void:
	var rng := Rng.new(0x6D360007)
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_full_unlocked(true)
	for iter: int in range(40):
		var n: int = rng.range_int(2, 8)
		s.set_players(n)
		var chips: Array[int] = _random_chips(rng)
		for i: int in range(SimConstants.MAX_TANKS):
			if s.get_team(i) != chips[i]:
				s.set_team(i, chips[i])
		var ff: bool = rng.range_int(0, 1) == 1
		s.set_friendly_fire(ff)
		s.save_prefs()
		assert_true(FileAccess.file_exists(PREFS_PATH), "iter %d: the settings file was written" % iter)
		SetupPrefs.reset()
		assert_true(SettingsStore.load_into(), "iter %d: it loads" % iter)
		assert_eq(SetupPrefs.teams, PackedInt32Array(chips), "iter %d: all eight chips are remembered (hidden slots too)" % iter)
		assert_eq(SetupPrefs.friendly_fire, ff, "iter %d: friendly fire" % iter)
		var s2: SetupScreen = _screen()
		for i: int in range(SimConstants.MAX_TANKS):
			assert_eq(s2.get_team(i), chips[i], "iter %d: a fresh screen shows slot %d's chip" % [iter, i])
		assert_eq(s2.is_friendly_fire(), ff)
		assert_eq(s2.get_players(), n)
		assert_eq(s2.team_error(), s.team_error(), "iter %d: same verdict after a reload" % iter)
		assert_eq(s2.get_start_button().disabled, s.get_start_button().disabled)
		s2.free()
		_cleanup()


func test_the_free_tier_reloads_a_big_saved_layout_inside_its_caps() -> void:
	var chips: Array[int] = [0, 1, 0, 1, 2, 2, 3, 3]
	SetupPrefs.remember(8, 5, 1, 2, PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0]), false, "", PackedStringArray(), PackedInt32Array(chips), false)
	assert_true(SettingsStore.save())
	SetupPrefs.reset()
	assert_true(SettingsStore.load_into())
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	s.set_full_unlocked(false)  # the player has the free version
	assert_lte(s.get_players(), 4)
	var st: MatchSettings = s.build_settings()
	assert_eq(st.validate(), "")
	assert_lte(st.num_tanks, 4)
	if not st.teams.is_empty():
		assert_eq(st.teams.size(), st.num_tanks)
	assert_eq(s.get_start_button().disabled, s.team_error() != "")


# --- the chip and the badge -----------------------------------------------------------------------------------

func test_chip_cycle_colours_and_letters() -> void:
	var v: int = NONE
	var seen_letters: Array[String] = []
	for _i: int in range(5):
		v = TeamStyle.next(v)
		seen_letters.append(TeamStyle.letter(v))
	assert_eq(seen_letters, ["A", "B", "C", "D", "—"] as Array[String])
	for t: int in range(4):
		for u: int in range(t + 1, 4):
			var a: Color = TeamStyle.color(t)
			var b: Color = TeamStyle.color(u)
			var d: float = absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			assert_gt(d, 0.6, "teams %d and %d are clearly different colours" % [t, u])
	for t: int in range(-3, 8):
		var chip := TeamChip.new()
		add_child_autofree(chip)
		chip.set_team(t)
		assert_eq(chip.get_team(), t if TeamStyle.is_team(t) else NONE, "chip value %d" % t)
		assert_ne(chip.text, "", "a letter or a dash is always shown")
		var badge := TeamBadge.new()
		add_child_autofree(badge)
		badge.set_team(t)
		assert_eq(badge.visible, TeamStyle.is_team(t))
		assert_eq(badge.get_letter(), TeamStyle.letter(t) if TeamStyle.is_team(t) else "")
	assert_eq(TeamStyle.letter(99), "—")
	assert_eq(TeamStyle.letter(-7), "—")
	assert_eq(TeamStyle.color(99), TeamStyle.NONE_COLOR)
