extends GutTest
## Team chips on the setup screen (ARCHITECTURE sections 39 and 42): cycling, colours plus letters, the START rules
## and their hints, the friendly-fire toggle, remembering the choices, the free 4-tank cap, and layout at phone and
## tablet sizes (including the narrowest 700 dp phone).

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const PREFS_PATH: String = "user://test_team_prefs.cfg"
const NONE: int = TeamStyle.NONE

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic (700 dp)"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
]


func before_each() -> void:
	SettingsStore.path = PREFS_PATH
	SettingsStore.delete()
	SetupPrefs.reset()
	PlayerNames.reset()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SetupPrefs.reset()
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


func _screen() -> SetupScreen:
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


# --- TeamStyle ---------------------------------------------------------------------------

func test_team_style_letters_colours_and_cycle() -> void:
	assert_eq(TeamStyle.letter(0), "A")
	assert_eq(TeamStyle.letter(3), "D")
	assert_eq(TeamStyle.letter(NONE), "—")
	assert_eq(TeamStyle.color(0), NeonPalette.CYAN, "A is cyan")
	assert_eq(TeamStyle.color(1), NeonPalette.MAGENTA, "B is magenta")
	var seen: Array[Color] = []
	for t: int in range(4):
		assert_false(seen.has(TeamStyle.color(t)), "four different colours")
		seen.append(TeamStyle.color(t))
	var v: int = NONE
	var walk: Array[int] = []
	for _i: int in range(6):
		v = TeamStyle.next(v)
		walk.append(v)
	assert_eq(walk, [0, 1, 2, 3, NONE, 0] as Array[int], "— A B C D —")
	assert_eq(TeamStyle.team_name(2), "TEAM C")


# --- chips ---------------------------------------------------------------------------------

func test_every_slot_starts_without_a_team_and_no_toggle() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	for i: int in range(SimConstants.MAX_TANKS):
		assert_eq(s.get_team(i), NONE)
		assert_eq(s.get_team_chip(i).text, "—")
	assert_false(s.teams_on())
	assert_eq(s.team_error(), "")
	assert_false(s.get_friendly_fire_button().visible, "no toggle without teams")
	assert_false(s.get_start_button().disabled)
	assert_true(s.build_settings().teams.is_empty())
	assert_eq(s.build_settings().validate(), "")


func test_tapping_a_chip_cycles_none_a_b_c_d_none() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	var chip: TeamChip = s.get_team_chip(0)
	var shown: Array[String] = []
	for _i: int in range(6):
		chip.pressed.emit()
		shown.append(chip.text)
	assert_eq(shown, ["A", "B", "C", "D", "—", "A"] as Array[String])
	assert_eq(s.get_team(0), 0)
	assert_eq(s.get_team(1), NONE, "other slots are untouched")


func test_a_chip_shows_a_letter_in_its_team_colour() -> void:
	var s: SetupScreen = _screen()
	for t: int in range(4):
		s.set_team(0, t)
		var chip: TeamChip = s.get_team_chip(0)
		assert_eq(chip.text, TeamStyle.letter(t), "the letter is always there (colour is not the only cue)")
		var sb: StyleBoxFlat = chip.get_theme_stylebox("normal") as StyleBoxFlat
		assert_eq(Color(sb.bg_color, 1.0), TeamStyle.color(t))
	assert_false(s.set_team(0, 4), "only A..D or none")
	assert_false(s.set_team(0, -2))
	assert_false(s.set_team(9, 0))
	assert_eq(s.get_team(0), 3, "a refused value changes nothing")


# --- validation ------------------------------------------------------------------------------

func test_some_slots_with_a_team_and_others_without_blocks_start() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_team(0, 0)
	assert_true(s.teams_on())
	assert_eq(s.team_error(), "need_all")
	assert_true(s.get_start_button().disabled)
	assert_eq(s.get_team_hint_text(), "Give every player a team")
	assert_true(s.get_team_hint_label().visible)
	assert_true(s.get_friendly_fire_button().visible, "teams are on")


func test_one_team_for_everybody_blocks_start() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_team(0, 2)
	s.set_team(1, 2)
	assert_eq(s.team_error(), "need_two")
	assert_true(s.get_start_button().disabled)
	assert_eq(s.get_team_hint_text(), "Use at least two teams")


func test_two_teams_enable_start_and_become_match_settings() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(4)
	s.set_team(0, 1)
	s.set_team(1, 3)
	s.set_team(2, 3)
	assert_true(s.get_start_button().disabled, "slot 4 still has no team")
	s.set_team(3, 1)
	assert_eq(s.team_error(), "")
	assert_false(s.get_start_button().disabled)
	assert_eq(s.get_team_hint_text(), "")
	var m: MatchSettings = s.build_settings()
	assert_eq(m.teams, PackedInt32Array([1, 3, 3, 1]))
	assert_true(m.friendly_fire, "friendly fire defaults to ON")
	assert_eq(m.validate(), "", "the core accepts what the screen builds")
	assert_true(m.has_teams())


func test_the_hidden_slots_do_not_count_for_the_rules() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_team(0, 0)
	s.set_team(1, 1)
	s.set_team(5, 2)  # a hidden slot of a 2-player match
	assert_eq(s.team_error(), "")
	assert_eq(s.build_settings().teams, PackedInt32Array([0, 1]))
	s.set_players(6)
	assert_eq(s.team_error(), "need_all", "slots 3 and 4 now show without a team")


func test_back_to_dashes_everywhere_means_no_teams_again() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_team(0, 0)
	s.set_team(0, NONE)
	assert_false(s.teams_on())
	assert_false(s.get_start_button().disabled)
	assert_false(s.get_friendly_fire_button().visible)
	assert_true(s.build_settings().teams.is_empty())


func test_start_does_nothing_while_the_teams_are_not_usable() -> void:
	var s: SetupScreen = _screen()
	s.set_team(0, 0)
	BattleConfig.settings = null
	s.start_match()
	assert_null(BattleConfig.settings, "START is disabled: no match was made")
	assert_false(FileAccess.file_exists(PREFS_PATH), "and nothing was saved either")


# --- friendly fire ----------------------------------------------------------------------------

func test_friendly_fire_toggle_only_with_teams_and_goes_into_the_settings() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	var ff: Button = s.get_friendly_fire_button()
	assert_false(ff.visible)
	s.set_team(0, 0)
	s.set_team(1, 1)
	assert_true(ff.visible)
	assert_eq(ff.text, "Friendly fire: ON")
	ff.toggled.emit(false)
	assert_false(s.is_friendly_fire())
	assert_eq(ff.text, "Friendly fire: OFF", "words, not only a colour")
	var m: MatchSettings = s.build_settings()
	assert_false(m.friendly_fire)
	assert_eq(m.teams, PackedInt32Array([0, 1]))
	ff.toggled.emit(true)
	assert_true(s.build_settings().friendly_fire)


# --- remembering --------------------------------------------------------------------------------

func test_teams_and_friendly_fire_round_trip_through_the_settings_file() -> void:
	var s: SetupScreen = _screen()
	s.set_players(4)
	for i: int in range(4):
		s.set_team(i, i % 2)
	s.set_friendly_fire(false)
	s.save_prefs()
	assert_true(FileAccess.file_exists(PREFS_PATH))
	SetupPrefs.reset()
	assert_true(SettingsStore.load_into(PREFS_PATH))
	assert_eq(SetupPrefs.teams.slice(0, 4), PackedInt32Array([0, 1, 0, 1]))
	assert_false(SetupPrefs.friendly_fire)
	var again: SetupScreen = _screen()
	assert_eq(again.get_teams(), PackedInt32Array([0, 1, 0, 1]))
	assert_false(again.is_friendly_fire())
	assert_eq(again.build_settings().teams, PackedInt32Array([0, 1, 0, 1]))


func test_no_teams_is_remembered_as_no_teams_and_friendly_fire_stays_on() -> void:
	var s: SetupScreen = _screen()
	s.save_prefs()
	SetupPrefs.reset()
	SettingsStore.load_into(PREFS_PATH)
	assert_eq(SetupPrefs.teams, PackedInt32Array([NONE, NONE, NONE, NONE, NONE, NONE, NONE, NONE]))
	assert_true(SetupPrefs.friendly_fire)


func test_a_hand_edited_file_cannot_put_bad_teams_in() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 3)
	cfg.set_value("setup", "teams", [0, 9, "x", -7, 2.0, null, 1, 1, 1, 1, 1])
	cfg.set_value("setup", "friendly_fire", "yes")
	assert_eq(cfg.save(PREFS_PATH), OK)
	assert_true(SettingsStore.load_into(PREFS_PATH))
	assert_eq(SetupPrefs.teams, PackedInt32Array([0, NONE, NONE, NONE, 2, NONE, 1, 1]), "bad entries become '—'")
	assert_true(SetupPrefs.friendly_fire, "a non-boolean keeps the default")
	var cfg2 := ConfigFile.new()
	cfg2.set_value("setup", "teams", "not a list")
	assert_eq(cfg2.save(PREFS_PATH), OK)
	SetupPrefs.reset()
	SettingsStore.load_into(PREFS_PATH)
	assert_eq(SetupPrefs.teams.slice(0, 2), PackedInt32Array([NONE, NONE]))


func test_an_old_file_without_teams_loads_without_teams() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 3)
	assert_eq(cfg.save(PREFS_PATH), OK)
	SettingsStore.load_into(PREFS_PATH)
	var s: SetupScreen = _screen()
	assert_false(s.teams_on())
	assert_true(s.is_friendly_fire())


# --- free version cap ------------------------------------------------------------------------------

func test_slots_beyond_the_free_cap_drop_their_team() -> void:
	var s: SetupScreen = _screen()
	s.set_full_unlocked(true)
	s.set_players(6)
	for i: int in range(6):
		s.set_team(i, 0 if i < 3 else 1)
	assert_eq(s.team_error(), "")
	s.set_full_unlocked(false)
	assert_eq(s.get_players(), SimConstants.FREE_MAX_TANKS)
	for i: int in range(4):
		assert_eq(s.get_team(i), 0 if i < 3 else 1, "the slots inside the cap keep their team")
	assert_eq(s.get_team(4), NONE)
	assert_eq(s.get_team(5), NONE)
	assert_eq(s.team_error(), "")
	var m: MatchSettings = s.build_settings()
	assert_eq(m.teams, PackedInt32Array([0, 0, 0, 1]))
	assert_eq(m.validate(), "")


func test_a_saved_six_player_team_setup_fits_the_free_cap_on_load() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 6)
	cfg.set_value("setup", "teams", [0, 0, 1, 1, 0, 1])
	assert_eq(cfg.save(PREFS_PATH), OK)
	SettingsStore.load_into(PREFS_PATH)
	var s: SetupScreen = _screen()
	s.set_full_unlocked(false)
	assert_eq(s.get_teams(), PackedInt32Array([0, 0, 1, 1]))
	assert_eq(s.get_team(4), NONE)
	assert_eq(s.team_error(), "")


func test_free_caps_leave_a_single_team_invalid_with_a_hint() -> void:
	var s: SetupScreen = _screen()
	s.set_full_unlocked(true)
	s.set_players(6)
	for i: int in range(6):
		s.set_team(i, 0 if i < 4 else 1)
	s.set_full_unlocked(false)
	assert_eq(s.team_error(), "need_two", "only team A is left inside the cap: the hint says so")
	assert_true(s.get_start_button().disabled)


func test_love_setup_has_no_team_ui() -> void:
	var s: Node = (load("res://ui/love/love_setup_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(s)
	await wait_process_frames(2)
	assert_eq(_count_of(s, "TeamChip"), 0)
	assert_eq(_count_of(s, "FriendlyFire"), 0)


func _count_of(n: Node, what: String) -> int:
	var c: int = 1 if (n.name == what or n.get_class() == what or (n.get_script() != null and (n.get_script() as Script).get_global_name() == what)) else 0
	for ch: Node in n.get_children():
		c += _count_of(ch, what)
	return c


# --- layout ----------------------------------------------------------------------------------------

func test_chips_fit_every_screen_and_text_size() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
			var vis: Vector2 = Vector2(vp.size)
			var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
			vp.add_child(s)
			s.set_players(4)
			s.set_controller(1, SimConstants.CTRL_NORMAL)  # a CPU slot has no name field
			for i: int in range(4):
				s.set_player_name(i, "WWWWWWWWWWWW")
				s.set_team(i, i % 2)
			s.set_team(3, NONE)  # one slot without a team: the hint shows
			await wait_process_frames(3)
			var bounds := Rect2(Vector2.ZERO, vis).grow(1.5)
			assert_true(bounds.encloses(s.get_start_button().get_global_rect()), "%s: START on screen" % label)
			assert_true(s.get_start_button().disabled, "%s: START disabled" % label)
			assert_true(bounds.encloses(s.get_scroll().get_global_rect()), "%s: list on screen" % label)
			assert_true(bounds.encloses(s.get_team_hint_label().get_global_rect()), "%s: hint on screen" % label)
			assert_true(s.get_team_hint_label().visible, label)
			var ff: Button = s.get_friendly_fire_button()
			assert_true(ff.get_global_rect().position.x >= -1.5 and ff.get_global_rect().end.x <= vis.x + 1.5, "%s: toggle inside sideways" % label)
			assert_gte(UiScale.canvas_to_dp(ff.size.y), 47.5, "%s: toggle is a 48 dp target" % label)
			for i: int in range(4):
				var chip: TeamChip = s.get_team_chip(i)
				var r: Rect2 = chip.get_global_rect()
				assert_true(r.position.x >= -1.5 and r.end.x <= vis.x + 1.5, "%s: chip %d %s inside %s sideways" % [label, i, r, vis])
				assert_gte(UiScale.canvas_to_dp(r.size.x), 47.5, "%s: chip %d wide enough" % [label, i])
				assert_gte(UiScale.canvas_to_dp(r.size.y), 47.5, "%s: chip %d tall enough" % [label, i])
				assert_true(s.get_player_slot(i).get_global_rect().grow(1.5).encloses(r), "%s: chip %d inside its slot" % [label, i])
				if i == 0:
					assert_true(bounds.encloses(r), "%s: first chip fully on screen" % label)
				# It never sits on top of the name field or the picker.
				var nf: NameField = s.get_name_field(i)
				if nf.visible:
					assert_false(r.intersects(nf.get_global_rect().grow(-1.0)), "%s: chip %d clear of the name" % [label, i])
				assert_false(r.intersects(s.get_kind_button(i).get_global_rect().grow(-1.0)), "%s: chip %d clear of the picker" % [label, i])
				for b: Control in [s.get_color_button(i), s.get_emblem_button(i), s.get_kind_button(i)]:
					var br: Rect2 = b.get_global_rect()
					assert_true(br.position.x >= -1.5 and br.end.x <= vis.x + 1.5, "%s: %s inside sideways" % [label, b.name])
			vp.queue_free()
			await wait_process_frames(1)


func test_the_chip_ends_the_row_on_wide_screens_and_the_second_line_on_narrow_ones() -> void:
	var narrow: SubViewport = _viewport(Vector2(2340, 1080), 535.0)
	var a: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	narrow.add_child(a)
	await wait_process_frames(2)
	assert_eq(a.get_team_chip(0).get_parent(), a.get_name_line(0))
	var wide: SubViewport = _viewport(Vector2(2048, 1536), 264.0)
	var b: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	wide.add_child(b)
	await wait_process_frames(2)
	assert_eq(b.get_team_chip(0).get_parent(), b.get_player_row(0))
	assert_eq(b.get_team_chip(0).get_index(), b.get_player_row(0).get_child_count() - 1, "last in the row")
	assert_false(b.get_name_line(0).visible)
