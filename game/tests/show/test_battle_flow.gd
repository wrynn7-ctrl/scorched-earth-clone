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
	get_tree().paused = false


func _make(rounds: int, seed_value: int, instant: bool = true) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, seed_value, instant)
	add_child_autofree(c)
	return c


## Plays AutoShot turns until the phase leaves "aim". Returns the number of shots fired.
func _play_round(c: BattleController, max_shots: int = 60) -> int:
	var shots: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and shots < max_shots:
		var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
		c.set_aim(shot.x, shot.y)
		assert_eq(c.fire_current(), "", "shot %d accepted" % shots)
		shots += 1
	return shots


func test_battle_scene_instantiates_with_fixed_seed() -> void:
	var c: BattleController = _make(3, SEED)
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
	var d: BattleController = _make(3, SEED)
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(s))


func test_fire_advances_turn_and_display_matches_state() -> void:
	var c: BattleController = _make(3, SEED)
	var first: int = c.get_state().current_tank
	assert_eq(c.fire_current(), "")
	var s: MatchState = c.get_state()
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_ne(s.current_tank, first, "turn passes to the other player")
	assert_eq(s.turn_number, 1)
	assert_eq(c.display_terrain.cells, s.terrain.cells, "terrain bytes identical after playback")
	assert_eq(c.mismatch_count, 0)
	assert_false(c.is_busy(), "input unlocked again")
	assert_eq(c.timelines_played(), 1)


func test_each_tank_remembers_its_own_aim() -> void:
	var c: BattleController = _make(3, SEED)
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
	var c: BattleController = _make(3, SEED)
	var before: String = Simulation.fingerprint(c.get_state())
	var cur: int = c.get_state().current_tank
	c.set_aim(450, 0)  # the slider allows 0, validate_action does not
	assert_eq(c.fire_current(), "bad_power")
	assert_eq(Simulation.fingerprint(c.get_state()), before, "state untouched")
	assert_eq(c.get_state().current_tank, cur)
	assert_eq(c.timelines_played(), 0)
	assert_false(c.is_busy())
	assert_ne(c.get_toast().get_text(), "", "a toast explains the problem")
	assert_true(c.get_toast().visible)
	# And the same through the pure API.
	var bad: Dictionary = {"kind": "fire", "tank": cur, "angle": 450, "power": 0, "weapon": "pulse_missile"}
	assert_eq(Simulation.validate_action(c.get_state(), bad), "bad_power")


func test_scripted_match_reaches_round_end_next_round_and_match_over() -> void:
	var c: BattleController = _make(2, SEED)
	watch_signals(c)
	_play_round(c)
	var s: MatchState = c.get_state()
	assert_eq(s.phase, SimConstants.PHASE_ROUND_OVER, "first round ends")
	assert_true(c.get_round_overlay().visible, "round overlay is shown")
	assert_true(c.is_busy(), "no aiming while the overlay is open")
	assert_eq(c.fire_current(), "busy")
	var wins_after_1: int = c.round_wins[0] + c.round_wins[1]
	assert_lte(wins_after_1, 1)
	assert_eq(c.get_round_overlay().get_tally_text().count("PLAYER"), 2)
	assert_eq(c.display_terrain.cells, s.terrain.cells)

	var old_terrain: PackedByteArray = s.terrain.cells.duplicate()
	c.next_round()
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_eq(s.round_index, 1)
	assert_false(c.get_round_overlay().visible)
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
	var c: BattleController = _make(1, 777)
	_play_round(c)
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	assert_true(c.get_match_overlay().visible)
	assert_false(c.get_round_overlay().visible)
	assert_eq(c.mismatch_count, 0)
	# NEW MATCH restarts.
	c.restart_match()
	assert_eq(c.get_state().phase, SimConstants.PHASE_AIM)
	assert_eq(c.get_state().round_index, 0)
	assert_false(c.get_match_overlay().visible)
	assert_eq(c.round_wins, PackedInt32Array([0, 0]))
	assert_eq(c.get_state().seed, 777, "fixed seed replays the same match")


func test_match_winner_helper() -> void:
	assert_eq(MatchEndOverlay.match_winner(PackedInt32Array([2, 1])), 0)
	assert_eq(MatchEndOverlay.match_winner(PackedInt32Array([0, 3])), 1)
	assert_eq(MatchEndOverlay.match_winner(PackedInt32Array([1, 1])), -1)
	assert_eq(MatchEndOverlay.match_winner(PackedInt32Array([0, 0])), -1)


func test_pause_overlay_opens_and_closes() -> void:
	var c: BattleController = _make(3, SEED)
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


func test_pause_settings_toggles_write_show_settings() -> void:
	var c: BattleController = _make(3, SEED)
	c.open_pause()
	var o: PauseOverlay = c.get_pause_overlay()
	(o.find_child("Haptics", true, false) as Button).button_pressed = false
	assert_false(ShowSettings.haptics)
	(o.find_child("Shake", true, false) as Button).button_pressed = false
	assert_false(ShowSettings.screen_shake)
	(o.find_child("ReduceFlashing", true, false) as Button).button_pressed = true
	assert_true(ShowSettings.reduce_flashing)
	(o.find_child("Preview", true, false) as Button).button_pressed = false
	assert_eq(ShowSettings.trajectory_preview, ShowSettings.PREVIEW_OFF)
	c.close_pause()
	assert_false(c.get_preview().visible, "preview hidden when Off")
	c.set_aim(500, 500)
	assert_false(c.get_preview().visible)
	ShowSettings.trajectory_preview = ShowSettings.PREVIEW_SHORT
	c.set_aim(510, 500)
	assert_true(c.get_preview().visible)


func test_restart_from_pause_menu() -> void:
	var c: BattleController = _make(3, SEED)
	c.fire_current()
	c.open_pause()
	(c.get_pause_overlay().find_child("Restart", true, false) as Button).pressed.emit()
	assert_false(c.is_paused())
	assert_eq(c.get_state().turn_number, 0)
	assert_eq(c.get_state().round_index, 0)
	assert_eq(c.display_terrain.cells, c.get_state().terrain.cells)


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


func test_title_screen_instantiates_and_starts_battle() -> void:
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_eq(t.get_logo_text(), "CRATERLINE")
	assert_eq(t.get_selected_rounds(), 3, "default 3 rounds")
	assert_eq(t.get_rounds_buttons().size(), 3)
	t.get_rounds_buttons()[2].pressed.emit()
	assert_eq(t.get_selected_rounds(), 5)
	t.get_rounds_buttons()[0].pressed.emit()
	assert_eq(t.get_selected_rounds(), 1)
	assert_true(t.get_start_button().custom_minimum_size.y >= UiScale.touch())
	t.get_rounds_buttons()[1].pressed.emit()
	t.get_start_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_not_null(cur)
	if cur != null:
		assert_true(cur is BattleController)
		assert_eq((cur as BattleController).get_state().settings.rounds, 3)
		cur.queue_free()
		await wait_process_frames(2)


func test_main_scene_is_title_and_demo_still_exists() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), TITLE)
	assert_true(ResourceLoader.exists("res://show/demo_battlefield.tscn"))


func test_speed_toggle_on_hud() -> void:
	var c: BattleController = _make(3, SEED)
	assert_eq(c.get_speed(), 1.0)
	c.get_hud().get_speed_button().pressed.emit()
	assert_eq(c.get_speed(), 2.0)
	assert_eq(c.get_hud().get_speed_button().text, "2x")
	c.get_hud().get_speed_button().pressed.emit()
	assert_eq(c.get_speed(), 1.0)


func test_preview_recomputes_once_per_frame_and_is_wind_free() -> void:
	var c: BattleController = _make(3, SEED)
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
	var c: BattleController = _make(3, SEED)
	var s: MatchState = c.get_state()
	var tr: Dictionary = Ballistics.trace(s, s.current_tank, 450, 500, "pulse_missile",
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var path: PackedInt32Array = tr["path"]
	var tank: TankState = s.tanks[s.current_tank]
	var p0 := Vector2(float(path[0]) / 65536.0, float(path[1]) / 65536.0)
	assert_lt(p0.distance_to(Vector2(tank.x, tank.y - SimConstants.TANK_H)), 40.0)
