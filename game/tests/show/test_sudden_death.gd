extends GutTest
## Sudden death in the show layer (ARCHITECTURE sections 40 and 42): when the `sudden_death` event plays there is
## one big banner, one alarm and one strong haptic pulse; the drain damage pops up in its own colour with the word
## "drain"; a small tag stays while it is active and comes back after Continue (derived from turn_number).

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://test_sudden_autosave.crtl"
const SEED: int = 4242
const H: int = SimConstants.CTRL_HUMAN

var _ad: Node = null
var _buzz: Array[Vector2] = []
var _now: int = 0


func before_each() -> void:
	_ad = get_tree().root.get_node("AudioDirector")
	_ad.reset_for_tests()
	ShowSettings.reset()
	PlayerNames.reset()
	SaveStore.delete(PATH)
	_buzz.clear()
	_now = 0


func after_each() -> void:
	_ad.reset_for_tests()
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()
	SaveStore.delete(PATH)


func _battle(players: int = 2, instant: bool = false, love: bool = false, teams: Array = []) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant, players)
	var ctrl := PackedInt32Array()
	ctrl.resize(players)
	ctrl.fill(H)
	c.set_controllers(ctrl)
	if love:
		c.set_mode(SimConstants.MODE_LOVE)
	if not teams.is_empty():
		c.set_teams(PackedInt32Array(teams))
	c.set_autosave_path(PATH)
	add_child_autofree(c)
	if c.get_state().phase == SimConstants.PHASE_SHOP:
		assert_true(c.quick_start())
	var hp: HapticPlayer = c.get("_haptics") as HapticPlayer
	hp.sink = func(ms: int, amp: float) -> void: _buzz.append(Vector2(ms, amp))
	hp.clock = func() -> int: return _now
	_play_out(c)
	return c


func _play_out(c: BattleController) -> void:
	var n: int = 0
	while c._playing and n < 1500:
		_now += 33
		c._process(1.0 / 30.0)
		n += 1


## Passes `n` turns (each played out).
func _pass_turns(c: BattleController, n: int) -> void:
	for _i: int in range(n):
		assert_eq(c.pass_turn(), "")
		_play_out(c)


func _threshold(c: BattleController) -> int:
	return Simulation.sudden_death_turn(c.get_state().settings)


# --- mapping ---------------------------------------------------------------------------------------

func test_the_sudden_death_event_has_its_own_sound_and_haptic() -> void:
	var e: Dictionary = {"type": "sudden_death", "tick": 3}
	assert_eq(AudioDirector.sound_for_event(e), "sudden_death")
	assert_eq(AudioDirector.sound_for_event(e, false, true), "", "never in love")
	assert_true((AudioDirector.SOUNDS as Dictionary).has("sudden_death"))
	var pat: Dictionary = HapticMapper.for_event(e)
	assert_false(pat.is_empty())
	assert_eq(int(pat["pri"]), HapticMapper.PRI_RUMBLE, "a strong pulse that nothing cuts short")
	assert_gte((pat["pulses"] as Array).size(), 3)
	assert_gte(HapticMapper.on_time_ms(pat), 300)
	assert_true(HapticMapper.for_event(e, false, true).is_empty(), "no vibration in love")
	assert_false(HapticMapper.NO_VIBRATION.has("sudden_death"))


func test_the_alarm_is_a_real_loud_sample() -> void:
	var s: AudioStreamWAV = (AudioDirector.SOUNDS["sudden_death"] as Dictionary)["s"] as AudioStreamWAV
	assert_not_null(s)
	assert_gt(s.get_length(), 1.5, "a klaxon plus its tail, not a blip")
	assert_lt(s.get_length(), 3.6)
	assert_gte(int((AudioDirector.SOUNDS["sudden_death"] as Dictionary)["pri"]), 9, "it wins a full voice pool")


# --- the moment it starts ------------------------------------------------------------------------------

func test_banner_alarm_and_haptic_fire_once_when_sudden_death_starts() -> void:
	var c: BattleController = _battle()
	var thr: int = _threshold(c)
	_pass_turns(c, thr - 1)
	assert_eq(c.sudden_death_events, 0, "nothing before the threshold")
	assert_false(c.get_hud().get_sudden_banner().is_showing())
	assert_false(c.get_hud().get_sudden_tag().is_active())
	_ad.reset_for_tests()
	_ad.record_log = true
	_buzz.clear()
	assert_eq(c.pass_turn(), "")
	c.call("_process", 0.0)
	_play_out(c)
	assert_eq(c.sudden_death_events, 1)
	assert_eq(c.get_hud().get_sudden_banner().play_count(), 1, "one banner")
	assert_eq(_ad.played_log.count("sudden_death"), 1, "one alarm")
	assert_gte(_buzz.size(), 1, "the haptic pulse started")
	assert_eq(_buzz[0], Vector2(160, 1.0), "at full strength, at once")
	_pass_turns(c, 2)
	assert_eq(c.get_hud().get_sudden_banner().play_count(), 1, "it never plays again this round")
	assert_eq(c.sudden_death_events, 1)


func test_the_banner_is_big_red_and_never_takes_input() -> void:
	var c: BattleController = _battle()
	_pass_turns(c, _threshold(c))
	var b: SuddenDeathBanner = c.get_hud().get_sudden_banner()
	assert_true(b.is_showing())
	assert_eq(b.get_text(), "SUDDEN DEATH")
	assert_eq(b.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(b.get_band().mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(b.get_label().mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_gt(b.get_label().get_theme_font_size("font_size"), c.get_hud().get_turn_banner().get("_label").get_theme_font_size("font_size") as int, "bigger than the turn banner")
	var col: Color = b.get_label().get_theme_color("font_color")
	assert_gt(col.r, col.g, "red/amber, not blue")
	assert_gt(col.r, col.b)
	assert_false(c.is_busy(), "play continues: the banner does not block")
	# It fades out by itself.
	var t: float = 0.0
	while b.is_showing() and t < 6.0:
		b.advance(0.1)
		t += 0.1
	assert_false(b.is_showing())
	assert_lt(t, 3.0, "about two seconds")


func test_reduce_motion_makes_the_banner_calm() -> void:
	ShowSettings.reduce_motion = true
	var b := SuddenDeathBanner.new()
	add_child_autofree(b)
	b.play()
	assert_almost_eq(b.get_band().scale.x, 1.0, 0.001, "no pop-in scaling")
	var t: float = 0.0
	while b.is_showing() and t < 6.0:
		b.advance(0.05)
		t += 0.05
	assert_lt(t, 1.8, "a quicker fade")
	ShowSettings.reduce_motion = false
	ShowSettings.reduce_flashing = true
	b.play()
	assert_gt(b.get_band().scale.x, 1.0, "the pop-in is on again")
	b.advance(0.05)
	var a: float = b.get_label().get_theme_color("font_shadow_color").a
	b.advance(0.2)
	assert_almost_eq(b.get_label().get_theme_color("font_shadow_color").a, a, 0.001, "no glow pulse with reduced flashing")


func test_instant_mode_is_silent_but_keeps_the_tag() -> void:
	var c: BattleController = _battle(2, true)
	_pass_turns(c, _threshold(c))
	assert_eq(c.sudden_death_events, 1)
	assert_eq(c.get_hud().get_sudden_banner().play_count(), 0, "no banner in replays and tests")
	assert_true(c.get_hud().get_sudden_tag().is_active())


func test_love_mode_has_no_sudden_death() -> void:
	var c: BattleController = _battle(2, false, true)
	assert_false(c.sudden_death_active())
	c.get_hud().set_sudden_death_active(true, 5)
	assert_false(c.get_hud().get_sudden_tag().is_active())


# --- the drain pop-up -------------------------------------------------------------------------------------------

func test_drain_damage_pops_up_in_its_own_colour_with_a_word() -> void:
	var c: BattleController = _battle()
	_pass_turns(c, _threshold(c))
	var found: Array[DamagePopup] = []
	for p: DamagePopup in c.get("_popups") as Array[DamagePopup]:
		if p.visible and p.text.contains("drain"):
			found.append(p)
	assert_eq(found.size(), 2, "both living tanks lose HP: %d popups" % found.size())
	assert_eq(found[0].text, "-5 drain", "the first drain is 5 HP")
	assert_eq(found[0].get_theme_color("font_color"), NeonPalette.BAD)
	for t: TankState in c.get_state().tanks:
		assert_eq(t.health, SimConstants.MAX_HEALTH - 5)


# --- the persistent tag --------------------------------------------------------------------------------------------------

func test_the_tag_shows_while_active_with_the_next_drain() -> void:
	var c: BattleController = _battle()
	var thr: int = _threshold(c)
	_pass_turns(c, thr - 1)
	assert_false(c.get_hud().get_sudden_tag().is_active())
	_pass_turns(c, 1)
	var tag: SuddenDeathIndicator = c.get_hud().get_sudden_tag()
	assert_true(tag.is_active())
	assert_true(tag.get_text().begins_with("SUDDEN DEATH"))
	assert_eq(tag.get_next_drain(), 10, "5 were taken, 10 is next")
	assert_string_contains(tag.get_text(), "-10 HP")
	_pass_turns(c, 2)
	assert_eq(c.get_hud().get_sudden_tag().get_next_drain(), 15)
	assert_true(c.sudden_death_active())


func test_the_tag_is_restored_after_continue() -> void:
	var c: BattleController = _battle()
	_pass_turns(c, _threshold(c) + 1)
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = false
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_true(r.get_state().turn_number >= _threshold(r))
	assert_true(r.sudden_death_active(), "derived from turn_number and the threshold")
	var tag: SuddenDeathIndicator = r.get_hud().get_sudden_tag()
	assert_true(tag.is_active())
	assert_eq(tag.get_next_drain(), Simulation.sudden_death_amount(r.get_state().sudden_death_cycles + 1))
	assert_false(r.get_hud().get_sudden_banner().is_showing(), "the call-out is for the moment it starts, not for Continue")
	assert_eq(r.sudden_death_events, 0)


func test_a_restore_before_the_threshold_has_no_tag() -> void:
	var c: BattleController = _battle()
	_pass_turns(c, _threshold(c) - 2)
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(r)
	assert_false(r.get_hud().get_sudden_tag().is_active())


func test_the_tag_goes_when_the_round_ends_and_a_new_round_starts_clean() -> void:
	var c: BattleController = _battle(2, true)
	_pass_turns(c, _threshold(c))
	assert_true(c.get_hud().get_sudden_tag().is_active())
	# Both tanks are one drain away from death: the next drain ends the round in a draw.
	for t: TankState in c.get_state().tanks:
		t.health = 5
	c.call("_rebuild_display")
	_pass_turns(c, 2)
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)
	assert_false(c.get_hud().get_sudden_tag().is_active(), "the summary hides it")
	assert_eq(c.get_round_overlay().get_title_text(), "DRAW", "no survivors: a draw")
	assert_true(c.quick_start())
	assert_false(c.get_hud().get_sudden_tag().is_active(), "round two starts without it")
	assert_false(c.sudden_death_active())


func test_a_team_draw_by_the_drain_says_no_survivors() -> void:
	var c: BattleController = _battle(2, true, false, [0, 1])
	_pass_turns(c, _threshold(c) - 1)
	for t: TankState in c.get_state().tanks:
		t.health = 5
	c.call("_rebuild_display")
	_pass_turns(c, 1)
	assert_eq(c.get_state().phase, SimConstants.PHASE_SHOP)
	assert_eq(c.get_round_overlay().get_title_text(), "DRAW — NO SURVIVORS")


func test_the_tag_fits_a_narrow_phone_under_the_banner() -> void:
	UiScale.dpi_override = 535.0
	UiScale.window_px_override = Vector2(2340, 1080)
	var vis: Vector2 = UiScale.visible_size(Vector2(2340, 1080))
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	var hud: BattleHud = BattleHud.new()
	vp.add_child(hud)
	hud.set_sudden_death_active(true, 25)
	hud.show_sudden_death()
	await wait_process_frames(3)
	var tag: Rect2 = hud.get_sudden_tag().get_global_rect()
	var bounds := Rect2(Vector2.ZERO, vis).grow(1.5)
	assert_true(bounds.encloses(tag), "tag %s inside %s" % [tag, vis])
	assert_false(tag.intersects(hud.get_turn_banner().get_global_rect().grow(-1.0)), "it does not cover the turn banner")
	var band: Rect2 = hud.get_sudden_banner().get_band().get_global_rect()
	assert_true(bounds.encloses(band), "banner band %s inside %s" % [band, vis])
	assert_lte(hud.get_sudden_banner().get_label().get_minimum_size().x, vis.x, "the text fits the width")
