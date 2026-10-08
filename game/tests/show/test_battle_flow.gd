extends GutTest
## The playable battle: simulation wired to the show layer. Runs headless with the controller in
## `instant` mode (a whole timeline applied at once) unless a test says otherwise.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const TITLE: String = "res://ui/title/title_screen.tscn"
const SEED: int = 12345


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	get_tree().paused = false


## A controller in the shop (the match always starts there).
func _make(rounds: int, seed_value: int, instant: bool = true, players: int = 2) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, seed_value, instant, players)
	add_child_autofree(c)
	return c


## Everybody buys a few Pulse Missiles (so rounds end as quickly as in M2) and presses READY.
func _enter_round(c: BattleController) -> void:
	for t: TankState in c.get_state().tanks:
		c.get_session().submit({"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 3})
	assert_true(c.quick_start(), "the shop hands over to the round")


## A controller whose round 1 is already running.
func _make_round(rounds: int, seed_value: int, instant: bool = true, players: int = 2) -> BattleController:
	var c: BattleController = _make(rounds, seed_value, instant, players)
	_enter_round(c)
	return c


## Plays AutoShot turns until the phase leaves "aim". Returns the number of shots fired.
func _play_round(c: BattleController, max_shots: int = 80) -> int:
	var shots: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and shots < max_shots:
		var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
		c.set_aim(shot.x, shot.y)
		c.select_weapon("pulse_missile")  # silently refused (toast) once the stock ran out
		assert_eq(c.fire_current(), "", "shot %d accepted" % shots)
		shots += 1
	return shots


func test_match_starts_in_the_shop() -> void:
	var c: BattleController = _make(3, SEED)
	var s: MatchState = c.get_state()
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_eq(s.round_index, -1)
	assert_null(s.terrain)
	assert_null(c.display_terrain)
	assert_true(c.get_shop().is_showing_handover(), "the hand-over screen comes first")
	assert_true(c.is_busy(), "no aiming in the shop")
	assert_eq(c.fire_current(), "busy")
	assert_false(c.get_hud().visible)
	assert_false(c.get_terrain_view().visible)


func test_battle_scene_instantiates_with_fixed_seed() -> void:
	var c: BattleController = _make_round(3, SEED)
	var s: MatchState = c.get_state()
	assert_not_null(s)
	assert_eq(s.seed, SEED)
	assert_eq(s.settings.rounds, 3)
	assert_eq(s.tanks.size(), 2)
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_eq(c.display_terrain.cells, s.terrain.cells, "display terrain starts equal to the state")
	assert_false(c.display_terrain == s.terrain, "but it is a separate copy")
	for t: TankState in s.tanks:
		assert_eq(c.get_tank_view(t.id).position, Vector2(t.x, t.y))
		assert_eq(c.get_tank_view(t.id).get_color_index(), t.color_index)
	assert_false(c.is_busy())
	assert_eq(c.round_wins, PackedInt32Array([0, 0]))
	# Same seed -> same match.
	var d: BattleController = _make_round(3, SEED)
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(s))


func test_fire_advances_turn_and_display_matches_state() -> void:
	var c: BattleController = _make_round(3, SEED)
	var first: int = c.get_state().current_tank
	assert_eq(c.fire_current(), "")
	var s: MatchState = c.get_state()
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_ne(s.current_tank, first, "turn passes to the other player")
	assert_eq(s.turn_number, 1)
	assert_eq(c.display_terrain.cells, s.terrain.cells, "terrain bytes identical after playback")
	assert_eq(c.mismatch_count, 0)
	assert_false(c.is_busy(), "input unlocked again")
	assert_eq(c.timelines_played(), 2, "round start + the shot")


func test_each_tank_remembers_its_own_aim() -> void:
	var c: BattleController = _make_round(3, SEED)
	var a0: Vector2i = c.get_aim(0)
	c.set_aim(700, 640)
	assert_eq(c.get_aim(c.get_state().current_tank), Vector2i(700, 640))
	assert_eq(c.get_tank_view(c.get_state().current_tank).get_angle_tenths(), 700, "turret rotates live")
	var other: int = 1 - c.get_state().current_tank
	assert_ne(c.get_aim(other), Vector2i(700, 640))
	c.fire_current()
	# The new current tank shows its own remembered aim in the HUD.
	var cur: int = c.get_state().current_tank
	assert_eq(c.get_hud().get_angle_tenths(), c.get_aim(cur).x)
	assert_eq(c.get_hud().get_power(), c.get_aim(cur).y)
	if cur == 0:
		assert_eq(c.get_aim(0), a0)


func test_invalid_aim_is_rejected_and_changes_nothing() -> void:
	var c: BattleController = _make_round(3, SEED)
	var before: String = Simulation.fingerprint(c.get_state())
	var cur: int = c.get_state().current_tank
	c.set_aim(450, 0)  # the slider allows 0, validate_action does not
	assert_eq(c.fire_current(), "bad_power")
	assert_eq(Simulation.fingerprint(c.get_state()), before, "state untouched")
	assert_eq(c.get_state().current_tank, cur)
	assert_eq(c.timelines_played(), 1, "only the round start was played")
	assert_false(c.is_busy())
	assert_ne(c.get_toast().get_text(), "", "a toast explains the problem")
	assert_true(c.get_toast().visible)
	# And the same through the pure API.
	var bad: Dictionary = {"kind": "fire", "tank": cur, "angle": 450, "power": 0, "weapon": "pulse_missile"}
	assert_eq(Simulation.validate_action(c.get_state(), bad), "bad_power")


func test_scripted_match_reaches_round_end_shop_next_round_and_match_over() -> void:
	var c: BattleController = _make_round(2, SEED)
	watch_signals(c)
	_play_round(c)
	var s: MatchState = c.get_state()
	assert_eq(s.phase, SimConstants.PHASE_SHOP, "first round ends: back to the shop")
	assert_true(c.get_round_overlay().visible, "the round summary is shown first")
	assert_true(c.is_busy(), "no aiming while the summary is open")
	assert_eq(c.fire_current(), "busy")
	var wins_after_1: int = c.round_wins[0] + c.round_wins[1]
	assert_lte(wins_after_1, 1)
	assert_eq(c.get_round_overlay().get_table().get_text().count("PLAYER"), 2)
	assert_eq(c.display_terrain.cells, s.terrain.cells)

	var old_terrain: PackedByteArray = s.terrain.cells.duplicate()
	c.next_round()
	assert_false(c.get_round_overlay().visible)
	assert_true(c.get_shop().is_showing_handover(), "NEXT opens the shop")
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_true(c.quick_start(), "READY from everyone starts round 2")
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_eq(s.round_index, 1)
	assert_false(c.is_busy())
	assert_ne(s.terrain.cells, old_terrain, "new terrain")
	assert_eq(c.display_terrain.cells, s.terrain.cells, "display rebuilt from the state")
	for t: TankState in s.tanks:
		assert_eq(c.get_tank_view(t.id).position, Vector2(t.x, t.y), "tanks repositioned")
		assert_false(c.get_tank_view(t.id).is_dead())
		assert_eq(c.get_tank_view(t.id).get_health(), SimConstants.MAX_HEALTH)

	_play_round(c)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_true(c.get_match_overlay().visible)
	assert_false(c.get_round_overlay().visible)
	assert_lte(c.round_wins[0] + c.round_wins[1], 2)
	assert_signal_emitted(c, "match_finished")
	assert_signal_emit_count(c, "round_finished", 2)
	assert_eq(c.mismatch_count, 0, "display always matched the state")
	assert_ne(c.get_match_overlay().get_title_text(), "")


func test_one_round_match_goes_straight_to_match_over() -> void:
	var c: BattleController = _make_round(1, 777)
	_play_round(c)
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	assert_true(c.get_match_overlay().visible)
	assert_false(c.get_round_overlay().visible)
	assert_eq(c.mismatch_count, 0)
	assert_eq(c.get_match_overlay().get_table().row_count(), 2, "final standings list every player")
	# NEW MATCH restarts: a fresh match opens in the shop.
	c.restart_match()
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)
	assert_eq(c.get_state().round_index, -1)
	assert_true(c.get_shop().is_showing_handover())
	assert_false(c.get_match_overlay().visible)
	assert_eq(c.round_wins, PackedInt32Array([0, 0]))
	assert_eq(c.get_state().seed, 777, "fixed seed replays the same match")
	for t: TankState in c.get_state().tanks:
		assert_eq(t.money, c.get_state().settings.start_money, "fresh money")


func test_standings_overlay_names_the_winner_or_a_draw() -> void:
	var o := MatchEndOverlay.new()
	add_child_autofree(o)
	var rows: Array[Dictionary] = [
		{"id": 0, "wins": 2, "damage": 300, "kills": 2},
		{"id": 1, "wins": 1, "damage": 400, "kills": 1},
	]
	o.show_standings([0, 1] as Array[int], rows)
	assert_eq(o.get_title_text(), "PLAYER 1 WINS THE MATCH")
	assert_true(o.get_table().get_text().begins_with("1. PLAYER 1"))
	var level: Array[Dictionary] = [
		{"id": 0, "wins": 1, "damage": 300, "kills": 1},
		{"id": 1, "wins": 1, "damage": 300, "kills": 1},
	]
	o.show_standings([0, 1] as Array[int], level)
	assert_eq(o.get_title_text(), "DRAW")
	var by_damage: Array[Dictionary] = [
		{"id": 0, "wins": 1, "damage": 100, "kills": 0},
		{"id": 1, "wins": 1, "damage": 250, "kills": 0},
	]
	o.show_standings([1, 0] as Array[int], by_damage)
	assert_eq(o.get_title_text(), "PLAYER 2 WINS THE MATCH", "tie-breaks decide, as Simulation.standings ordered them")


func test_pause_overlay_opens_and_closes() -> void:
	var c: BattleController = _make_round(3, SEED)
	assert_false(c.is_paused())
	c.get_hud().get_pause_button().pressed.emit()
	assert_true(c.is_paused())
	assert_true(get_tree().paused, "tree paused while the menu is open")
	assert_true(c.get_pause_overlay().visible)
	var resume: Button = c.get_pause_overlay().find_child("Resume", true, false)
	resume.pressed.emit()
	assert_false(c.is_paused())
	assert_false(get_tree().paused)
	# Android back button toggles it.
	c.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_true(c.is_paused())
	c.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(c.is_paused())
	assert_false(get_tree().is_quit_on_go_back(), "back is handled by the game, not the engine")


func test_back_in_a_nested_settings_dialog_closes_only_that_dialog() -> void:
	SettingsStore.path = "user://test_settings_flow.cfg"
	var c: BattleController = _make_round(3, SEED)
	c.open_pause()
	(c.get_pause_overlay().find_child("Settings", true, false) as Button).pressed.emit()
	var settings: SettingsOverlay = c.get_settings_overlay()
	assert_true(settings.is_open())
	settings.get_unlock_screen().open()
	c.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(settings.get_unlock_screen().is_open(), "Back closes the Unlock screen first")
	assert_true(settings.is_open(), "the settings stay")
	c.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_false(settings.is_open())
	assert_true(c.is_paused(), "and the pause menu is behind them")
	c.close_pause()
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH


func test_pause_menu_opens_settings_and_back_returns_to_it() -> void:
	SettingsStore.path = "user://test_settings_flow.cfg"
	var c: BattleController = _make_round(3, SEED)
	c.open_pause()
	(c.get_pause_overlay().find_child("Settings", true, false) as Button).pressed.emit()
	assert_true(c.get_settings_overlay().visible)
	assert_false(c.get_pause_overlay().visible, "the pause menu steps aside")
	(c.get_settings_overlay().get_toggle("Haptics") as Button).button_pressed = false
	assert_false(ShowSettings.haptics)
	(c.get_settings_overlay().get_toggle("Shake") as Button).button_pressed = false
	assert_false(ShowSettings.screen_shake)
	(c.get_settings_overlay().get_preview_button()).button_pressed = false
	assert_eq(ShowSettings.trajectory_preview, ShowSettings.PREVIEW_OFF)
	(c.get_settings_overlay().find_child("Back", true, false) as Button).pressed.emit()
	assert_false(c.get_settings_overlay().visible)
	assert_true(c.get_pause_overlay().visible, "BACK returns to the pause menu")
	c.close_pause()
	assert_false(c.get_preview().visible, "preview hidden when Off")
	c.set_aim(500, 500)
	assert_false(c.get_preview().visible)
	ShowSettings.trajectory_preview = ShowSettings.PREVIEW_SHORT
	c.set_aim(510, 500)
	assert_true(c.get_preview().visible)
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH


func test_restart_from_pause_menu_needs_a_second_tap() -> void:
	var c: BattleController = _make_round(3, SEED)
	c.fire_current()
	c.open_pause()
	var restart: Button = c.get_pause_overlay().find_child("Restart", true, false)
	restart.pressed.emit()
	assert_true(c.is_paused(), "the first tap only asks")
	assert_true(c.get_pause_overlay().is_restart_armed())
	restart.pressed.emit()
	assert_false(c.is_paused())
	assert_eq(c.get_state().turn_number, 0)
	assert_eq(c.get_state().round_index, -1, "a fresh match starts in the shop")
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)


func test_quit_to_title_changes_scene() -> void:
	var c: BattleController = _make(3, SEED)
	c.open_pause()
	(c.get_pause_overlay().find_child("Quit", true, false) as Button).pressed.emit()
	assert_false(get_tree().paused)
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_not_null(cur, "a scene is current")
	if cur != null:
		assert_eq(cur.scene_file_path, TITLE)
		assert_true(cur is TitleScreen)
		cur.queue_free()
		await wait_process_frames(2)


func test_title_screen_instantiates_and_start_opens_the_setup() -> void:
	BattleConfig.autosave_path = "user://test_title_none.crtl"
	SaveStore.delete(BattleConfig.autosave_path)
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_eq(t.get_logo_text(), "CHARRED HORIZONS")
	assert_false(t.get_continue_button().visible, "no save, no CONTINUE")
	assert_true(t.get_start_button().custom_minimum_size.y >= UiScale.touch())
	assert_gte(t.get_settings_button().custom_minimum_size.y, UiScale.touch() - 0.01)
	t.get_start_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_not_null(cur)
	if cur != null:
		assert_true(cur is SetupScreen, "START opens the match setup")
		cur.queue_free()
		await wait_process_frames(2)


func test_main_scene_is_title_and_demo_still_exists() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), TITLE)
	assert_true(ResourceLoader.exists("res://show/demo_battlefield.tscn"))


func test_speed_toggle_on_hud() -> void:
	var c: BattleController = _make_round(3, SEED)
	assert_eq(c.get_speed(), 1.0)
	c.get_hud().get_speed_button().pressed.emit()
	assert_eq(c.get_speed(), 2.0)
	assert_eq(c.get_hud().get_speed_button().text, "2x")
	c.get_hud().get_speed_button().pressed.emit()
	assert_eq(c.get_speed(), 1.0)


func test_preview_recomputes_once_per_frame_and_is_wind_free() -> void:
	var c: BattleController = _make_round(3, SEED)
	await wait_process_frames(2)
	var p: TrajectoryPreview = c.get_preview()
	var base: int = p.get_recompute_count()
	c.set_aim(500, 600)
	c.set_aim(510, 600)
	c.set_aim(520, 600)
	assert_eq(p.get_recompute_count(), base, "nothing computed synchronously")
	await wait_process_frames(2)
	assert_eq(p.get_recompute_count(), base + 1, "one rebuild for several changes in a frame")
	assert_gt(p.get_dot_count(), 2)
	await wait_process_frames(3)
	assert_eq(p.get_recompute_count(), base + 1, "idle frames do not recompute")
	# The preview must not depend on the state's wind.
	var s: MatchState = c.get_state()
	var id: int = s.current_tank
	var t0: Dictionary = Ballistics.trace(s, id, 520, 600, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	var windy: MatchState = s.duplicate_state()
	windy.wind = 100
	var t1: Dictionary = Ballistics.trace(windy, id, 520, 600, "pulse_missile", 0, SimConstants.MAX_FLIGHT_TICKS)
	assert_eq(t0["path"], t1["path"])


func test_real_time_playback_finishes_and_matches_state() -> void:
	var c: BattleController = _make(3, SEED, false)
	c.set_speed(2.0)
	_enter_round(c)
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	var first: int = c.get_state().current_tank
	assert_eq(c.fire_current(), "")
	assert_true(c.is_busy(), "input locked during playback")
	assert_eq(c.fire_current(), "busy")
	c.set_aim(100, 100)
	assert_ne(c.get_aim(first), Vector2i(100, 100), "aim ignored while locked")
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	assert_false(c.is_busy(), "playback ended")
	assert_ne(c.get_state().current_tank, first)
	assert_eq(c.mismatch_count, 0)
	assert_eq(c.display_terrain.cells, c.get_state().terrain.cells)
	assert_eq(c.get_hud().is_controls_locked(), false)


func test_projectile_path_conversion_matches_ballistics() -> void:
	# The shell is drawn from the Q16.16 path / 65536: first path point is next to the muzzle.
	var c: BattleController = _make_round(3, SEED)
	var s: MatchState = c.get_state()
	var tr: Dictionary = Ballistics.trace(s, s.current_tank, 450, 500, "pulse_missile",
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var path: PackedInt32Array = tr["path"]
	var tank: TankState = s.tanks[s.current_tank]
	var p0 := Vector2(float(path[0]) / 65536.0, float(path[1]) / 65536.0)
	assert_lt(p0.distance_to(Vector2(tank.x, tank.y - SimConstants.TANK_H)), 40.0)
