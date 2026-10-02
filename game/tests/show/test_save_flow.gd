extends GutTest
## Autosave and CONTINUE: compressed atomic saves, restoring a match mid-turn or mid-shop.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const TITLE: String = "res://ui/title/title_screen.tscn"
const PATH: String = "user://test_flow_autosave.crtl"
const SEED: int = 31337


func before_each() -> void:
	SaveStore.delete(PATH)


func after_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	get_tree().paused = false


func _new(players: int = 2, rounds: int = 3) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, SEED, true, players)
	c.set_autosave_path(PATH)
	add_child_autofree(c)
	return c


func _resume() -> BattleController:
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(c)
	return c


func _state(seed_value: int = 5) -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = 3
	m.rounds = 3
	m.seed = seed_value
	var s: MatchState = Simulation.new_match(m)
	for t: TankState in s.tanks:
		Simulation.apply_action(s, {"kind": "ready", "tank": t.id})
	Simulation.start_round(s)
	return s


# --- SaveStore: compression and meta -----------------------------------------------------

func test_saves_are_zstd_compressed_with_the_uncompressed_size_in_the_header() -> void:
	var s: MatchState = _state()
	var actions: Array[Dictionary] = [{"kind": "ready", "tank": 0}]
	assert_true(SaveStore.save(s, actions, PATH))
	var file_bytes: PackedByteArray = SaveStore.read_file(PATH)
	assert_eq(file_bytes.slice(0, 4).get_string_from_ascii(), "CRZ1")
	var raw: PackedByteArray = SaveCodec.encode(s, actions)
	var head := StreamPeerBuffer.new()
	head.data_array = file_bytes.slice(4, 8)
	assert_eq(head.get_32(), raw.size(), "header holds the uncompressed size")
	assert_lt(file_bytes.size(), raw.size() / 4, "terrain compresses a lot")
	assert_eq(SaveStore.read_bytes(PATH), raw, "read_bytes returns the codec bytes")
	assert_eq(SaveStore.last_raw_bytes, raw.size())
	assert_eq(SaveStore.last_file_bytes, file_bytes.size())
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(Simulation.fingerprint(res["state"] as MatchState), Simulation.fingerprint(s))
	gut.p("save size: %d -> %d bytes (%.1f%%), encode+compress %.2f ms" % [raw.size(), file_bytes.size(),
			100.0 * float(file_bytes.size()) / float(raw.size()), SaveStore.last_encode_ms])
	var t0: int = Time.get_ticks_usec()
	SaveStore.load_save(PATH)
	gut.p("load + decompress + decode: %.2f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))


func test_meta_round_trips_and_is_not_part_of_the_state() -> void:
	var s: MatchState = _state()
	var meta: Dictionary = {"looks": {"colors": [3, 1, 2], "emblems": [0, 1, 5]}, "round_money": [1, 2, 3]}
	var before: String = Simulation.fingerprint(s)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], PATH, meta))
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_eq((res["meta"] as Dictionary)["round_money"], [1.0, 2.0, 3.0], "JSON numbers")
	assert_eq(Simulation.fingerprint(res["state"] as MatchState), before)


func test_uncompressed_saves_still_load() -> void:
	var s: MatchState = _state()
	assert_true(SaveStore.write_bytes(SaveCodec.encode(s, [] as Array[Dictionary]), PATH))
	assert_true(SaveStore.has_valid_save(PATH))
	assert_eq(Simulation.fingerprint(SaveStore.load_save(PATH)["state"] as MatchState), Simulation.fingerprint(s))


func test_damaged_compressed_saves_are_rejected() -> void:
	var s: MatchState = _state()
	SaveStore.save(s, [] as Array[Dictionary], PATH)
	var bytes: PackedByteArray = SaveStore.read_file(PATH)
	var cut: PackedByteArray = bytes.slice(0, bytes.size() / 2)
	SaveStore.write_bytes(cut, PATH)
	assert_false(SaveStore.has_valid_save(PATH), "truncated")
	var flipped: PackedByteArray = bytes.duplicate()
	flipped[flipped.size() - 20] = flipped[flipped.size() - 20] ^ 0xFF
	SaveStore.write_bytes(flipped, PATH)
	assert_false(SaveStore.has_valid_save(PATH), "bit flip inside the payload")
	var header_only: PackedByteArray = bytes.slice(0, 11)
	SaveStore.write_bytes(header_only, PATH)
	assert_false(SaveStore.has_valid_save(PATH))
	var lying: PackedByteArray = bytes.duplicate()
	lying[4] = 0xFF
	lying[7] = 0x7F  # claims a huge uncompressed size
	SaveStore.write_bytes(lying, PATH)
	assert_false(SaveStore.has_valid_save(PATH), "a wrong size header")


func test_the_write_is_atomic() -> void:
	var s: MatchState = _state()
	SaveStore.save(s, [] as Array[Dictionary], PATH)
	assert_false(FileAccess.file_exists(PATH + SaveStore.TMP_SUFFIX))
	var good: PackedByteArray = SaveStore.read_file(PATH)
	assert_false(SaveStore.write_bytes(PackedByteArray([1]), "user://no_such_dir_abc/x.crtl"))
	assert_eq(SaveStore.read_file(PATH), good, "a failed write leaves the old save")


# --- autosave from the battle --------------------------------------------------------------

func test_the_action_log_holds_every_applied_action_normalized() -> void:
	var c: BattleController = _new()
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1.0})
	c.quick_start()
	c.select_weapon("pulse_missile")
	c.fire_current()
	c.move_current(1)  # refused: no fuel; must not be logged
	var log: Array[Dictionary] = c.get_session().actions
	var kinds: Array[String] = []
	for a: Dictionary in log:
		kinds.append(a["kind"])
	assert_eq(kinds, ["buy", "ready", "ready", "fire"] as Array[String])
	assert_eq(typeof(log[0]["qty"]), TYPE_INT, "whole-number floats were turned into ints")
	assert_eq(log[3]["weapon"], "pulse_missile")


func test_autosave_runs_after_resolved_actions_and_on_pause() -> void:
	var c: BattleController = _new()
	assert_false(FileAccess.file_exists(PATH))
	c.quick_start()
	c.fire_current()
	assert_true(FileAccess.file_exists(PATH), "saved once the shot resolved")
	assert_true(SaveStore.has_valid_save(PATH))
	var n: int = c.autosaves_done()
	assert_gt(n, 0)
	SaveStore.delete(PATH)
	c.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(SaveStore.has_valid_save(PATH), "saved when the app is paused")
	SaveStore.delete(PATH)
	c.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	assert_true(SaveStore.has_valid_save(PATH), "saved on close")


func test_shop_actions_are_saved_too() -> void:
	var c: BattleController = _new()
	assert_eq(c.get_shop().get_screen().get_player(), 0)
	c.get_shop().get_handover().get_tap_button().pressed.emit()
	c.get_shop().get_screen().select("pulse_missile")
	c.get_shop().get_screen().get_detail().get_buy_button().pressed.emit()
	assert_true(SaveStore.has_valid_save(PATH), "a purchase is saved")
	var restored: Dictionary = SaveStore.load_save(PATH)
	assert_eq((restored["state"] as MatchState).tanks[0].stock_of("pulse_missile"), 5)


func test_autosave_then_reload_gives_the_identical_match_mid_turn() -> void:
	PlayerLooks.set_looks(PackedInt32Array([4, 6, 1]), PackedInt32Array([2, 0, 7]))
	var c: BattleController = _new(3)
	c.get_session().submit({"kind": "buy", "tank": 1, "item": "fuel_cell", "qty": 2})
	c.quick_start()
	c.fire_current()  # player 1 fires -> player 2's turn
	c.fire_current()  # player 2 fires -> player 3's turn
	var st: MatchState = c.get_state()
	assert_eq(st.current_tank, 2)
	var want: String = Simulation.fingerprint(st)
	assert_true(c.autosave_now())
	PlayerLooks.reset()  # a fresh process knows nothing
	var d: BattleController = _resume()
	assert_eq(Simulation.fingerprint(d.get_state()), want, "identical state")
	assert_eq(d.get_state().current_tank, 2)
	assert_eq(d.get_state().phase, SimConstants.PHASE_AIM)
	assert_eq(d.get_hud().get_turn_banner().get_text(), "PLAYER 3'S TURN", "the HUD shows the right player")
	assert_eq(d.get_hud().get_money_label().get_amount(), d.get_state().tanks[2].money)
	assert_eq(d.get_session().actions, c.get_session().actions, "the action log survives")
	assert_false(d.is_busy(), "ready to aim")
	assert_eq(d.display_terrain.cells, d.get_state().terrain.cells)
	assert_eq(d.get_tank_view(0).get_color_index(), 4, "colours and emblems survive")
	assert_eq(d.get_tank_view(0).get_emblem_index(), 2)
	assert_eq(PlayerLooks.color_index(1), 6)
	assert_eq(d.mismatch_count, 0)
	# And it keeps playing identically.
	var a: Dictionary = {"kind": "fire", "tank": 2, "angle": 600, "power": 480, "weapon": "spark_dart"}
	Simulation.apply_action(st, a)
	assert_eq(d.get_session().submit(a)["err"], "")
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(st))


func test_reload_restores_shields_and_the_move_buttons() -> void:
	var c: BattleController = _new()
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "glow_shield", "qty": 1})
	c.get_session().submit({"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 1})
	c.quick_start()
	assert_eq(c.use_item("glow_shield"), "")
	assert_eq(c.move_current(1), "")
	assert_true(c.autosave_now())
	var d: BattleController = _resume()
	assert_true(d.get_tank_view(0).has_shield_bubble(), "the bubble is back")
	assert_eq(d.get_tank_view(0).get_shield_hp(), 30)
	assert_true(d.get_hud().get_move_controls().visible)
	assert_eq(d.get_hud().get_move_controls().get_fuel_total(), c.get_state().tanks[0].fuel)
	assert_eq(d.get_tank_view(0).position, Vector2(d.get_state().tanks[0].x, d.get_state().tanks[0].y))


func test_reload_in_the_shop_continues_with_the_next_player_who_is_not_ready() -> void:
	var c: BattleController = _new(3)
	c.get_shop().get_handover().get_tap_button().pressed.emit()
	c.get_shop().get_screen().select("hyperpulse")
	c.get_shop().get_screen().get_detail().get_buy_button().pressed.emit()
	c.get_shop().get_screen().get_ready_button().pressed.emit()
	assert_true(c.autosave_now())
	var d: BattleController = _resume()
	assert_eq(d.get_state().phase, SimConstants.PHASE_SHOP)
	assert_true(d.get_state().tanks[0].ready)
	assert_eq(d.get_state().tanks[0].stock_of("hyperpulse"), 3)
	assert_true(d.get_shop().is_showing_handover())
	assert_eq(d.get_shop().get_handover().get_title_text(), "PLAYER 2 — YOUR SHOP")
	assert_eq(d.get_state().tanks[0].money, 7500)
	assert_false(d.get_hud().visible)


func test_reload_after_a_round_shows_the_summary_with_the_earnings() -> void:
	var c: BattleController = _new(2, 2)
	for t: TankState in c.get_state().tanks:
		c.get_session().submit({"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 4})
	c.quick_start()
	var guard: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and guard < 100:
		var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
		c.set_aim(shot.x, shot.y)
		c.select_weapon("pulse_missile")
		c.fire_current()
		guard += 1
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)
	assert_true(c.get_round_overlay().visible)
	var d: BattleController = _resume()
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(c.get_state()))
	assert_true(d.get_round_overlay().visible, "still on the round summary")
	assert_eq(d.round_earnings(0), c.round_earnings(0))
	assert_eq(d.round_earnings(1), c.round_earnings(1))
	assert_eq(d.get_round_overlay().get_table().get_text(), c.get_round_overlay().get_table().get_text())
	d.get_round_overlay().get_next_button().pressed.emit()
	assert_true(d.get_shop().is_showing_handover())


func test_a_missing_or_damaged_save_starts_a_fresh_match() -> void:
	var d: BattleController = _resume()
	assert_eq(d.get_state().phase, SimConstants.PHASE_SHOP)
	assert_eq(d.get_state().round_index, -1)
	assert_eq(d.get_state().tanks.size(), 2)


func test_the_autosave_is_deleted_when_the_match_ends_and_replaced_by_a_new_one() -> void:
	var c: BattleController = _new(2, 1)
	for t: TankState in c.get_state().tanks:
		c.get_session().submit({"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 4})
	c.quick_start()
	c.fire_current()
	assert_true(FileAccess.file_exists(PATH))
	var guard: int = 0
	while c.get_state().phase == SimConstants.PHASE_AIM and guard < 100:
		var shot: Vector2i = AutoShot.find_shot(c.get_state(), c.get_state().current_tank)
		c.set_aim(shot.x, shot.y)
		c.select_weapon("pulse_missile")
		c.fire_current()
		guard += 1
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER)
	assert_false(FileAccess.file_exists(PATH), "nothing to continue after the final standings")
	c.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_false(FileAccess.file_exists(PATH), "and pausing does not bring it back")
	# NEW MATCH starts again and saves again.
	c.restart_match()
	c.get_shop().get_handover().get_tap_button().pressed.emit()
	c.get_shop().get_screen().get_ready_button().pressed.emit()
	assert_true(c.autosave_now())
	assert_true(FileAccess.file_exists(PATH))
	c.restart_match()
	assert_false(FileAccess.file_exists(PATH), "restarting discards the old save")


# --- title: CONTINUE ------------------------------------------------------------------------

func test_title_offers_continue_only_with_a_valid_save() -> void:
	BattleConfig.autosave_path = PATH
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_false(t.get_continue_button().visible)
	var c: BattleController = _new()
	c.quick_start()
	c.fire_current()
	t.refresh_continue()
	assert_true(t.get_continue_button().visible)
	SaveStore.write_bytes("garbage".to_ascii_buffer(), PATH)
	t.refresh_continue()
	assert_false(t.get_continue_button().visible, "a damaged save is not offered")


func test_start_asks_before_discarding_a_save_and_continue_restores_it() -> void:
	var c: BattleController = _new(3)
	c.quick_start()
	c.fire_current()
	var want: String = Simulation.fingerprint(c.get_state())
	BattleConfig.autosave_path = PATH
	BattleConfig.instant = true
	var t: TitleScreen = (load(TITLE) as PackedScene).instantiate()
	add_child_autofree(t)
	await wait_process_frames(2)
	assert_true(t.get_continue_button().visible)
	t.get_start_button().pressed.emit()
	assert_true(t.get_confirm_overlay().visible, "START asks first")
	(t.get_confirm_overlay().find_child("Cancel", true, false) as Button).pressed.emit()
	assert_false(t.get_confirm_overlay().visible)
	assert_true(FileAccess.file_exists(PATH), "cancel keeps the save")
	t.get_continue_button().pressed.emit()
	await wait_process_frames(3)
	var cur: Node = get_tree().current_scene
	assert_true(cur is BattleController)
	if cur is BattleController:
		assert_eq(Simulation.fingerprint((cur as BattleController).get_state()), want, "CONTINUE restores the match")
		cur.queue_free()
		await wait_process_frames(2)
