extends GutTest
## The match setup screen: choices become MatchSettings, every control fits every screen.

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const TEST_SAVE: String = "user://test_setup_save.crtl"
const PREFS_PATH: String = "user://test_setup_prefs.cfg"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func before_each() -> void:
	# START and BACK write settings.cfg: never the developer's real one.
	SettingsStore.path = PREFS_PATH
	SettingsStore.delete()
	SetupPrefs.reset()


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()


func _screen() -> SetupScreen:
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


func test_defaults() -> void:
	var s: SetupScreen = _screen()
	var m: MatchSettings = s.build_settings()
	assert_eq(m.num_tanks, 2)
	assert_eq(m.rounds, 3)
	assert_eq(m.start_money, 10000)
	assert_eq(m.wind_max, 70)
	assert_true(m.full_unlocked, "the full game is unlocked until billing exists")


func test_choices_become_match_settings() -> void:
	var s: SetupScreen = _screen()
	s.get_players_plus().pressed.emit()
	s.get_players_plus().pressed.emit()
	s.get_round_button(10).pressed.emit()
	s.get_money_button(2).pressed.emit()
	s.get_wind_button(0).pressed.emit()
	var m: MatchSettings = s.build_settings()
	assert_eq(m.num_tanks, 4)
	assert_eq(m.rounds, 10)
	assert_eq(m.start_money, 25000)
	assert_eq(m.wind_max, 0)
	for level: Array in [[0, 5000], [1, 10000], [2, 25000]]:
		s.set_money_level(level[0])
		assert_eq(s.build_settings().start_money, level[1])
	for pair: Array in [[0, 0], [1, 40], [2, 70], [3, 100]]:
		s.set_wind_level(pair[0])
		assert_eq(s.build_settings().wind_max, pair[1])
	for n: int in [1, 3, 5, 10, 20]:
		s.set_rounds(n)
		assert_eq(s.build_settings().rounds, n)


func test_player_count_is_limited_to_2_through_8() -> void:
	var s: SetupScreen = _screen()
	for _i: int in range(10):
		s.get_players_plus().pressed.emit()
	assert_eq(s.get_players(), 8)
	assert_true(s.get_players_plus().disabled)
	for _i: int in range(10):
		s.get_players_minus().pressed.emit()
	assert_eq(s.get_players(), 2)
	assert_true(s.get_players_minus().disabled)
	assert_eq(s.get_players_value_text(), "2")
	s.set_players(5)
	for i: int in range(8):
		assert_eq(s.get_player_row(i).visible, i < 5, "row %d" % i)


func test_colours_and_emblems_stay_unique() -> void:
	var s: SetupScreen = _screen()
	s.set_players(8)
	for _i: int in range(20):
		s.cycle_color(0)
		s.cycle_emblem(3)
		s.cycle_color(5)
	var colors: Dictionary = {}
	var emblems: Dictionary = {}
	for i: int in range(8):
		colors[s.get_color_index(i)] = true
		emblems[s.get_emblem_index(i)] = true
	assert_eq(colors.size(), 8, "no two players share a colour")
	assert_eq(emblems.size(), 8, "no two players share an emblem")
	# Cycling to a colour somebody else has swaps with them.
	var s2: SetupScreen = _screen()
	s2.cycle_color(0)  # player 0 takes colour 1, player 1 gets colour 0
	assert_eq(s2.get_color_index(0), 1)
	assert_eq(s2.get_color_index(1), 0)
	assert_eq(s2.get_emblem_button(0).get_emblem(), 0, "the emblem button draws the emblem")
	assert_ne(s2.get_color_button(0).tooltip_text, "", "colours have names for screen readers")


func test_every_slot_starts_human() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	assert_eq(s.get_kind_button(0).text, "HUMAN ▾")
	assert_eq(s.get_kind_button(1).text, "HUMAN ▾")
	assert_false(s.get_chip(1).visible, "no level chip on a human")


func test_start_hands_the_match_to_the_battle() -> void:
	BattleConfig.autosave_path = TEST_SAVE
	var f: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("an old autosave")
	f.close()
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(3)
	s.set_rounds(5)
	s.set_money_level(0)
	s.set_wind_level(3)
	s.cycle_color(0)
	s.cycle_emblem(0)
	var picked_color: int = s.get_color_index(0)
	s.get_start_button().pressed.emit()
	assert_false(FileAccess.file_exists(TEST_SAVE), "a new match replaces the autosave")
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController, "START loads the battle")
	if cur is BattleController:
		var c: BattleController = cur
		var st: MatchState = c.get_state()
		assert_eq(st.settings.num_tanks, 3)
		assert_eq(st.settings.rounds, 5)
		assert_eq(st.settings.start_money, 5000)
		assert_eq(st.settings.wind_max, 100)
		assert_eq(st.phase, SimConstants.PHASE_SHOP, "new_match opens the shop")
		assert_eq(st.tanks[0].money, 5000)
		assert_true(st.settings.full_unlocked)
		assert_eq(PlayerLooks.color_index(0), picked_color, "chosen colour reaches the battle")
		assert_true(c.get_shop().is_showing_handover())
		cur.queue_free()
		await wait_process_frames(2)


func test_back_returns_to_the_title() -> void:
	var s: SetupScreen = _screen()
	s.get_back_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is TitleScreen)
	if cur != null:
		cur.queue_free()
		await wait_process_frames(2)


func _controls(root: Node, out: Array[Control]) -> void:
	for c: Node in root.get_children():
		if c is Window:
			continue
		if c is Control:
			out.append(c as Control)
		# Rows inside the scrolling player list are clipped on purpose; check the scroll area itself.
		if not (c is ScrollContainer):
			_controls(c, out)


func test_layout_fits_every_screen() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], size_pct]
			UiScale.dpi_override = float(case[1])
			UiScale.window_px_override = case[0]
			var vis: Vector2 = UiScale.visible_size(case[0])
			var vp := SubViewport.new()
			vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
			vp.disable_3d = true
			add_child_autofree(vp)
			var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
			vp.add_child(s)
			s.set_players(8)
			s.set_watch(true)
			for slot: int in range(1, 8):
				s.set_controller(slot, SimConstants.CTRL_EXPERT)  # the widest chip text
			await wait_process_frames(3)
			assert_true(s.get_chip(7).visible, "%s: CPU chip shown" % label)
			var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
			var all: Array[Control] = []
			_controls(s, all)
			for c: Control in all:
				if c.is_visible_in_tree():
					assert_true(rect.encloses(c.get_global_rect()), "%s: %s %s outside %s" % [label, c.get_path(), c.get_global_rect(), vis])
					if c is BaseButton:
						assert_gte(UiScale.canvas_to_dp(minf(c.size.x, c.size.y)), 47.5, "%s: %s only %.1f dp" % [label, c.name, UiScale.canvas_to_dp(minf(c.size.x, c.size.y))])
			# The scrolling list and START stay on screen; the first rows are really visible.
			assert_true(rect.encloses(s.get_scroll().get_global_rect()), "%s: list on screen" % label)
			assert_gt(s.get_scroll().size.y, UiScale.touch() * 1.5, "%s: at least one and a half player rows visible" % label)
			var first: Rect2 = s.get_player_row(0).get_global_rect()
			assert_true(s.get_scroll().get_global_rect().encloses(first), "%s: first player row visible" % label)
			assert_true(rect.encloses(s.get_start_button().get_global_rect()), "%s: START on screen" % label)
			assert_true(rect.encloses(s.get_watch_box().get_global_rect()), "%s: the Watch checkbox is on screen" % label)
			for slot: int in [1, 7]:
				var kb: Rect2 = s.get_kind_button(slot).get_global_rect().grow(1.5)
				assert_true(kb.encloses(s.get_chip(slot).get_global_rect()), "%s: the chip stays inside its button" % label)
			for b: Button in [s.get_color_button(0), s.get_emblem_button(0), s.get_kind_button(0)]:
				assert_gte(UiScale.canvas_to_dp(minf(b.size.x, b.size.y)), 47.5, "%s: %s >= 48 dp" % [label, b.name])
			vp.queue_free()
			await wait_process_frames(1)


# --- computer opponents: the picker, the human rule, the lock, persistence -------------------

func _pick(s: SetupScreen, slot: int, level: int) -> void:
	s.get_kind_button(slot).pressed.emit()
	assert_true(s.get_kind_popup().visible, "the picker opens")
	s.get_kind_popup().get_option(level).pressed.emit()


func test_picker_offers_human_and_four_cpu_levels() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(4)
	s.get_kind_button(1).pressed.emit()
	var picker: KindPicker = s.get_kind_popup()
	assert_true(picker.visible)
	var names: Array[String] = []
	for level: int in range(5):
		names.append(picker.get_option(level).text)
	assert_eq(names, ["HUMAN", "CPU EASY", "CPU NORMAL", "CPU HARD", "CPU EXPERT"] as Array[String])
	assert_eq(picker.get_player(), 1)
	assert_true(picker.get_option(0).button_pressed, "the current choice is marked")
	picker.get_cancel_button().pressed.emit()
	assert_false(picker.visible, "BACK closes the picker without a choice")
	assert_eq(s.get_controllers(), PackedInt32Array([0, 0, 0, 0]))


func test_choices_become_controllers_and_chips() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(4)
	_pick(s, 1, SimConstants.CTRL_EASY)
	_pick(s, 2, SimConstants.CTRL_HARD)
	_pick(s, 3, SimConstants.CTRL_EXPERT)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1, 3, 4]))
	assert_eq(s.get_kind_button(0).text, "HUMAN ▾")
	assert_eq(s.get_kind_button(2).text, "CPU ▾")
	assert_false(s.get_kind_popup().visible, "choosing closes the picker")
	assert_false(s.get_chip(0).visible)
	assert_eq([s.get_chip_text(1), s.get_chip_text(2), s.get_chip_text(3)], ["EASY", "HARD", "EXPERT"], "the chip spells the level out")
	for slot: int in [1, 2, 3]:
		assert_true(s.get_chip(slot).visible)
	# A CPU slot can go back to human.
	_pick(s, 2, SimConstants.CTRL_HUMAN)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1, 0, 4]))
	assert_false(s.get_chip(2).visible)
	# Hidden slots keep their choice when the count shrinks and grows again.
	s.set_players(2)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1]))
	s.set_players(4)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1, 0, 4]))


func test_at_least_one_human_unless_watch_is_ticked() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(3)
	assert_true(s.set_controller(1, SimConstants.CTRL_NORMAL))
	assert_true(s.set_controller(2, SimConstants.CTRL_NORMAL))
	assert_false(s.set_controller(0, SimConstants.CTRL_EASY), "the last human cannot become a CPU")
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 2, 2]))
	assert_eq(s.get_hint_text(), "At least one player must be human (or turn on Watch CPUs play).")
	assert_true(s.get_hint_text() != "")
	# Through the picker the choice is refused the same way.
	_pick(s, 0, SimConstants.CTRL_HARD)
	assert_eq(s.build_settings().controllers[0], 0)
	# Watch CPUs play lifts the rule.
	s.get_watch_box().button_pressed = true
	assert_true(s.is_watch())
	assert_true(s.set_controller(0, SimConstants.CTRL_EASY))
	assert_eq(s.build_settings().controllers, PackedInt32Array([1, 2, 2]))
	assert_eq(s.get_hint_text(), "", "the hint clears with the next change")
	# Switching it off with nobody human makes player 1 human again.
	s.get_watch_box().button_pressed = false
	assert_false(s.is_watch())
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 2, 2]))
	# Shrinking the list can leave only CPUs in view: player 1 becomes human again.
	s.set_watch(true)
	s.set_controller(0, SimConstants.CTRL_EASY)
	s.set_controller(1, SimConstants.CTRL_EASY)
	s.set_controller(2, SimConstants.CTRL_HUMAN)
	s.set_watch(false)
	assert_eq(s.build_settings().controllers, PackedInt32Array([1, 1, 0]), "the human in slot 3 satisfies the rule")
	s.set_players(2)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 1]))


func test_hard_and_expert_are_locked_without_the_full_game() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(3)
	s.set_controller(1, SimConstants.CTRL_EXPERT)
	s.set_full_unlocked(false)
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, 2, 0]), "an Expert slot falls back to Normal")
	assert_false(s.build_settings().full_unlocked)
	s.get_kind_button(2).pressed.emit()
	var picker: KindPicker = s.get_kind_popup()
	for level: int in [3, 4]:
		assert_true(picker.get_option(level).disabled, "level %d is locked" % level)
		assert_string_contains(picker.get_option(level).text, "FULL GAME")
		assert_true(picker.get_option(level).get_node("Lock").visible, "with a lock icon")
	for level: int in [0, 1, 2]:
		assert_false(picker.get_option(level).disabled)
		assert_false(picker.get_option(level).get_node("Lock").visible)
	assert_false(s.set_controller(2, SimConstants.CTRL_HARD))
	assert_true(s.set_controller(2, SimConstants.CTRL_NORMAL))
	s.set_full_unlocked(true)
	s.get_kind_button(2).pressed.emit()
	assert_false(picker.get_option(4).disabled)
	assert_eq(picker.get_option(4).text, "CPU EXPERT")
	# The simulation enforces the same rule on its side.
	var m: MatchSettings = s.build_settings()
	m.full_unlocked = false
	m.controllers = PackedInt32Array([0, 4, 3])
	assert_eq(Simulation.new_match(m).settings.controllers, PackedInt32Array([0, 2, 2]))


func test_last_used_setup_is_saved_and_restored() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(5)
	s.set_rounds(10)
	s.set_money_level(2)
	s.set_wind_level(3)
	s.set_controller(1, SimConstants.CTRL_EASY)
	s.set_controller(2, SimConstants.CTRL_HARD)
	s.set_controller(4, SimConstants.CTRL_EXPERT)
	s.get_watch_box().button_pressed = true
	s.save_prefs()
	assert_true(FileAccess.file_exists(PREFS_PATH), "written to settings.cfg")
	# A new process: defaults in memory, then the file is loaded.
	SetupPrefs.reset()
	var fresh: SetupScreen = _screen()
	assert_eq(fresh.get_players(), 2, "nothing saved in memory: defaults")
	assert_true(SettingsStore.load_into())
	var again: SetupScreen = _screen()
	await wait_process_frames(2)
	assert_eq(again.get_players(), 5)
	assert_eq(again.get_rounds(), 10)
	assert_eq(again.get_money_level(), 2)
	assert_eq(again.get_wind_level(), 3)
	assert_true(again.is_watch())
	var m: MatchSettings = again.build_settings()
	assert_eq(m.num_tanks, 5)
	assert_eq(m.start_money, 25000)
	assert_eq(m.wind_max, 100)
	assert_eq(m.controllers, PackedInt32Array([0, 1, 3, 0, 4]))
	assert_eq(again.get_kind_button(2).text, "CPU ▾", "the rows show the restored choices")
	assert_eq(again.get_chip_text(4), "EXPERT")


func test_damaged_saved_setup_is_clamped() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("setup", "players", 99)
	cfg.set_value("setup", "rounds", 7)
	cfg.set_value("setup", "money_level", -4)
	cfg.set_value("setup", "wind_level", "high")
	cfg.set_value("setup", "controllers", [9, -2, "x", 3, 1.0])
	cfg.set_value("setup", "watch", "yes")
	cfg.save(PREFS_PATH)
	assert_true(SettingsStore.load_into())
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	assert_eq(s.get_players(), 8, "clamped")
	assert_eq(s.get_rounds(), 3, "a round count the screen has no button for falls back")
	assert_eq(s.get_money_level(), 0)
	assert_eq(s.get_wind_level(), 2, "a non-number keeps the default")
	assert_false(s.is_watch())
	var c: PackedInt32Array = s.build_settings().controllers
	assert_eq(c[0], 4, "too big clamps to Expert")
	assert_eq(c[1], 0, "negative values become human")
	assert_eq(c[2], 0, "junk becomes human")
	assert_eq(c[3], 3)
	assert_eq(c[4], 1)
	# A hand-edited file with no human at all (and no Watch) is repaired.
	cfg.set_value("setup", "controllers", [4, 4, 4, 4, 4, 4, 4, 4])
	cfg.save(PREFS_PATH)
	SetupPrefs.reset()
	SettingsStore.load_into()
	var repaired: SetupScreen = _screen()
	assert_eq(repaired.build_settings().controllers[0], 0, "player 1 is human again")


func test_start_passes_the_controllers_to_the_battle_and_remembers_them() -> void:
	BattleConfig.autosave_path = TEST_SAVE
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	s.set_players(3)
	s.set_controller(1, SimConstants.CTRL_NORMAL)
	s.set_controller(2, SimConstants.CTRL_EASY)
	s.get_start_button().pressed.emit()
	assert_true(FileAccess.file_exists(PREFS_PATH), "START saves the setup")
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController, "START loads the battle")
	if cur is BattleController:
		var c: BattleController = cur
		assert_eq(c.get_state().settings.controllers, PackedInt32Array([0, 2, 1]))
		assert_true(c.is_cpu_tank(1))
		assert_false(c.is_cpu_tank(0))
		assert_true(c.get_shop().is_showing_shop(), "one human and CPUs: straight into the shop, no hand-over")
		assert_false(c.get_shop().is_showing_handover())
		assert_eq(c.get_shop().get_screen().get_player(), 0)
		cur.queue_free()
		await wait_process_frames(2)
	SaveStore.delete(TEST_SAVE)


# --- the picker fits every screen -----------------------------------------------------------

func test_picker_layout_fits_every_screen() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for locked: bool in [false, true]:
			for case: Array in CASES:
				var label: String = "%s @%d%% %s" % [case[2], size_pct, "locked" if locked else "unlocked"]
				UiScale.dpi_override = float(case[1])
				UiScale.window_px_override = case[0]
				var vis: Vector2 = UiScale.visible_size(case[0])
				var vp := SubViewport.new()
				vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
				vp.disable_3d = true
				add_child_autofree(vp)
				var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
				vp.add_child(s)
				s.set_players(8)
				s.set_full_unlocked(not locked)
				await wait_process_frames(2)
				s.get_kind_button(7).pressed.emit()
				await wait_process_frames(3)
				var picker: KindPicker = s.get_kind_popup()
				assert_true(picker.visible, label)
				var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
				var panel: Rect2 = picker.get_panel().get_global_rect()
				assert_true(rect.encloses(panel), "%s: panel %s outside %s" % [label, panel, vis])
				var buttons: Array[Button] = []
				for level: int in range(5):
					buttons.append(picker.get_option(level))
				buttons.append(picker.get_cancel_button())
				for b: Button in buttons:
					assert_true(rect.encloses(b.get_global_rect()), "%s: %s on screen" % [label, b.name])
					assert_gte(UiScale.canvas_to_dp(b.size.y), 55.5, "%s: %s is a large (56 dp) target, %.1f" % [label, b.name, UiScale.canvas_to_dp(b.size.y)])
					assert_gte(UiScale.canvas_to_dp(b.size.x), 47.5, "%s: %s wide enough" % [label, b.name])
					if b.text.length() > 4:
						# The text is not clipped away: a locked entry must still say FULL GAME.
						assert_gt(b.size.x, UiScale.dp(100.0), "%s: %s has room for its text" % [label, b.name])
				vp.queue_free()
				await wait_process_frames(1)
