extends GutTest
## Free vs full gating (ARCHITECTURE section 32): every rule on the setup screen, the kind and
## theme pickers, the shop, matches carrying `full_unlocked`, locked taps opening the Unlock
## screen, live refresh after a purchase, and a full-game autosave on a device that is free now.

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const TITLE: String = "res://ui/title/title_screen.tscn"
const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PREFS: String = "user://test_gating_prefs.cfg"
const CACHE: String = "user://test_gating_entitlement.cfg"
const SAVE: String = "user://test_gating_save.crtl"

var _state: MatchState = null
var _taps: Array[String] = []


func before_each() -> void:
	SettingsStore.path = PREFS
	SettingsStore.delete()
	SetupPrefs.reset()
	SaveStore.delete(SAVE)
	_taps.clear()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SaveStore.delete(SAVE)
	Entitlement.forget_for_tests()
	if FileAccess.file_exists(CACHE):
		DirAccess.remove_absolute(CACHE)
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	ThemeDefs.full_override = -1


func _setup(full: bool) -> SetupScreen:
	Entitlement.reset_for_tests(full, CACHE)
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	s.locked_tapped.connect(func(kind: String, id: String) -> void: _taps.append("%s:%s" % [kind, id]))
	return s


func _badge(b: Control) -> bool:
	var badge: Node = b.get_node_or_null("LockBadge")
	return badge != null and (badge as Control).visible


# --- setup: players -----------------------------------------------------------------------------

func test_free_setup_stops_at_four_players() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_true(s.set_players(4))
	assert_false(s.get_players_plus().disabled, "the + stays tappable: it explains the limit")
	assert_true(_badge(s.get_players_plus()), "with a padlock")
	assert_false(s.set_players(5))
	assert_eq(s.get_players(), 4)
	assert_eq(_taps, ["players:5"])
	assert_true(s.get_unlock_screen().visible, "tapping a locked option opens the Unlock screen")
	assert_eq(s.get_unlock_screen().get_kind(), "players")
	assert_eq(s.get_hint_text(), "More than 4 players needs the full game.")
	s.get_players_plus().pressed.emit()
	assert_eq(_taps.size(), 2, "the button does the same")


func test_full_setup_allows_eight_players_and_shows_no_padlocks() -> void:
	var s: SetupScreen = _setup(true)
	await wait_process_frames(2)
	assert_true(s.set_players(8))
	assert_true(s.get_players_plus().disabled, "8 is the end of the line")
	assert_true(_taps.is_empty())
	for b: Button in [s.get_players_plus(), s.get_round_button(10), s.get_round_button(20), s.get_money_button(0),
			s.get_money_button(2), s.get_wind_button(0), s.get_wind_button(3)]:
		assert_false(_badge(b), "%s" % b.name)
	assert_true(s.build_settings().full_unlocked)
	assert_eq(s.build_settings().num_tanks, 8)


# --- setup: rounds, money, wind -----------------------------------------------------------------

func test_free_setup_locks_ten_and_twenty_rounds() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	for n: int in [1, 3, 5]:
		assert_true(s.set_rounds(n), "%d rounds are free" % n)
		assert_false(_badge(s.get_round_button(n)))
	for n: int in [10, 20]:
		assert_false(s.set_rounds(n))
		assert_true(_badge(s.get_round_button(n)), "%d has a padlock" % n)
		assert_eq(s.get_rounds(), 5)
		assert_eq(s.get_unlock_screen().get_kind(), "rounds")
	assert_eq(_taps, ["rounds:10", "rounds:20"])


func test_free_setup_locks_money_and_wind_presets_except_normal() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_true(s.set_money_level(1))
	assert_true(s.set_wind_level(2))
	for level: int in [0, 2]:
		assert_false(s.set_money_level(level))
		assert_true(_badge(s.get_money_button(level)))
	for level: int in [0, 1, 3]:
		assert_false(s.set_wind_level(level))
		assert_true(_badge(s.get_wind_button(level)))
	assert_false(_badge(s.get_money_button(1)))
	assert_false(_badge(s.get_wind_button(2)))
	assert_eq(s.get_money_level(), 1)
	assert_eq(s.get_wind_level(), 2)
	assert_eq(s.get_unlock_screen().get_kind(), "wind")
	assert_eq(_taps, ["money:0", "money:2", "wind:0", "wind:1", "wind:3"])


# --- setup: themes, CPU levels, humans ------------------------------------------------------------

func test_theme_defs_follow_the_entitlement() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	assert_false(ThemeDefs.is_full_game())
	Entitlement.reset_for_tests(true, CACHE)
	assert_true(ThemeDefs.is_full_game())


func test_free_setup_locks_the_three_full_themes() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_true(s.choose_theme(ThemeDefs.ICE_CIRCUIT))
	assert_true(s.choose_theme(ThemeDefs.RANDOM))
	for id: String in [ThemeDefs.MAGMA_CITY, ThemeDefs.TOXIC_MARSH, ThemeDefs.MIDNIGHT_CHROME]:
		assert_false(s.choose_theme(id))
	assert_eq(s.get_unlock_screen().get_kind(), "theme")
	assert_eq(_taps.size(), 3)
	# The picker lists them, locked, and a tap reports it instead of choosing.
	s.get_theme_button().pressed.emit()
	var p: ThemePicker = s.get_theme_picker()
	assert_true(p.is_lock_shown(ThemeDefs.MAGMA_CITY))
	assert_false(p.is_lock_shown(ThemeDefs.SUNSET_GRID))
	s.get_unlock_screen().close()
	p.get_option(ThemeDefs.TOXIC_MARSH).pressed.emit()
	assert_true(s.get_unlock_screen().visible)
	assert_ne(s.get_theme_choice(), ThemeDefs.TOXIC_MARSH)


func test_free_setup_locks_hard_and_expert_cpus() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_false(s.set_controller(1, SimConstants.CTRL_HARD))
	assert_false(s.set_controller(1, SimConstants.CTRL_EXPERT))
	assert_true(s.set_controller(1, SimConstants.CTRL_NORMAL))
	assert_true(s.set_controller(1, SimConstants.CTRL_EASY))
	assert_eq(_taps, ["cpu:3", "cpu:4"])
	assert_eq(s.get_unlock_screen().get_kind(), "cpu")
	s.get_unlock_screen().close()
	# Through the picker: the entries are visible, padlocked and tappable.
	s.get_kind_button(1).pressed.emit()
	var picker: KindPicker = s.get_kind_popup()
	assert_true(picker.is_locked(3))
	assert_true(picker.is_locked(4))
	assert_false(picker.is_locked(2))
	picker.get_option(4).pressed.emit()
	assert_false(picker.visible)
	assert_true(s.get_unlock_screen().visible)
	assert_eq(_taps[_taps.size() - 1], "cpu:4")


func test_free_setup_allows_two_humans_per_device() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_true(s.set_players(4))
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 0, 2, 2]),
			"growing the list never creates a third human: the new slots are CPU Normal")
	assert_false(s.set_controller(2, SimConstants.CTRL_HUMAN))
	assert_eq(_taps, ["human:"])
	assert_eq(s.get_unlock_screen().get_kind(), "human")
	s.get_unlock_screen().close()
	s.get_kind_button(2).pressed.emit()
	assert_true(s.get_kind_popup().is_locked(0), "Human is padlocked in the picker")
	s.get_kind_popup().close()
	# Free a human slot (player 2 becomes a CPU): player 3 may be human now.
	assert_true(s.set_controller(1, SimConstants.CTRL_EASY))
	assert_true(s.set_controller(2, SimConstants.CTRL_HUMAN))
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1, 0, 2]))


func test_full_setup_allows_any_number_of_humans_and_every_cpu_level() -> void:
	var s: SetupScreen = _setup(true)
	await wait_process_frames(2)
	s.set_players(5)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 0, 0, 0, 0]))
	assert_true(s.set_controller(2, SimConstants.CTRL_EXPERT))
	assert_true(s.set_controller(3, SimConstants.CTRL_HARD))
	assert_true(_taps.is_empty())


func test_match_settings_carry_the_entitlement() -> void:
	for full: bool in [false, true]:
		var s: SetupScreen = _setup(full)
		assert_eq(s.build_settings().full_unlocked, full)


func test_free_match_settings_are_inside_every_limit() -> void:
	# What a full-game setup left behind in the saved prefs.
	SetupPrefs.remember(7, 20, 2, 0, PackedInt32Array([0, 0, 0, 4, 3, 0, 0, 0]), false, ThemeDefs.MAGMA_CITY)
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	var m: MatchSettings = s.build_settings()
	assert_false(m.full_unlocked)
	assert_eq(m.num_tanks, 4)
	assert_eq(m.rounds, 3)
	assert_eq(m.start_money, 10000)
	assert_eq(m.wind_max, 70)
	assert_eq(s.get_theme_choice(), ThemeDefs.DEFAULT_ID)
	var humans: int = 0
	for c: int in m.controllers:
		assert_lte(c, SimConstants.CTRL_FREE_MAX)
		humans += 1 if c == SimConstants.CTRL_HUMAN else 0
	assert_lte(humans, 2)
	# And the core agrees.
	var st: MatchState = Simulation.new_match(m)
	assert_eq(st.settings.num_tanks, 4)


# --- the Unlock screen and live refresh -----------------------------------------------------------

func test_buying_unlocks_the_setup_screen_without_a_restart() -> void:
	var s: SetupScreen = _setup(false)
	await wait_process_frames(2)
	assert_false(s.set_rounds(10))
	assert_true(_badge(s.get_round_button(10)))
	var unlock: UnlockScreen = s.get_unlock_screen()
	assert_true(unlock.visible)
	unlock.get_buy_button().pressed.emit()  # the fake store answers at once
	assert_true(Entitlement.is_full())
	assert_false(_badge(s.get_round_button(10)), "the padlock is gone")
	assert_false(_badge(s.get_players_plus()))
	assert_false(_badge(s.get_money_button(0)))
	assert_true(s.set_rounds(10))
	assert_true(s.set_players(8))
	assert_true(s.set_controller(1, SimConstants.CTRL_EXPERT))
	assert_true(s.choose_theme(ThemeDefs.MAGMA_CITY))
	assert_true(s.build_settings().full_unlocked)


func test_losing_the_full_game_pulls_the_setup_back_inside_the_free_limits() -> void:
	var s: SetupScreen = _setup(true)
	await wait_process_frames(2)
	s.set_players(6)
	s.set_rounds(20)
	s.set_controller(1, SimConstants.CTRL_EXPERT)
	s.set_wind_level(0)
	s.choose_theme(ThemeDefs.TOXIC_MARSH)
	Entitlement.hub().changed.emit()  # nothing changed in truth: still full
	assert_eq(s.get_players(), 6)
	Entitlement.reset_for_tests(false, CACHE)
	s.set_full_unlocked(false)
	assert_eq(s.get_players(), 4)
	assert_eq(s.get_rounds(), 3)
	assert_eq(s.get_wind_level(), 2)
	assert_eq(s.get_theme_choice(), ThemeDefs.DEFAULT_ID)
	assert_lte(s.build_settings().controllers[1], SimConstants.CTRL_FREE_MAX)


func test_title_chip_shows_only_while_free() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_true(t.get_unlock_chip().visible)
	assert_eq(t.get_unlock_chip().text, "UNLOCK FULL GAME")
	assert_gte(t.get_unlock_chip().custom_minimum_size.y, UiScale.touch() - 0.01, "48 dp tap target")
	t.get_unlock_chip().pressed.emit()
	assert_true(t.get_unlock_screen().visible)
	assert_eq(t.get_unlock_screen().get_kind(), "")
	t.get_unlock_screen().get_buy_button().pressed.emit()
	assert_false(t.get_unlock_chip().visible, "gone once the game is unlocked, live")


func test_title_chip_is_hidden_when_full() -> void:
	Entitlement.reset_for_tests(true, CACHE)
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_false(t.get_unlock_chip().visible)


# --- shop -----------------------------------------------------------------------------------------

func _shop_state(full: bool) -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = 2
	m.rounds = 3
	m.seed = 99
	m.full_unlocked = full
	_state = Simulation.new_match(m)
	return _state


func _submit(action: Dictionary) -> String:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(_state, a)
	if err == "":
		Simulation.apply_action(_state, a)
	return err


func _flow() -> ShopFlow:
	var f := ShopFlow.new()
	add_child_autofree(f)
	f.open(_state, _submit, 0, true)
	return f


func test_shop_locks_every_full_tier_entry_and_keeps_it_visible() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_shop_state(false)
	var f: ShopFlow = _flow()
	await wait_process_frames(2)
	var locked: int = 0
	for id: String in f.get_screen().card_ids():
		var full_tier: bool = Catalog.get_def(id)["tier"] == "full"
		assert_eq(f.get_screen().get_card(id).is_locked_badge_visible(), full_tier, id)
		locked += 1 if full_tier else 0
	assert_gt(locked, 8, "the card list shows the locked entries too")
	assert_not_null(f.get_screen().get_card("singularity_seed"))
	assert_not_null(f.get_screen().get_card("riptide_anchor"))


func test_tapping_a_locked_shop_entry_opens_unlock_and_buying_it_unlocks_live() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_shop_state(false)
	var f: ShopFlow = _flow()
	await wait_process_frames(2)
	var screen: ShopScreen = f.get_screen()
	screen.select("singularity_seed")
	screen.get_detail().get_buy_button().pressed.emit()
	assert_true(f.get_unlock_screen().visible)
	assert_eq(f.get_unlock_screen().get_kind(), "item")
	assert_eq(_state.tanks[0].stock_of("singularity_seed"), 0)
	f.get_unlock_screen().get_buy_button().pressed.emit()
	assert_true(Entitlement.is_full())
	assert_true(_state.settings.full_unlocked, "the running match is upgraded")
	assert_false(screen.get_card("singularity_seed").is_locked_badge_visible(), "locks vanish without a restart")
	assert_eq(screen.buy_error("singularity_seed"), "")
	f.get_unlock_screen().close()
	screen.get_detail().get_buy_button().pressed.emit()
	assert_eq(_state.tanks[0].stock_of("singularity_seed"), 1, "and it can be bought now")


func test_a_free_match_is_never_upgraded_by_a_failed_purchase() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	_shop_state(false)
	var f: ShopFlow = _flow()
	await wait_process_frames(2)
	Entitlement.debug_build_override = 0  # a release build with no store
	f.get_screen().select("supernova")
	f.get_screen().get_detail().get_buy_button().pressed.emit()
	f.get_unlock_screen().get_buy_button().pressed.emit()
	assert_false(_state.settings.full_unlocked)
	assert_eq(f.get_unlock_screen().get_status_text(), "Store unavailable")


# --- battle: every match carries the entitlement ----------------------------------------------------

func test_a_quick_battle_carries_the_entitlement() -> void:
	for full: bool in [false, true]:
		Entitlement.reset_for_tests(full, CACHE)
		var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
		c.configure(1, 5, true, 2)
		add_child_autofree(c)
		assert_eq(c.state.settings.full_unlocked, full)


func test_a_purchase_during_a_battle_upgrades_the_running_match() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(1, 5, true, 2)
	add_child_autofree(c)
	assert_false(c.state.settings.full_unlocked)
	Entitlement.purchase_full()
	assert_true(c.state.settings.full_unlocked)


# --- autosave made with the full game, opened on a device that is free now -------------------------

func _save_full_match() -> void:
	var m := MatchSettings.new()
	m.num_tanks = 6
	m.rounds = 10
	m.seed = 12
	m.full_unlocked = true
	var st: MatchState = Simulation.new_match(m)
	for t: TankState in st.tanks:
		Simulation.apply_action(st, {"kind": "ready", "tank": t.id})
	Simulation.start_round(st)
	assert_true(SaveStore.save(st, [] as Array[Dictionary], SAVE))


func test_a_full_game_save_is_refused_on_a_free_device() -> void:
	_save_full_match()
	Entitlement.reset_for_tests(false, CACHE)
	assert_true(MatchSession.needs_full(SAVE))
	assert_null(MatchSession.restore(SAVE), "never hands out the full game for free")
	Entitlement.reset_for_tests(true, CACHE)
	assert_false(MatchSession.needs_full(SAVE))
	assert_not_null(MatchSession.restore(SAVE))


func test_a_free_game_save_resumes_on_any_device() -> void:
	var m := MatchSettings.new()
	m.num_tanks = 3
	m.seed = 4
	m.full_unlocked = false
	var st: MatchState = Simulation.new_match(m)
	assert_true(SaveStore.save(st, [] as Array[Dictionary], SAVE))
	Entitlement.reset_for_tests(false, CACHE)
	assert_false(MatchSession.needs_full(SAVE))
	assert_not_null(MatchSession.restore(SAVE))


func test_continue_explains_instead_of_resuming_and_keeps_the_save() -> void:
	_save_full_match()
	Entitlement.reset_for_tests(false, CACHE)
	BattleConfig.autosave_path = SAVE
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_true(t.has_save(), "the save is still offered")
	t.continue_game()
	assert_false(BattleConfig.resume, "the battle is not started")
	var u: UnlockScreen = t.get_unlock_screen()
	assert_true(u.visible)
	assert_eq(u.get_kind(), "save")
	assert_eq(u.get_context_text(), "This match uses full-game features. Unlock the full game to continue it.")
	assert_true(SaveStore.has_valid_save(SAVE), "nothing was deleted")
	u.get_buy_button().pressed.emit()
	assert_eq(u.get_close_button().text, "CONTINUE", "unlocking offers to continue the match")
	assert_false(MatchSession.needs_full(SAVE))


func test_a_battle_resuming_a_save_it_may_not_have_starts_a_fresh_free_match() -> void:
	_save_full_match()
	Entitlement.reset_for_tests(false, CACHE)
	BattleConfig.autosave_path = SAVE
	BattleConfig.resume = true
	BattleConfig.instant = true
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(c)
	assert_false(c.state.settings.full_unlocked)
	assert_lte(c.state.settings.num_tanks, SimConstants.FREE_MAX_TANKS)
