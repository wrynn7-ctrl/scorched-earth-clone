extends GutTest
## The big "<NAME>'S TURN" banner of pass-and-play (ARCHITECTURE section 42): only with two or more
## humans, never for a CPU, never after a restore or in instant mode, never in the way of input,
## and calm when motion is reduced. Plus the name tags and the names in autosave meta.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://test_names_autosave.crtl"
const SEED: int = 4242

const H: int = SimConstants.CTRL_HUMAN
const NORMAL: int = SimConstants.CTRL_NORMAL


func before_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	PlayerNames.reset()


func after_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()
	get_tree().paused = false


## A battle (not instant, so timelines play and the banner may show) whose round has started and
## whose opening timeline has finished.
func _battle(controllers: Array, names: PackedStringArray = PackedStringArray(), love: bool = false, instant: bool = false) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant, controllers.size())
	c.set_controllers(PackedInt32Array(controllers))
	c.set_player_names(names)
	if love:
		c.set_mode(SimConstants.MODE_LOVE)
	c.set_autosave_path(PATH)
	add_child_autofree(c)
	if c.get_state().phase == SimConstants.PHASE_SHOP:
		assert_true(c.quick_start())
	_play_out(c)
	return c


func _play_out(c: BattleController) -> void:
	var n: int = 0
	while c._playing and n < 900:
		c._process(1.0 / 30.0)
		n += 1


func _banner(c: BattleController) -> BigTurnBanner:
	return c.get_hud().get_big_banner()


## Steps the banner's own animation (the engine's frames are too fast and too slow to rely on).
func _pump(b: BigTurnBanner, seconds: float) -> void:
	var t: float = 0.0
	while t < seconds:
		b.advance(1.0 / 30.0)
		t += 1.0 / 30.0


# --- when it shows ---------------------------------------------------------------------

func test_two_humans_get_the_banner_with_their_name_in_their_colour() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(["ANNA", "BOB"]))
	var b: BigTurnBanner = _banner(c)
	assert_true(b.is_showing(), "the first turn is announced")
	assert_eq(b.get_text(), "ANNA'S TURN")
	assert_eq(b.get_label().get_theme_color("font_color"), PlayerLooks.color(0), "in the player's colour")
	assert_eq(c.fire_current(), "", "fire")
	_play_out(c)
	assert_eq(c.get_state().current_tank, 1)
	assert_true(b.is_showing(), "the next human's turn is announced too")
	assert_eq(b.get_text(), "BOB'S TURN")
	assert_eq(b.get_label().get_theme_color("font_color"), PlayerLooks.color(1))


func test_unnamed_players_are_called_player_n() -> void:
	var c: BattleController = _battle([H, H])
	assert_eq(_banner(c).get_text(), "PLAYER 1'S TURN")


func test_a_single_human_never_sees_it() -> void:
	var c: BattleController = _battle([H, NORMAL])
	assert_false(_banner(c).is_showing())
	assert_false(_banner(c).visible)


func test_a_single_human_among_three_tanks_never_sees_it() -> void:
	var c: BattleController = _battle([H, NORMAL, NORMAL])
	assert_false(_banner(c).is_showing())


func test_cpu_turns_do_not_show_it() -> void:
	# Two humans and a CPU: the banner shows for the humans and is gone when the CPU plays.
	var c: BattleController = _battle([H, H, NORMAL])
	var b: BigTurnBanner = _banner(c)
	assert_true(b.is_showing())
	c.fire_current()
	_play_out(c)  # human 2
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(b.get_player(), 1)
	c.fire_current()
	_play_out(c)  # now the CPU's turn
	assert_eq(c.get_state().current_tank, 2)
	assert_true(c.is_busy(), "the CPU turn locks the input")
	assert_false(b.is_showing(), "no banner on a CPU's turn")
	assert_ne(b.get_player(), 2)


func test_three_humans_cycle_through_their_names() -> void:
	var c: BattleController = _battle([H, H, H], PackedStringArray(["A", "B", "C"]))
	var seen: PackedStringArray = PackedStringArray()
	for i: int in range(3):
		seen.append(_banner(c).get_text())
		c.fire_current()
		_play_out(c)
	assert_eq(seen, PackedStringArray(["A'S TURN", "B'S TURN", "C'S TURN"]))


func test_not_in_instant_mode() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(), false, true)
	assert_false(_banner(c).is_showing(), "instant timelines (tests, replays) stay quiet")


func test_not_after_a_restore() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(["ANNA", "BOB"]))
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_false(_banner(r).is_showing(), "a restored match opens straight on the turn")
	assert_eq(r.get_state().current_tank, 0)
	# ... and the next turn after it is announced as usual.
	r.fire_current()
	_play_out(r)
	assert_true(_banner(r).is_showing())
	assert_eq(_banner(r).get_text(), "BOB'S TURN", "names came back with the save")


func test_the_same_turn_is_not_announced_twice() -> void:
	var c: BattleController = _battle([H, H])
	var b: BigTurnBanner = _banner(c)
	_pump(b, 2.0)
	assert_false(b.is_showing(), "it fades out by itself")
	c._begin_turn_ui()
	assert_false(b.is_showing(), "re-entering the same turn does not show it again")


func test_love_mode_with_two_humans_uses_the_love_style() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(), true)
	var b: BigTurnBanner = _banner(c)
	assert_true(b.is_showing())
	assert_true(b.is_love())
	assert_true(b.has_hearts(), "hearts beside the text")


func test_standard_banner_has_no_hearts() -> void:
	var c: BattleController = _battle([H, H])
	assert_false(_banner(c).has_hearts())


# --- how it behaves --------------------------------------------------------------------

func test_it_fades_in_and_out_in_about_a_second_and_a_bit() -> void:
	var c: BattleController = _battle([H, H])
	var b: BigTurnBanner = _banner(c)
	assert_almost_eq(BigTurnBanner.IN_SECONDS + BigTurnBanner.HOLD_SECONDS + BigTurnBanner.OUT_SECONDS, 1.2, 0.001)
	assert_true(b.is_showing())
	_pump(b, 0.5)
	assert_gt(b.modulate.a, 0.95, "fully in during the hold")
	_pump(b, 1.0)
	assert_false(b.is_showing())
	assert_false(b.visible)


func test_it_never_blocks_input() -> void:
	var c: BattleController = _battle([H, H])
	var b: BigTurnBanner = _banner(c)
	assert_true(b.is_showing())
	var all: Array[Node] = b.find_children("*", "Control", true, false)
	all.append(b)
	for n: Node in all:
		assert_eq((n as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s ignores the mouse" % n.name)
	assert_false(c.is_busy(), "the controller is not locked while it shows")
	assert_false(c.get_hud().is_controls_locked())
	c.set_aim(1100, 55)
	assert_eq(c.get_aim(0), Vector2i(1100, 55), "aiming works while it shows")
	assert_true(b.is_showing(), "and does not dismiss it")
	assert_eq(c.fire_current(), "", "so does firing")


func test_reduce_motion_means_no_scaling_and_a_quick_fade() -> void:
	ShowSettings.reduce_motion = true
	var c: BattleController = _battle([H, H])
	var b: BigTurnBanner = _banner(c)
	assert_true(b.is_showing())
	var row: Control = b.get_node("Row") as Control
	for i: int in range(6):
		b.advance(0.03)
		assert_eq(row.scale, Vector2.ONE, "no scaling")
	_pump(b, 0.6)
	assert_true(b.is_showing(), "still holding")
	_pump(b, 0.6)
	assert_false(b.is_showing(), "gone sooner than the normal 1.2 s")
	assert_lt(BigTurnBanner.CALM_IN_SECONDS + BigTurnBanner.CALM_HOLD_SECONDS + BigTurnBanner.CALM_OUT_SECONDS, BigTurnBanner.SHOW_SECONDS)


func test_normal_motion_pops_in() -> void:
	var c: BattleController = _battle([H, H])
	var row: Control = _banner(c).get_node("Row") as Control
	assert_lt(row.scale.x, 1.0, "starts a little small")
	_pump(_banner(c), 0.4)
	assert_almost_eq(row.scale.x, 1.0, 0.01)


func test_long_names_fit_the_screen_at_phone_and_tablet_sizes() -> void:
	var name12: String = "WWWWWWWWWWWW"
	for case: Array in [[Vector2(2340, 1080), 535.0], [Vector2(2340, 1080), 500.0], [Vector2(2048, 1536), 264.0], [Vector2(1280, 720), 240.0]]:
		UiScale.dpi_override = case[1] as float
		UiScale.window_px_override = case[0] as Vector2
		var vis: Vector2 = UiScale.visible_size(case[0] as Vector2)
		var vp := SubViewport.new()
		vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
		vp.disable_3d = true
		add_child_autofree(vp)
		var hud := BattleHud.new()
		vp.add_child(hud)
		await wait_process_frames(2)
		for love: bool in [false, true]:
			hud.set_love_mode(love)
			hud.show_big_turn(0, name12)
			await wait_process_frames(2)
			var label: Label = hud.get_big_banner().get_label()
			var rect: Rect2 = label.get_global_rect()
			var bounds := Rect2(Vector2.ZERO, vis)
			assert_true(bounds.encloses(rect), "%s love=%s: banner text %s inside %s" % [str(case), love, rect, vis])
			var font: Font = label.get_theme_font("font")
			var w: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x
			assert_lt(w, vis.x * 0.95, "%s: text width %.0f of %.0f" % [str(case), w, vis.x])
		UiScale.reset_overrides()
		vp.queue_free()
		await wait_process_frames(1)


# --- name tags and the autosave --------------------------------------------------------

func test_named_players_get_a_tag_and_cpus_never() -> void:
	var c: BattleController = _battle([H, NORMAL], PackedStringArray(["ANNA", "SNEAKY"]))
	assert_eq(c.get_tank_view(0).get_name_tag(), "ANNA")
	assert_eq(c.get_tank_view(1).get_name_tag(), "", "a CPU has no name tag")


func test_unnamed_players_have_no_tag() -> void:
	var c: BattleController = _battle([H, H])
	assert_eq(c.get_tank_view(0).get_name_tag(), "")


func test_names_are_saved_in_the_autosave_meta_and_come_back() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(["ANNA", ""]))
	assert_true(c.autosave_now())
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_true(res["ok"] as bool)
	assert_eq((res["meta"] as Dictionary).get("names"), ["ANNA", ""])
	PlayerNames.reset()
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_eq(PlayerNames.label(0), "ANNA")
	assert_eq(PlayerNames.label(1), "PLAYER 2")
	assert_eq(r.get_tank_view(0).get_name_tag(), "ANNA")


func test_an_old_save_without_names_falls_back_to_player_n() -> void:
	var c: BattleController = _battle([H, H], PackedStringArray(["ANNA", "BOB"]))
	var meta: Dictionary = c._make_meta()
	meta.erase("names")
	assert_true(SaveStore.save(c.get_state(), c.get_session().actions, PATH, meta))
	PlayerNames.set_names(PackedStringArray(["STALE", "STALE"]))
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_eq(PlayerNames.label(0), "PLAYER 1", "stale names from before are dropped")
	assert_eq(r.get_tank_view(1).get_name_tag(), "")


func test_a_damaged_names_entry_in_a_save_is_ignored() -> void:
	var c: BattleController = _battle([H, H])
	var meta: Dictionary = c._make_meta()
	meta["names"] = ["FUCK", 7, null, "OK" + String.chr(0x1F600) + "NAME"]
	assert_true(SaveStore.save(c.get_state(), c.get_session().actions, PATH, meta))
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_eq(PlayerNames.label(0), "PLAYER 1", "a blocked name is dropped")
	assert_eq(PlayerNames.label(1), "PLAYER 2", "a number is not a name")
