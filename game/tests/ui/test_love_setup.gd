extends GutTest
## The Love Edition setup and the love HUD: settings with mode = LOVE, the fixed player 1, the CPU gating, START into a
## battle, the HUD that hides money / items / move, and every love screen fitting every phone and tablet at both
## extreme text sizes.

const SETUP: String = "res://ui/love/love_setup_screen.tscn"
const HUD: String = "res://ui/hud/hud.tscn"
const TITLE: String = "res://ui/title/title_screen.tscn"
const PREFS: String = "user://test_love_setup_prefs.cfg"
const SAVE: String = "user://test_love_setup_save.crtl"

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
	SettingsStore.path = PREFS
	SettingsStore.delete()
	SetupPrefs.reset()
	BattleConfig.autosave_path = SAVE
	SaveStore.delete(SAVE)
	ThemeDefs.full_override = -1


func after_each() -> void:
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SettingsStore.love_found = false
	SaveStore.delete(SAVE)
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	ThemeDefs.full_override = -1


func _screen() -> LoveSetupScreen:
	var s: LoveSetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	return s


# --- setup ---------------------------------------------------------------------------------

func test_love_setup_builds_love_settings() -> void:
	var s: LoveSetupScreen = _screen()
	var m: MatchSettings = s.build_settings()
	assert_eq(m.mode, SimConstants.MODE_LOVE)
	assert_eq(m.num_tanks, 2)
	assert_eq(m.rounds, 1)
	assert_eq(m.start_money, 0)
	assert_lte(m.wind_max, SimConstants.LOVE_WIND_MAX, "gentle wind")
	assert_eq(m.controllers[0], SimConstants.CTRL_HUMAN, "player 1 is always human")
	assert_eq(m.controllers[1], SimConstants.CTRL_HUMAN)
	assert_ne(m.seed, 0)


func test_player_one_is_fixed_and_player_two_picks_human_or_cpu() -> void:
	var s: LoveSetupScreen = _screen()
	await wait_process_frames(2)
	assert_true(s.get_kind_button(0).disabled, "nothing to choose for player 1")
	assert_false(s.get_kind_button(1).disabled)
	assert_true(s.set_player2(SimConstants.CTRL_EASY))
	assert_eq(s.build_settings().controllers, PackedInt32Array([0, SimConstants.CTRL_EASY]))
	assert_true(s.set_player2(SimConstants.CTRL_NORMAL))
	assert_eq(s.build_settings().controllers[1], SimConstants.CTRL_NORMAL)
	assert_true(s.get_kind_button(1).text.contains("NORMAL"))
	assert_true(s.set_player2(SimConstants.CTRL_HUMAN))
	assert_eq(s.build_settings().controllers[1], SimConstants.CTRL_HUMAN)
	# The picker is the standard one.
	s.get_kind_button(1).pressed.emit()
	assert_true(s.get_kind_popup().is_open())
	s.get_kind_popup().get_option(SimConstants.CTRL_EASY).pressed.emit()
	assert_eq(s.get_player2(), SimConstants.CTRL_EASY)


func test_hard_and_expert_are_locked_without_the_full_game() -> void:
	ThemeDefs.full_override = 0
	var s: LoveSetupScreen = _screen()
	await wait_process_frames(2)
	watch_signals(s)
	assert_false(s.set_player2(SimConstants.CTRL_HARD))
	assert_false(s.set_player2(SimConstants.CTRL_EXPERT))
	assert_signal_emit_count(s, "locked_tapped", 2)
	assert_eq(s.get_player2(), SimConstants.CTRL_HUMAN)
	assert_true(s.get_hint_text() != "")
	assert_true(s.set_player2(SimConstants.CTRL_NORMAL), "Easy and Normal are free")
	s.get_kind_button(1).pressed.emit()
	assert_true(s.get_kind_popup().is_locked(SimConstants.CTRL_HARD))
	assert_false(s.build_settings().full_unlocked)
	s.set_full_unlocked(true)
	assert_true(s.set_player2(SimConstants.CTRL_HARD), "unlocked live")


func test_colours_and_emblems_default_to_pinks_and_stay_unique() -> void:
	var s: LoveSetupScreen = _screen()
	assert_eq(s.get_color_index(0), 6, "orchid")
	assert_eq(s.get_color_index(1), 5, "coral")
	s.cycle_color(0)
	assert_eq(s.get_color_index(0), 7)
	s.cycle_color(0)  # 0 would not collide; the loop swaps with player 2 only when equal
	for _i: int in range(8):
		s.cycle_color(1)
		assert_ne(s.get_color_index(0), s.get_color_index(1), "never the same colour")
	for _i: int in range(9):
		s.cycle_emblem(0)
		assert_ne(s.get_emblem_index(0), s.get_emblem_index(1), "never the same emblem")


func test_start_loads_a_love_battle_with_the_chosen_looks() -> void:
	var s: LoveSetupScreen = _screen()
	await wait_process_frames(2)
	s.set_player2(SimConstants.CTRL_EASY)
	s.cycle_color(0)
	var picked: int = s.get_color_index(0)
	var f: FileAccess = FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	s.get_start_button().pressed.emit()
	assert_false(FileAccess.file_exists(SAVE), "a new match replaces the autosave")
	assert_true(FileAccess.file_exists(PREFS), "player 2 is remembered")
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController, "START loads the battle")
	if cur is BattleController:
		var c: BattleController = cur
		var st: MatchState = c.get_state()
		assert_eq(st.settings.mode, SimConstants.MODE_LOVE)
		assert_eq(st.phase, SimConstants.PHASE_AIM, "straight into the aim, no shop")
		assert_eq(st.settings.controllers, PackedInt32Array([0, SimConstants.CTRL_EASY]))
		assert_true(c.is_cpu_tank(1))
		assert_eq(PlayerLooks.color_index(0), picked)
		assert_true(c.is_love_mode())
		cur.queue_free()
		await wait_process_frames(2)
	# Remembered for next time.
	SetupPrefs.reset()
	SettingsStore.load_into()
	assert_eq(SetupPrefs.love_cpu, SimConstants.CTRL_EASY)


func test_back_returns_to_the_title() -> void:
	var s: LoveSetupScreen = _screen()
	s.get_back_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is TitleScreen)
	if cur != null:
		cur.queue_free()
		await wait_process_frames(2)


func test_the_love_setup_uses_the_love_sky() -> void:
	var s: LoveSetupScreen = _screen()
	await wait_process_frames(1)
	var sky: NeonSky = s.find_child("*", false, false) as NeonSky if false else null
	for n: Node in s.get_children():
		if n is NeonSky:
			sky = n
	assert_not_null(sky)
	assert_eq(sky.get_theme_id(), ThemeDefs.LOVE_THEME)


# --- the love HUD ----------------------------------------------------------------------------

func _hud_in(win: Vector2, dpi: float, love: bool, cpu: bool = true) -> Dictionary:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	var hud: BattleHud = (load(HUD) as PackedScene).instantiate()
	vp.add_child(hud)
	hud.set_love_mode(love)
	if cpu:
		hud.show_cpu_turn(1, SimConstants.CTRL_NORMAL, true)
	else:
		hud.show_turn(1)
	hud.set_angle_tenths(1800)
	hud.set_power(1000)
	hud.set_wind(-30)
	hud.set_money(1000000)
	hud.set_weapon("heart", -1)
	hud.set_items([{"id": "glow_shield", "count": 9}] as Array[Dictionary])
	hud.set_fuel(9900)
	await wait_frames(3)
	return {"hud": hud, "vis": vis, "vp": vp}


func test_love_hud_hides_money_items_and_move() -> void:
	var built: Dictionary = await _hud_in(Vector2(2340, 1080), 500.0, true)
	var hud: BattleHud = built["hud"]
	assert_true(hud.is_love_mode())
	assert_false(hud.get_money_label().visible, "money hidden")
	assert_false(hud.get_items_toggle().visible, "items toggle hidden")
	assert_false(hud.get_item_tray().visible, "items row hidden")
	assert_false(hud.get_move_controls().visible, "move hidden even with fuel")
	hud.toggle_items()
	assert_false(hud.get_item_tray().visible)
	assert_true(hud.get_weapon_button().visible)
	assert_eq(hud.get_weapon_button().get_name_text(), "Heart")
	assert_eq(hud.get_weapon_button().get_sub_text(), "∞")
	assert_eq(hud.get_weapon_button().get_item(), "heart")
	assert_true(hud.get_turn_banner().has_heart_accents(), "heart accents on the banner")
	# And back: a standard match shows them all again.
	hud.set_love_mode(false)
	assert_true(hud.get_money_label().visible)
	hud.set_fuel(100)
	assert_true(hud.get_move_controls().visible)
	assert_false(hud.get_turn_banner().has_heart_accents())


func test_the_heart_has_its_own_glyph() -> void:
	assert_eq(ItemIcon.glyph_color("heart"), Color(1.0, 0.42, 0.66))
	assert_ne(ItemIcon.glyph_color("heart"), NeonPalette.TEXT)


# --- layout ----------------------------------------------------------------------------------

func _all(root: Node, out: Array[Control]) -> void:
	for c: Node in root.get_children():
		if c is Window:
			continue
		if c is Control:
			out.append(c as Control)
		_all(c, out)


func _inside(root: Node, vis: Vector2, label: String) -> void:
	var rect := Rect2(Vector2.ZERO, vis).grow(1.5)
	var all: Array[Control] = []
	_all(root, all)
	assert_gt(all.size(), 5, label)
	for c: Control in all:
		if not c.is_visible_in_tree():
			continue
		if c.get_parent() is ScrollContainer or c is ScrollContainer:
			continue
		var r: Rect2 = c.get_global_rect()
		assert_true(rect.encloses(r), "%s: %s %s outside %s" % [label, c.get_path(), r, Rect2(Vector2.ZERO, vis)])


func test_love_hud_fits_every_screen_at_both_text_sizes() -> void:
	for pct: int in [80, 150]:
		ShowSettings.set_text_size(pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], pct]
			var built: Dictionary = await _hud_in(case[0], float(case[1]), true)
			var hud: BattleHud = built["hud"]
			var vis: Vector2 = built["vis"]
			_inside(hud, vis, label)
			var banner: Rect2 = hud.get_turn_banner().get_global_rect()
			for other: Control in [hud.get_pause_button(), hud.get_speed_button(), hud.get_wind_indicator(), hud.get_power_panel()]:
				assert_false(banner.intersects(other.get_global_rect()), "%s: banner/%s overlap" % [label, other.name])
			assert_false(hud.get_angle_panel().get_global_rect().intersects(hud.get_fire_button().get_global_rect()), label)
			assert_gte(UiScale.canvas_to_dp(hud.get_pause_button().size.y), 47.5, label)
			(built["vp"] as Node).queue_free()


func test_love_setup_fits_every_screen_at_both_text_sizes() -> void:
	for pct: int in [80, 150]:
		ShowSettings.set_text_size(pct)
		for locked: bool in [false, true]:
			for case: Array in CASES:
				var label: String = "%s @%d%% %s" % [case[2], pct, "free" if locked else "full"]
				UiScale.dpi_override = float(case[1])
				UiScale.window_px_override = case[0]
				var vis: Vector2 = UiScale.visible_size(case[0])
				var vp := SubViewport.new()
				vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
				vp.disable_3d = true
				add_child_autofree(vp)
				var s: LoveSetupScreen = (load(SETUP) as PackedScene).instantiate()
				vp.add_child(s)
				s.set_full_unlocked(not locked)
				s.set_player2(SimConstants.CTRL_NORMAL)
				await wait_process_frames(3)
				_inside(s, vis, label)
				for b: Button in [s.get_start_button(), s.get_back_button(), s.get_kind_button(1)]:
					assert_gte(UiScale.canvas_to_dp(b.size.y), 47.5, "%s: %s >= 48 dp" % [label, b.name])
				s.get_kind_button(1).pressed.emit()
				await wait_process_frames(3)
				_inside(s.get_kind_popup(), vis, label + " picker")
				vp.queue_free()


func test_title_with_the_love_button_fits_every_screen() -> void:
	SettingsStore.love_found = true
	for pct: int in [80, 150]:
		ShowSettings.set_text_size(pct)
		for case: Array in CASES:
			var label: String = "%s @%d%%" % [case[2], pct]
			UiScale.dpi_override = float(case[1])
			UiScale.window_px_override = case[0]
			var vis: Vector2 = UiScale.visible_size(case[0])
			var vp := SubViewport.new()
			vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
			vp.disable_3d = true
			add_child_autofree(vp)
			var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
			vp.add_child(t)
			await wait_process_frames(3)
			assert_true(t.get_love_button().visible, label)
			var r: Rect2 = t.get_love_button().get_global_rect()
			assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(r), "%s: love button %s in %s" % [label, r, vis])
			assert_gte(UiScale.canvas_to_dp(r.size.y), 47.5, label)
			assert_false(r.intersects(t.get_start_button().get_global_rect()), label)
			var logo: Rect2 = t.get_logo_holder().get_global_rect()
			assert_true(Rect2(Vector2.ZERO, vis).grow(1.5).encloses(logo), "%s: logo stays on screen" % label)
			vp.queue_free()
