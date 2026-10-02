extends GutTest
## The match setup screen: choices become MatchSettings, every control fits every screen.

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const TEST_SAVE: String = "user://test_setup_save.crtl"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(2340, 1080), 535.0, "narrowest realistic"],
	[Vector2(2560, 1080), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
]


func after_each() -> void:
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


func test_every_slot_is_human_and_ai_is_a_disabled_option() -> void:
	var s: SetupScreen = _screen()
	await wait_process_frames(2)
	assert_eq(s.get_kind_button(0).text, "HUMAN ▾")
	var ai: Button = s.get_kind_popup().find_child("Ai", true, false)
	assert_not_null(ai)
	assert_true(ai.disabled)
	assert_eq(ai.text, "AI — coming soon")


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
			await wait_process_frames(3)
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
			for b: Button in [s.get_color_button(0), s.get_emblem_button(0), s.get_kind_button(0)]:
				assert_gte(UiScale.canvas_to_dp(minf(b.size.x, b.size.y)), 47.5, "%s: %s >= 48 dp" % [label, b.name])
			vp.queue_free()
			await wait_process_frames(1)
