extends GutTest
## Vibration (docs/ARCHITECTURE.md section 33a): the event -> pattern mapper and the player's rules (setting,
## focus, rate limit, priority, patterns). No device is involved: the player's sink and clock are fakes.

var _calls: Array[Vector2] = []  # (duration_ms, amplitude)
var _now: int = 100000
var _hp: HapticPlayer = null


func before_each() -> void:
	ShowSettings.reset()
	_calls.clear()
	_now = 100000
	_hp = HapticPlayer.new()
	_hp.sink = func(ms: int, amp: float) -> void: _calls.append(Vector2(ms, amp))
	_hp.clock = func() -> int: return _now
	add_child_autofree(_hp)


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


func _fire(weapon: String = "spark_dart") -> Dictionary:
	return {"type": "fire", "tank": 0, "weapon": weapon}


func _boom(radius: int) -> Dictionary:
	return {"type": "explosion", "x": 100, "y": 100, "radius": radius}


# --- mapper ---------------------------------------------------------------------------------------

func test_firing_is_a_light_pulse_of_15_to_30_ms() -> void:
	for key: String in ["fire_light", "fire_medium", "fire_heavy", "beam_zap"]:
		var pat: Dictionary = HapticMapper.for_sound(key)
		assert_false(pat.is_empty(), key)
		var pulses: Array = pat["pulses"]
		assert_eq(pulses.size(), 1, key + " is a single tick")
		var p: Vector3 = pulses[0]
		assert_between(int(p.y), 15, 30, key + " duration")
		assert_lt(p.z, 0.6, key + " is gentle")
	assert_false(HapticMapper.for_event(_fire("spark_dart")).is_empty())


func test_impacts_grow_with_the_explosion_size() -> void:
	var small: Dictionary = HapticMapper.for_event(_boom(14))
	var medium: Dictionary = HapticMapper.for_event(_boom(40))
	var large: Dictionary = HapticMapper.for_event(_boom(90))
	var nuke: Dictionary = HapticMapper.for_event(_boom(160))
	for pat: Dictionary in [small, medium, large, nuke]:
		assert_false(pat.is_empty())
	var on: Array[int] = [HapticMapper.on_time_ms(small), HapticMapper.on_time_ms(medium),
		HapticMapper.on_time_ms(large), HapticMapper.on_time_ms(nuke)]
	for i: int in range(3):
		assert_gt(on[i + 1], on[i], "small < medium < large < nuke vibrating time: %s" % str(on))
	assert_lt(int(small["pri"]), int(medium["pri"]))
	assert_lt(int(medium["pri"]), int(large["pri"]))
	assert_lt(int(large["pri"]), int(nuke["pri"]))


func test_nuke_and_tank_destroyed_are_a_heavy_rumble() -> void:
	for pat: Dictionary in [HapticMapper.for_event(_boom(160)), HapticMapper.for_event({"type": "tank_destroyed", "tank": 1})]:
		assert_eq(int(pat["pri"]), HapticMapper.PRI_RUMBLE)
		assert_gte((pat["pulses"] as Array).size(), 4, "chained pulses")
		assert_gte(HapticMapper.length_ms(pat), 400, "a rumble lasts about half a second")
		assert_gte(HapticMapper.on_time_ms(pat), 300)
		var first: Vector3 = (pat["pulses"] as Array)[0]
		assert_almost_eq(first.z, 1.0, 0.001, "starts at full strength")
	var fire: Dictionary = HapticMapper.for_sound("fire_heavy")
	assert_gt(HapticMapper.on_time_ms(HapticMapper.for_sound("explosion_nuke")), HapticMapper.on_time_ms(fire) * 8)


func test_every_audio_director_sound_has_a_haptic_decision() -> void:
	for key: Variant in AudioDirector.SOUNDS.keys():
		var k: String = str(key)
		var in_map: bool = HapticMapper.PATTERNS.has(k)
		var silent: bool = HapticMapper.NO_VIBRATION.has(k)
		assert_true(in_map != silent, "'%s' must be in PATTERNS or NO_VIBRATION, not both or neither" % k)
	for k: String in HapticMapper.PATTERNS.keys():
		assert_true(AudioDirector.SOUNDS.has(k), "pattern for unknown sound " + k)
	for k: String in HapticMapper.NO_VIBRATION:
		assert_true(AudioDirector.SOUNDS.has(k), "silent entry for unknown sound " + k)


func test_patterns_are_well_formed() -> void:
	for k: String in HapticMapper.PATTERNS.keys():
		var pat: Dictionary = HapticMapper.PATTERNS[k]
		assert_between(int(pat["pri"]), 1, 5, k)
		var last_start: int = -1
		for p: Vector3 in (pat["pulses"] as Array):
			assert_gt(int(p.y), 0, k + " duration")
			assert_between(p.z, 0.05, 1.0, k + " amplitude")
			assert_gt(int(p.x), last_start, k + " pulses are in order")
			last_start = int(p.x)


func test_love_edition_has_no_rumble_and_only_the_win_beats() -> void:
	for e: Dictionary in [_boom(160), _boom(40), {"type": "tank_destroyed", "tank": 0}, _fire("heart"),
			{"type": "heart_burst", "x": 5, "y": 5, "radius": 30}, {"type": "love", "tank": 1, "amount": 10}]:
		assert_true(HapticMapper.for_event(e, false, true).is_empty(), "no vibration for %s in Love" % str(e.get("type")))
	var win: Dictionary = HapticMapper.for_event({"type": "round_end", "winner": 0}, true, true)
	assert_false(win.is_empty(), "the Love win has a heartbeat")
	var pulses: Array = win["pulses"]
	assert_gte(pulses.size(), 2, "a double beat")
	for p: Vector3 in pulses:
		assert_lt(int(p.y), 70, "soft")
		assert_lt(p.z, 0.5, "gentle")
	assert_true(HapticMapper.for_event({"type": "round_end", "winner": 0}, true, false).is_empty(), "the standard win does not vibrate")
	assert_true(HapticMapper.for_event({"type": "round_end", "winner": -1}, true, true).is_empty(), "no winner, no heartbeat")


func test_events_that_make_no_vibrating_sound_are_silent() -> void:
	for e: Dictionary in [{"type": "terrain_add"}, {"type": "money", "reason": "kill", "delta": 100}, {"type": "turn"},
			{"type": "wind"}, {"type": "projectile"}, {"type": "chute", "tank": 0}, {"type": "flames"}]:
		assert_true(HapticMapper.for_event(e).is_empty(), str(e.get("type")))


# --- player ---------------------------------------------------------------------------------------

func test_a_shot_pulses_once_immediately() -> void:
	assert_true(_hp.on_event(_fire("spark_dart")))
	assert_eq(_calls.size(), 1)
	assert_between(int(_calls[0].x), 15, 30)
	assert_between(_calls[0].y, 0.0, 1.0)


func test_the_setting_switches_everything_off() -> void:
	ShowSettings.haptics = false
	assert_false(_hp.on_event(_boom(160)))
	assert_false(_hp.play_key("fire_heavy"))
	assert_eq(_calls.size(), 0)
	assert_eq(int(_hp.stats["started"]), 0)
	ShowSettings.haptics = true
	assert_true(_hp.on_event(_boom(160)))
	assert_gt(_calls.size(), 0)


func test_nothing_vibrates_while_the_app_is_not_focused() -> void:
	_hp.set_focused(false)
	assert_false(_hp.on_event(_boom(160)))
	assert_false(_hp.on_event(_fire()))
	assert_eq(_calls.size(), 0)
	_hp.set_focused(true)
	assert_true(_hp.on_event(_fire()))
	assert_eq(_calls.size(), 1)


func test_losing_focus_cancels_the_rest_of_a_rumble() -> void:
	assert_true(_hp.on_event(_boom(160)))
	assert_eq(_calls.size(), 1, "the first pulse fires at once")
	assert_true(_hp.is_busy())
	_hp.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(_hp.focused)
	_now += 1000
	_hp.pump()
	assert_eq(_calls.size(), 1, "the pending pulses were dropped")
	_hp.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(_hp.focused)
	_hp.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_false(_hp.focused)


func test_a_rumble_chains_its_pulses_over_time() -> void:
	assert_true(_hp.on_event({"type": "tank_destroyed", "tank": 0}))
	var pat: Dictionary = HapticMapper.for_sound("tank_destroyed")
	var total: int = (pat["pulses"] as Array).size()
	assert_eq(_calls.size(), 1)
	_now += 200
	_hp.pump()
	assert_gt(_calls.size(), 1, "later pulses follow on the clock")
	_now += 1000
	_hp.pump()
	assert_eq(_calls.size(), total)
	assert_false(_hp.is_busy())
	assert_gt(_calls[0].x, _calls[total - 1].x, "decaying: the last pulse is shorter than the first")
	assert_gt(_calls[0].y, _calls[total - 1].y, "and weaker")


func test_the_love_heartbeat_is_two_soft_beats() -> void:
	assert_true(_hp.on_event({"type": "round_end", "winner": 0}, true, true))
	_now += 2000
	_hp.pump()
	assert_eq(_calls.size(), 4, "lub-dub twice")
	for c: Vector2 in _calls:
		assert_lt(c.y, 0.5)


func test_a_multi_warhead_volley_does_not_buzz() -> void:
	# Eight small blasts 60 ms apart: only a couple may vibrate.
	var started: int = 0
	for i: int in range(8):
		if _hp.on_event(_boom(14)):
			started += 1
		_now += 60
		_hp.pump()
	assert_gte(started, 1)
	assert_lte(started, 3, "rate-limited (started %d of 8)" % started)
	assert_lte(_calls.size(), 3)


func test_the_budget_caps_vibration_per_second() -> void:
	var on_ms: int = 0
	for i: int in range(40):  # a long barrage of medium blasts, 100 ms apart
		_hp.on_event(_boom(40))
		_now += 100
		_hp.pump()
	for c: Vector2 in _calls:
		on_ms += int(c.x)
	assert_lte(on_ms, HapticPlayer.BUDGET_MS * 4 + 100, "about the budget per second over 4 s (%d ms)" % on_ms)
	assert_gt(on_ms, 0)


func test_a_stronger_pattern_replaces_a_weaker_one() -> void:
	assert_true(_hp.on_event(_boom(14)))
	_now += 10
	assert_true(_hp.on_event(_boom(160)), "a nuke cuts a small tick short")
	assert_eq(_calls.size(), 2)
	_now += 20
	assert_false(_hp.on_event(_boom(14)), "a weaker pattern is ignored while the rumble runs")
	assert_false(_hp.on_event(_fire()))


func test_a_nuke_ignores_the_budget_but_not_the_priority_rule() -> void:
	for i: int in range(3):
		_hp.on_event(_boom(40))
		_now += 200
	assert_true(_hp.on_event(_boom(160)), "rare, so it always plays")
	_now += 5
	assert_false(_hp.on_event({"type": "tank_destroyed", "tank": 0}), "an equal rumble waits for the first")
	_now += 2000
	_hp.pump()
	assert_true(_hp.on_event({"type": "tank_destroyed", "tank": 0}))


func test_the_default_sink_is_the_phone_and_a_missing_clock_is_fine() -> void:
	var plain := HapticPlayer.new()
	add_child_autofree(plain)
	# No sink: it calls Input.vibrate_handheld, which does nothing on desktop and headless.
	assert_true(plain.on_event(_fire()))
	assert_eq(int(plain.stats["pulses"]), 1)
	assert_true(ClassDB.class_has_method("Input", "vibrate_handheld"))


func test_the_battle_controller_feeds_the_player_from_the_timeline() -> void:
	ShowSettings.haptics = true
	var c: BattleController = (load("res://show/battle/battle_scene.tscn") as PackedScene).instantiate()
	c.configure(3, 20260101, false)
	add_child_autofree(c)
	c.quick_start()
	await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	var hp: HapticPlayer = c.get("_haptics") as HapticPlayer
	assert_not_null(hp, "the controller owns a HapticPlayer")
	if hp == null:
		return
	var got: Array[Vector2] = []
	hp.sink = func(ms: int, amp: float) -> void: got.append(Vector2(ms, amp))
	hp.clock = func() -> int: return _now
	_now += 100000
	c.call("_dispatch", {"type": "explosion", "tick": 0, "x": 400, "y": 300, "radius": 90, "weapon": "nova_core"})
	assert_gt(got.size(), 0, "an explosion event vibrates")
	ShowSettings.haptics = false
	got.clear()
	_now += 100000
	c.call("_dispatch", {"type": "explosion", "tick": 0, "x": 400, "y": 300, "radius": 160, "weapon": "supernova"})
	assert_eq(got.size(), 0, "the setting is respected")
