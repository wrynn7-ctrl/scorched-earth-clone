extends GutTest
## Love Edition in the battle (docs/ARCHITECTURE.md section 37): the love HUD and theme, hearts and bursts, the love meters, the
## flowers, the winner's smiley and overlay, REMATCH, autosave/continue, and a whole instant match against a
## scripted opponent. Everything is presentation; the outcome always comes from the simulation.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://test_love_autosave.crtl"
const SEED: int = 4242
const H: int = SimConstants.CTRL_HUMAN
const NORMAL: int = SimConstants.CTRL_NORMAL


func before_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	ShowSettings.haptics = false


func after_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	get_tree().paused = false


func _battle(controllers: Array = [H, H], instant: bool = true, autosave: bool = false) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(1, SEED, instant, 2)
	c.set_mode(SimConstants.MODE_LOVE)
	c.set_controllers(PackedInt32Array(controllers))
	if autosave:
		c.set_autosave_path(PATH)
	add_child_autofree(c)
	return c


## A heart action from `id` at the nearest enemy (the screenshot helper's ballistic search).
static func _heart_at_enemy(state: MatchState, id: int) -> Dictionary:
	var shot: Vector2i = AutoShot.find_shot(state, id)
	return {"kind": "fire", "tank": id, "angle": shot.x, "power": shot.y, "weapon": Catalog.HEART}


## Human turn: aim with the helper and fire through the controller.
func _human_heart(c: BattleController) -> String:
	var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
	c.set_aim(shot.x, shot.y)
	return c.fire_current()


## Plays turns until the match is over (or `limit` actions). P2 fires through the scripted override.
func _play_out(c: BattleController, limit: int = 60) -> int:
	var n: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and n < limit:
		n += 1
		if c.is_cpu_tank(c.get_state().current_tank):
			assert_gt(c.drive_cpu(), 0, "the scripted opponent acts")
		else:
			assert_eq(_human_heart(c), "")
	return n


# --- the look of a love match ----------------------------------------------------------------

func test_love_match_starts_in_aim_with_the_love_look() -> void:
	var c: BattleController = _battle()
	var st: MatchState = c.get_state()
	assert_eq(st.settings.mode, SimConstants.MODE_LOVE)
	assert_eq(st.phase, SimConstants.PHASE_AIM, "no shop in love mode")
	assert_true(c.is_love_mode())
	assert_eq(c.get_theme_id(), ThemeDefs.LOVE_THEME, "the rose sky")
	assert_eq(c.get_selected_weapon(), Catalog.HEART)
	for i: int in range(2):
		assert_true(c.get_tank_view(i).is_love_mode(), "love meter instead of the health bar")
		assert_eq(c.get_tank_view(i).get_love(), 0)
	# The HUD: weapon "Heart" with an infinity count; no money, items or move.
	var hud: BattleHud = c.get_hud()
	assert_eq(hud.get_weapon_button().get_name_text(), "Heart")
	assert_eq(hud.get_weapon_button().get_sub_text(), "∞")
	assert_false(hud.get_money_label().visible)
	assert_false(hud.get_move_controls().visible)
	assert_false(hud.get_items_toggle().visible)
	assert_true(hud.get_turn_banner().has_heart_accents())
	assert_eq(hud.get_wind_indicator().get_wind(), st.wind, "the wind shows from the first turn")


func test_the_love_theme_is_used_only_by_love_matches() -> void:
	var standard: BattleController = (load(BATTLE) as PackedScene).instantiate()
	standard.configure(1, SEED, true, 2)
	add_child_autofree(standard)
	assert_ne(standard.get_theme_id(), ThemeDefs.LOVE_THEME)
	assert_false(standard.get_hud().is_love_mode())
	assert_true(standard.get_hud().get_money_label().visible)
	assert_false(standard.get_tank_view(0).is_love_mode())


func test_hearts_are_not_a_standard_weapon() -> void:
	var standard: BattleController = (load(BATTLE) as PackedScene).instantiate()
	standard.configure(1, SEED, true, 2)
	add_child_autofree(standard)
	assert_true(standard.quick_start())
	assert_eq(standard.select_weapon(Catalog.HEART), "unknown_weapon")
	assert_ne(standard.get_selected_weapon(), Catalog.HEART)


# --- love meters ---------------------------------------------------------------------------

func test_a_hit_fills_the_love_meter_and_nothing_else_changes() -> void:
	var c: BattleController = _battle()
	var st: MatchState = c.get_state()
	var terrain_before: PackedByteArray = st.terrain.cells.duplicate()
	assert_eq(_human_heart(c), "")
	assert_gt(st.tanks[1].love, 0, "the heart reached the other tank")
	assert_eq(st.tanks[0].love, 0, "the shooter gets nothing")
	assert_eq(c.get_tank_view(1).get_love(), st.tanks[1].love, "the meter follows the love event")
	assert_eq(st.terrain.cells, terrain_before, "no terrain change")
	assert_eq(st.tanks[1].health, SimConstants.MAX_HEALTH, "no damage")
	assert_true(c.check_consistency())
	assert_eq(c.mismatch_count, 0)


func test_love_events_set_the_meters_directly() -> void:
	var c: BattleController = _battle()
	c._dispatch({"type": "love", "tick": 0, "tank": 1, "amount": 34, "love": 34, "from": 0})
	assert_eq(c.get_tank_view(1).get_love(), 34)
	c._dispatch({"type": "love", "tick": 0, "tank": 0, "amount": 50, "love": 50, "from": 1})
	assert_eq(c.get_tank_view(0).get_love(), 50)
	assert_almost_eq(c.get_tank_view(0).get_love_shown(), 0.5, 0.001, "instant mode snaps the fill")


func test_the_meter_fills_smoothly_and_pulses_when_animated() -> void:
	var v: TankView = (load("res://show/tank_view.tscn") as PackedScene).instantiate()
	add_child_autofree(v)
	v.set_love_mode(true)
	v.set_love(60, true)
	v.pulse_love()
	assert_eq(v.get_love(), 60)
	assert_eq(v.get_love_shown(), 0.0, "the fill starts from where it was")
	assert_true(v.is_love_pulsing())
	for _i: int in range(120):
		v._process(1.0 / 30.0)
	assert_almost_eq(v.get_love_shown(), 0.6, 0.001)
	assert_false(v.is_love_pulsing())
	assert_false(v.is_processing(), "idle again: no per-frame work")
	ShowSettings.reduce_motion = true
	v.set_love(100, true)
	assert_eq(v.get_love_shown(), 1.0, "reduced motion: no animation")
	v.pulse_love()
	assert_false(v.is_love_pulsing())


# --- flowers ---------------------------------------------------------------------------------

func _burst_event(x: int, radius: int = 30) -> Dictionary:
	return {"type": "heart_burst", "tick": 0, "x": x, "y": 200, "radius": radius}


func test_a_burst_sprouts_three_to_seven_flowers_on_the_surface() -> void:
	var c: BattleController = _battle()
	var f: FlowerField = c.get_flowers()
	assert_eq(f.flower_count(), 0)
	c._dispatch(_burst_event(800))
	assert_between(f.flower_count(), FlowerField.MIN_PER_IMPACT, FlowerField.MAX_PER_IMPACT)
	for i: int in range(f.flower_count()):
		var p: Vector2 = f.get_flower_position(i)
		var sy: int = c.display_terrain.surface_y(int(p.x))
		assert_almost_eq(p.y, float(sy) + 1.0, 0.01, "the flower stands on the terrain surface")
		assert_lte(absf(p.x - 800.0), 45.0, "around the impact")


func test_flowers_are_capped_and_the_oldest_are_reused() -> void:
	var c: BattleController = _battle()
	var f: FlowerField = c.get_flowers()
	for i: int in range(24):
		c._dispatch(_burst_event(100 + i * 60))
	assert_eq(f.flower_count(), FlowerField.MAX_FLOWERS, "never more than the cap")
	assert_lte(c.get_love_impacts().size(), FlowerField.MAX_FLOWERS, "the save keeps a bounded list")
	var nodes: int = c.get_node("World").get_child_count()
	for i: int in range(24):
		c._dispatch(_burst_event(100 + i * 60))
	assert_eq(c.get_node("World").get_child_count(), nodes, "no node is created per flower")


func test_flowers_stay_clear_of_the_tanks() -> void:
	var c: BattleController = _battle()
	var t: TankState = c.get_state().tanks[0]
	c._dispatch({"type": "heart_burst", "tick": 0, "x": t.x, "y": t.y - 10, "radius": 30})
	var f: FlowerField = c.get_flowers()
	for i: int in range(f.flower_count()):
		assert_gte(absf(f.get_flower_position(i).x - float(t.x)), FlowerField.TANK_CLEAR - 1.0, "not under the tank")


func test_a_real_shot_plants_flowers_where_it_landed() -> void:
	var c: BattleController = _battle()
	assert_eq(_human_heart(c), "")
	assert_gte(c.get_flowers().flower_count(), FlowerField.MIN_PER_IMPACT)
	assert_eq(c.get_love_impacts().size(), 1)


# --- no shake, no flashing -------------------------------------------------------------------

func test_love_mode_never_shakes_the_camera() -> void:
	var c: BattleController = _battle([H, H], false)
	var cam: CameraShake = c.get_node("Camera") as CameraShake
	_pump(c, 1.0)
	assert_eq(_human_heart(c), "")
	var guard: int = 0
	while c.is_busy() and guard < 1500:
		c._process(1.0 / 60.0)
		assert_false(cam.is_shaking(), "no screen shake in love mode")
		guard += 1
	assert_lt(guard, 1500, "the shot played out")
	assert_eq(c.get_tank_view(1).get_love() > 0, true)


func test_reduced_flashing_dims_the_burst() -> void:
	var b := HeartBurst.new()
	add_child_autofree(b)
	b.play(Vector2(100, 100), 30.0)
	var full: float = (b.get_node("Flash") as Sprite2D).modulate.a
	ShowSettings.reduce_flashing = true
	b.play(Vector2(100, 100), 30.0)
	var dim: float = (b.get_node("Flash") as Sprite2D).modulate.a
	assert_lt(dim, full * 0.5, "less bright with reduced flashing")


# --- animated playback ---------------------------------------------------------------------

func _pump(c: BattleController, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		c._process(1.0 / 60.0)
		t += 1.0 / 60.0


func test_animated_shot_shows_heart_shell_burst_popup_and_flowers() -> void:
	var c: BattleController = _battle([H, H], false)
	_pump(c, 1.0)
	assert_eq(_human_heart(c), "")
	var saw_heart_shell: bool = false
	var saw_burst: bool = false
	var guard: int = 0
	while c.is_busy() and guard < 1500:
		c._process(1.0 / 60.0)
		for t: ShellTrail in c._trail_pool:
			saw_heart_shell = saw_heart_shell or (t.visible and t.is_heart_style())
		for b: HeartBurst in c.get_heart_bursts():
			saw_burst = saw_burst or b.is_playing()
		guard += 1
	assert_true(saw_heart_shell, "the shell is a heart")
	assert_true(saw_burst, "the burst played")
	var popped: bool = false
	for p: LovePopup in c.get_love_popups():
		popped = popped or p.get_amount() > 0
	assert_true(popped, "the +N popup showed")
	await wait_seconds(0.6)
	assert_gte(c.get_flowers().flower_count(), FlowerField.MIN_PER_IMPACT, "flowers sprout after the burst")
	for e: Explosion in c._fx:
		assert_false(e.is_playing(), "no explosion in love mode")


# --- the win ---------------------------------------------------------------------------------

func _near_win(c: BattleController) -> void:
	c.get_state().tanks[1].love = 90
	c._rebuild_display()


func test_filling_a_meter_wins_with_smiley_confetti_and_the_overlay() -> void:
	var c: BattleController = _battle()
	_near_win(c)
	assert_eq(_human_heart(c), "")
	var st: MatchState = c.get_state()
	assert_eq(st.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(st.tanks[1].love, 100)
	var smiley: LoveSmiley = c.get_smiley()
	assert_true(smiley.is_showing(), "the smiley floats up")
	var winner_view: TankView = c.get_tank_view(0)
	assert_almost_eq(smiley.get_rest_position().x, winner_view.position.x, 0.01, "over the winning tank")
	assert_lt(smiley.get_rest_position().y, winner_view.position.y - 100.0, "well above it")
	assert_eq(smiley.orbit_heart_count(), LoveSmiley.ORBIT_HEARTS, "hearts orbit it")
	assert_true(c.get_confetti().is_active(), "heart confetti")
	var o: LoveWinOverlay = c.get_love_overlay()
	assert_true(o.is_open())
	assert_eq(o.get_title_text(), "PLAYER 1 WINS")
	assert_false(c.get_hud().visible, "the HUD gives way to the celebration")
	assert_false(c.get_match_overlay().is_open(), "not the standard standings")
	assert_eq(c.get_round_overlay().visible, false)


func test_the_other_player_can_win_too() -> void:
	var c: BattleController = _battle()
	assert_eq(c.get_state().current_tank, 0)
	c.get_state().tanks[0].love = 99
	c._rebuild_display()
	c.pass_turn()
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(_human_heart(c), "")
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(c.get_love_overlay().get_title_text(), "PLAYER 2 WINS")
	assert_almost_eq(c.get_smiley().get_rest_position().x, c.get_tank_view(1).position.x, 0.01)


func test_the_overlay_is_a_bottom_strip_that_leaves_the_tanks_visible() -> void:
	var c: BattleController = _battle()
	_near_win(c)
	assert_eq(_human_heart(c), "")
	await wait_process_frames(3)
	var o: LoveWinOverlay = c.get_love_overlay()
	var vis: Rect2 = c.get_viewport().get_visible_rect()
	var r: Rect2 = o.get_panel().get_global_rect()
	assert_gt(r.get_center().y, vis.size.y * 0.7, "along the bottom edge")
	assert_true(vis.grow(1.5).encloses(r), "inside the screen")


func test_rematch_starts_a_fresh_love_match_with_the_same_players() -> void:
	var c: BattleController = _battle([H, NORMAL], true, true)
	PlayerLooks.set_looks(PackedInt32Array([6, 5]), PackedInt32Array([4, 0]))
	_near_win(c)
	assert_eq(_human_heart(c), "")
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	assert_gt(c.get_flowers().flower_count(), 0)
	c.get_love_overlay().get_rematch_button().pressed.emit()
	var st: MatchState = c.get_state()
	assert_eq(st.settings.mode, SimConstants.MODE_LOVE, "still a love match")
	assert_eq(st.settings.controllers, PackedInt32Array([H, NORMAL]), "the same players")
	assert_eq(st.phase, SimConstants.PHASE_AIM)
	assert_eq(st.tanks[0].love, 0)
	assert_eq(st.tanks[1].love, 0)
	assert_eq(c.get_session().actions.size(), 0, "a fresh session")
	assert_eq(c.get_flowers().flower_count(), 0, "the garden is cleared")
	assert_false(c.get_smiley().is_showing())
	assert_false(c.get_confetti().is_active())
	assert_false(c.get_love_overlay().is_open())
	assert_true(c.get_hud().visible)
	assert_eq(c.get_tank_view(1).get_love(), 0)
	assert_eq(PlayerLooks.color_index(0), 6, "same colours")
	assert_eq(c.get_theme_id(), ThemeDefs.LOVE_THEME)


func test_the_title_button_of_the_overlay_leaves_the_match() -> void:
	var c: BattleController = _battle()
	_near_win(c)
	assert_eq(_human_heart(c), "")
	watch_signals(c.get_love_overlay())
	c.get_love_overlay().get_title_button().pressed.emit()
	assert_signal_emitted(c.get_love_overlay(), "title_pressed")
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is TitleScreen, "back at the title")
	if cur != null:
		cur.queue_free()
		await wait_process_frames(2)


# --- a whole match -------------------------------------------------------------------------

func test_instant_love_match_against_a_scripted_opponent_runs_to_the_win() -> void:
	var c: BattleController = _battle([H, NORMAL])
	# The scripted opponent fires hearts with the ballistic helper (whatever AiPlayer does).
	c.cpu_action_override = func(state: MatchState, id: int) -> Dictionary: return _heart_at_enemy(state, id)
	var turns: int = _play_out(c)
	var st: MatchState = c.get_state()
	assert_eq(st.phase, SimConstants.PHASE_MATCH_OVER, "the match reaches its win (%d turns)" % turns)
	var winner: int = -1
	for t: TankState in st.tanks:
		if t.love >= SimConstants.LOVE_MAX:
			winner = 1 - t.id
	assert_ne(winner, -1, "somebody's meter is full")
	assert_true(c.get_love_overlay().is_open())
	assert_eq(c.get_love_overlay().get_title_text(), "PLAYER %d WINS" % (winner + 1))
	assert_eq(c.cpu_fallbacks, 0, "the opponent only fired hearts")
	assert_eq(c.mismatch_count, 0, "the display always matched the simulation")
	assert_true(c.check_consistency())


func test_the_real_ai_keeps_a_love_match_going() -> void:
	# Whatever AiPlayer answers, the controller validates it; a bad answer becomes a pass, so the match goes on.
	var c: BattleController = _battle([H, NORMAL])
	assert_eq(_human_heart(c), "")
	assert_eq(c.get_state().phase, SimConstants.PHASE_AIM)
	assert_eq(c.get_state().current_tank, 1)
	assert_true(c.is_cpu_tank(1))
	assert_gt(c.drive_cpu(), 0, "the CPU acted")
	var done: bool = c.get_state().phase == SimConstants.PHASE_MATCH_OVER
	assert_true(done or c.get_state().current_tank == 0, "the turn came back to the human")
	for e: Dictionary in c.get_session().actions:
		assert_true(e["kind"] == "fire" or e["kind"] == "pass", "only legal love actions were logged")


# --- autosave and continue ---------------------------------------------------------------------

func test_a_love_match_saves_and_continues_with_meters_and_flowers() -> void:
	var c: BattleController = _battle([H, H], true, true)
	assert_eq(_human_heart(c), "")
	var love_before: int = c.get_state().tanks[1].love
	var flowers_before: int = c.get_flowers().flower_count()
	assert_gt(love_before, 0)
	assert_true(c.autosave_now())
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_true(res["ok"], str(res["error"]))
	assert_eq((res["state"] as MatchState).settings.mode, SimConstants.MODE_LOVE, "the mode is in the saved state")
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_true(r.is_love_mode(), "continues as a love match")
	assert_eq(r.get_state().tanks[1].love, love_before)
	assert_eq(r.get_tank_view(1).get_love(), love_before, "the meter shows the saved love")
	assert_eq(r.get_theme_id(), ThemeDefs.LOVE_THEME)
	assert_eq(r.get_flowers().flower_count(), flowers_before, "the same garden grows back")
	assert_false(r.get_hud().get_money_label().visible)
	assert_eq(r.get_hud().get_wind_indicator().get_wind(), r.get_state().wind)
	assert_eq(Simulation.fingerprint(r.get_state()), Simulation.fingerprint(c.get_state()))
	assert_eq(r.get_state().phase, SimConstants.PHASE_AIM)
