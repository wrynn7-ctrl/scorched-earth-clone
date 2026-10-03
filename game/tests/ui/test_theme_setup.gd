extends GutTest
## Terrain theme on the setup screen: the picker, lock state, persistence (setup prefs and the
## autosave meta) and its application in the battle, including per-round "Random".

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PREFS_PATH: String = "user://test_theme_prefs.cfg"
const SAVE: String = "user://test_theme_save.crtl"
const SEED: int = 777


func before_each() -> void:
	SettingsStore.path = PREFS_PATH
	SettingsStore.delete()
	SetupPrefs.reset()
	ThemeDefs.full_override = 1
	SaveStore.delete(SAVE)


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SaveStore.delete(SAVE)
	ThemeDefs.full_override = -1
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()


func _screen() -> SetupScreen:
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func test_default_theme_and_row() -> void:
	var s: SetupScreen = _screen()
	assert_eq(s.get_theme_choice(), ThemeDefs.SUNSET_GRID)
	assert_not_null(s.find_child("ThemeRow", true, false), "a THEME row exists")
	assert_eq(s.get_theme_button().text, "Sunset Grid ▾")
	assert_not_null(s.get_theme_button().icon, "with a tiny preview swatch")
	assert_gte(s.get_theme_button().custom_minimum_size.y, UiScale.touch() - 0.01, "tap target >= 48 dp")


func test_picker_lists_five_themes_and_random() -> void:
	var s: SetupScreen = _screen()
	s.get_theme_button().pressed.emit()
	var p: ThemePicker = s.get_theme_picker()
	assert_true(p.visible)
	for id: String in ThemeDefs.ids():
		assert_not_null(p.get_option(id), id)
		assert_false(p.is_lock_shown(id), "the full game is unlocked here")
	assert_not_null(p.get_option(ThemeDefs.RANDOM))
	assert_true(p.get_option(ThemeDefs.SUNSET_GRID).button_pressed, "current choice shows pressed")
	p.get_option(ThemeDefs.MAGMA_CITY).pressed.emit()
	assert_false(p.visible, "choosing closes it")
	assert_eq(s.get_theme_choice(), ThemeDefs.MAGMA_CITY)
	assert_eq(s.get_theme_button().text, "Magma City ▾")
	s.choose_theme(ThemeDefs.RANDOM)
	assert_eq(s.get_theme_button().text, "Random ▾")


func test_every_swatch_is_a_real_picture() -> void:
	for id: String in ThemeDefs.ids() + PackedStringArray([ThemeDefs.RANDOM]):
		var img: Image = ThemeSwatch.image(id)
		assert_eq(img.get_size(), Vector2i(ThemeSwatch.W, ThemeSwatch.H))
		assert_ne(img.get_pixel(ThemeSwatch.W / 2, ThemeSwatch.H / 4), img.get_pixel(ThemeSwatch.W / 2, ThemeSwatch.H - 3),
				"%s: sky and ground differ" % id)


func test_locked_themes_stay_visible_with_the_full_game_lock() -> void:
	ThemeDefs.full_override = 0
	var s: SetupScreen = _screen()
	var seen: Array[String] = []
	s.locked_tapped.connect(func(kind: String, id: String) -> void: seen.append("%s:%s" % [kind, id]))
	s.get_theme_button().pressed.emit()
	var p: ThemePicker = s.get_theme_picker()
	for id: String in [ThemeDefs.MAGMA_CITY, ThemeDefs.TOXIC_MARSH, ThemeDefs.MIDNIGHT_CHROME]:
		assert_true(p.get_option(id).visible, "%s not hidden" % id)
		assert_true(p.is_lock_shown(id), "%s locked" % id)
		assert_true(p.get_option(id).text.contains("FULL GAME"), "the lock is also spelled out")
		assert_false(p.get_option(id).disabled, "tappable: it leads to the unlock screen")
	for id: String in [ThemeDefs.SUNSET_GRID, ThemeDefs.ICE_CIRCUIT, ThemeDefs.RANDOM]:
		assert_false(p.is_lock_shown(id), "%s is free" % id)
	p.get_option(ThemeDefs.MAGMA_CITY).pressed.emit()
	assert_eq(s.get_theme_choice(), ThemeDefs.SUNSET_GRID, "a locked theme is not chosen")
	assert_eq(seen, ["theme:magma_city"], "the tap is reported")
	assert_eq(s.get_hint_text(), "That theme is part of the full game.")
	assert_true(s.choose_theme(ThemeDefs.ICE_CIRCUIT))
	assert_true(s.choose_theme(ThemeDefs.RANDOM))
	assert_false(s.choose_theme("toxic_marsh"))
	assert_false(s.choose_theme("not_a_theme"))


func test_locking_after_the_fact_demotes_a_full_theme() -> void:
	var s: SetupScreen = _screen()
	s.choose_theme(ThemeDefs.MIDNIGHT_CHROME)
	s.set_full_unlocked(false)
	assert_eq(s.get_theme_choice(), ThemeDefs.DEFAULT_ID)


func test_theme_persists_through_the_setup_prefs_file() -> void:
	var s: SetupScreen = _screen()
	s.choose_theme(ThemeDefs.TOXIC_MARSH)
	s.save_prefs()
	assert_eq(SetupPrefs.theme, ThemeDefs.TOXIC_MARSH)
	assert_true(FileAccess.file_exists(PREFS_PATH))
	SetupPrefs.reset()
	assert_eq(SetupPrefs.theme, ThemeDefs.DEFAULT_ID)
	assert_true(SettingsStore.load_into())
	assert_eq(SetupPrefs.theme, ThemeDefs.TOXIC_MARSH, "read back from settings.cfg")
	var s2: SetupScreen = _screen()
	assert_eq(s2.get_theme_choice(), ThemeDefs.TOXIC_MARSH, "a new setup screen starts with it")
	# "random" persists too; garbage falls back to the default.
	s2.choose_theme(ThemeDefs.RANDOM)
	s2.save_prefs()
	SetupPrefs.reset()
	SettingsStore.load_into()
	assert_eq(SetupPrefs.theme, ThemeDefs.RANDOM)
	var cfg := ConfigFile.new()
	cfg.load(PREFS_PATH)
	cfg.set_value(SettingsStore.SETUP_SECTION, "theme", "bogus")
	cfg.save(PREFS_PATH)
	SetupPrefs.reset()
	SettingsStore.load_into()
	assert_eq(SetupPrefs.theme, ThemeDefs.DEFAULT_ID)


func test_a_saved_locked_theme_falls_back_without_the_full_game() -> void:
	SetupPrefs.remember(2, 3, 1, 2, PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0]), false, ThemeDefs.MAGMA_CITY)
	ThemeDefs.full_override = 0
	var s: SetupScreen = _screen()
	assert_eq(s.get_theme_choice(), ThemeDefs.DEFAULT_ID)


func test_start_hands_the_theme_to_the_battle() -> void:
	BattleConfig.autosave_path = SAVE
	var s: SetupScreen = _screen()
	s.choose_theme(ThemeDefs.ICE_CIRCUIT)
	s.get_start_button().pressed.emit()
	assert_eq(BattleConfig.theme, ThemeDefs.ICE_CIRCUIT)
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController)
	if cur is BattleController:
		assert_eq((cur as BattleController).get_theme_choice(), ThemeDefs.ICE_CIRCUIT)
		cur.queue_free()
		await wait_process_frames(2)


func _battle(instant: bool = true) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant, 2)
	c.set_autosave_path(SAVE)
	add_child_autofree(c)
	return c


func test_battle_applies_the_theme_to_sky_and_terrain() -> void:
	var c: BattleController = _battle()
	c.set_theme_choice(ThemeDefs.MAGMA_CITY)
	assert_true(c.quick_start())
	assert_eq(c.get_theme_id(), ThemeDefs.MAGMA_CITY)
	assert_eq(c.get_terrain_view().get_theme_id(), ThemeDefs.MAGMA_CITY)
	assert_eq((c.get_node("Sky") as NeonSky).get_theme_id(), ThemeDefs.MAGMA_CITY)


func test_random_theme_is_resolved_per_round_from_seed_and_round() -> void:
	var c: BattleController = _battle()
	c.set_theme_choice(ThemeDefs.RANDOM)
	assert_true(c.quick_start())
	var st: MatchState = c.get_state()
	var want: String = ThemeDefs.resolve(ThemeDefs.RANDOM, st.seed, st.round_index, st.settings.full_unlocked)
	assert_eq(c.get_theme_id(), want)
	var seen: Dictionary = {}
	for r: int in range(12):
		seen[ThemeDefs.resolve(ThemeDefs.RANDOM, st.seed, r, true)] = true
	assert_gte(seen.size(), 2, "rounds of one match can differ")


func test_theme_choice_is_saved_in_the_autosave_meta_and_restored() -> void:
	var c: BattleController = _battle()
	c.set_theme_choice(ThemeDefs.RANDOM)
	assert_true(c.quick_start())
	var applied: String = c.get_theme_id()
	assert_true(c.autosave_now())
	var res: Dictionary = SaveStore.load_save(SAVE)
	assert_true(res["ok"] as bool)
	assert_eq((res["meta"] as Dictionary)["theme"], ThemeDefs.RANDOM)
	BattleConfig.autosave_path = SAVE
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_eq(r.get_theme_choice(), ThemeDefs.RANDOM, "the choice survives a restore")
	assert_eq(r.get_theme_id(), applied, "and a restored round shows the same theme")
