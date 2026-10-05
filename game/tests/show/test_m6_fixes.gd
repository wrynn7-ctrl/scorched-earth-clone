extends GutTest
## M6 QA fixes (show layer): a wreck never shows a shield or repulsor, and the autosave meta is read defensively.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://test_m6_fixes_autosave.crtl"
const SEED: int = 777


func before_each() -> void:
	SaveStore.delete(PATH)


func after_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


func _view() -> TankView:
	var v: TankView = (load("res://show/tank_view.tscn") as PackedScene).instantiate()
	add_child_autofree(v)
	return v


func test_a_dead_tank_view_takes_no_shield_or_repulsor_in_either_order() -> void:
	var v: TankView = _view()
	v.set_shield(30, 30)
	v.set_repulsor(true)
	v.set_dead(true)
	assert_false(v.has_shield_bubble())
	assert_false(v.is_repulsor_on())
	v.set_shield(30, 30)  # the rebuild used to do this after set_dead
	v.set_repulsor(true)
	assert_false(v.has_shield_bubble(), "a wreck keeps no bubble")
	assert_false(v.is_repulsor_on())
	v.set_dead(false)
	v.set_shield(30, 30)
	assert_true(v.has_shield_bubble(), "a living tank still does")


func _battle() -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, true, 2)
	c.set_autosave_path(PATH)
	add_child_autofree(c)
	if c.get_state().phase == SimConstants.PHASE_SHOP:
		c.quick_start()
	return c


func test_a_dead_shielded_tank_is_consistent_and_rebuilds_without_a_bubble() -> void:
	var c: BattleController = _battle()
	var t: TankState = c.get_state().tanks[1]
	t.shield_type = Catalog.index_of("glow_shield")
	t.shield_hp = 30
	t.repulsor_charge = 50
	c.call("_rebuild_display")
	assert_true(c.get_tank_view(1).has_shield_bubble())
	t.alive = false  # as a drain or fall death leaves it: shield_hp stays
	t.health = 0
	c.get_tank_view(1).set_dead(true)
	c.get_tank_view(1).set_health(0, SimConstants.MAX_HEALTH)
	assert_true(c.check_consistency(), "a dead tank wants no shield")
	assert_eq(c.mismatch_count, 0)
	c.call("_rebuild_display")
	assert_false(c.get_tank_view(1).has_shield_bubble())
	assert_false(c.get_tank_view(1).is_repulsor_on())
	assert_true(c.check_consistency())
	assert_eq(c.mismatch_count, 0, "no snap on Continue either")


func test_wrong_typed_meta_values_are_ignored_when_continuing() -> void:
	var c: BattleController = _battle()
	assert_true(c.pass_turn() == "")
	var bad_metas: Array[Dictionary] = [
		{"looks": 5, "summary_pending": "yes", "round_money": "x", "cpu_buys": 3, "flowers": {}, "theme": 7, "names": 1},
		{"looks": [1, 2], "summary_pending": 1, "round_money": [{}, []], "cpu_buys": [{"tank": {}, "items": [[{}, []]]}], "flowers": [[{}, "a", []]]},
		{"looks": {"colors": 4, "emblems": "z"}, "summary_pending": null, "round_money": [1.5, "x"], "cpu_buys": [5, null, {"tank": 0, "items": 3}]},
	]
	for meta: Dictionary in bad_metas:
		assert_true(SaveStore.save(c.get_state(), [] as Array[Dictionary], PATH, meta))
		BattleConfig.autosave_path = PATH
		BattleConfig.resume = true
		BattleConfig.instant = true
		var r: BattleController = (load(BATTLE) as PackedScene).instantiate()
		add_child_autofree(r)
		assert_not_null(r.get_state(), "the match restores despite meta %s" % str(meta))
		assert_eq(Simulation.fingerprint(r.get_state()), Simulation.fingerprint(c.get_state()))
		assert_false(r.get("_summary_pending") as bool, "a non-bool summary flag is ignored")
