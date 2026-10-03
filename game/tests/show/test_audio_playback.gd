extends GutTest
## The battle controller feeds every played timeline event to the AudioDirector (one call per event), stays
## silent in instant mode, and hands the loops back when the battle goes away.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 777

var _ad: Node = null


func before_each() -> void:
	_ad = get_tree().root.get_node("AudioDirector")
	_ad.reset_for_tests()
	ShowSettings.reset()


func after_each() -> void:
	_ad.reset_for_tests()
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


func _battle(instant: bool) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant)
	add_child_autofree(c)
	c.quick_start()
	if not instant:
		await wait_until(func() -> bool: return not c.is_busy(), 10.0, 0.1)
	return c


func test_a_played_event_reaches_the_audio_director() -> void:
	var c: BattleController = await _battle(false)
	_ad.reset_for_tests()
	_ad.record_log = true
	c.call("_dispatch", {"type": "explosion", "tick": 0, "x": 400, "y": 300, "radius": 90, "weapon": "nova_core"})
	assert_eq(_ad.played_log, ["explosion_large"] as Array[String])


func test_instant_mode_is_silent() -> void:
	var c: BattleController = await _battle(true)
	_ad.reset_for_tests()
	_ad.record_log = true
	c.call("_dispatch", {"type": "explosion", "tick": 0, "x": 400, "y": 300, "radius": 90, "weapon": "nova_core"})
	c.call("_dispatch", {"type": "well_on", "tick": 0, "owner": 0, "x": 400, "y": 300, "expires_turn": 9})
	assert_eq(_ad.played_log.size(), 0)
	assert_false(_ad.is_hum_playing())
	c.fire_current()
	assert_eq(_ad.played_log.size(), 0, "a whole instant timeline makes no sound")


func test_a_real_shot_plays_fire_then_explosion_then_the_turn_blip() -> void:
	var c: BattleController = await _battle(false)
	c.set_speed(6.0)
	_ad.reset_for_tests()
	_ad.record_log = true
	assert_eq(c.fire_current(), "")
	await wait_until(func() -> bool: return not c.is_busy(), 15.0, 0.1)
	var log: Array[String] = _ad.played_log
	assert_gt(log.size(), 2, "the shot made sound: %s" % [log])
	assert_eq(log[0], "fire_light", "the Spark Dart")
	assert_true(log.has("turn_blip"), "the turn changed")
	assert_lt(log.find("fire_light"), log.find("turn_blip"))


func test_refusals_make_the_locked_sound() -> void:
	var c: BattleController = await _battle(false)
	_ad.reset_for_tests()
	_ad.record_log = true
	assert_eq(c.select_weapon("nova_core"), "out_of_stock")
	assert_eq(_ad.played_log, ["ui_locked"] as Array[String])


func test_leaving_the_battle_silences_the_well_hum() -> void:
	var c: BattleController = await _battle(false)
	c.call("_dispatch", {"type": "well_on", "tick": 0, "owner": 1, "x": 400, "y": 300, "expires_turn": 9})
	assert_true(_ad.is_hum_playing())
	c.free()
	assert_false(_ad.is_hum_playing(), "the hum belongs to the battle that is gone")


func test_a_match_decided_by_the_timeline_plays_the_match_jingle() -> void:
	var c: BattleController = await _battle(false)
	_ad.reset_for_tests()
	_ad.record_log = true
	c.get_state().phase = SimConstants.PHASE_MATCH_OVER
	c.call("_dispatch", {"type": "round_end", "tick": 0, "winner": 0})
	assert_eq(_ad.played_log, ["match_win"] as Array[String])
