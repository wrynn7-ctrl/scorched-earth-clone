extends GutTest
## In a match, a Human tank on this device wears the skin assigned to its slot; CPUs and humans
## without an assignment keep the default look.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const DIR: String = "user://test_skins_battle"
const H: int = SimConstants.CTRL_HUMAN
const EASY: int = SimConstants.CTRL_EASY


func before_each() -> void:
	SkinStore.dir = DIR
	_wipe()


func after_each() -> void:
	_wipe()
	SkinStore.dir = SkinStore.DEFAULT_DIR
	BattleConfig.reset()
	PlayerLooks.reset()
	ShowSettings.reset()


func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _skin(id: String) -> SkinData:
	var s: SkinData = SkinData.make_default(id, id)
	s.pattern = SkinData.Pattern.CAMO
	return s


func _battle(controllers: Array) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, 4242, true, controllers.size())
	c.set_controllers(PackedInt32Array(controllers))
	add_child_autofree(c)
	return c


func test_only_human_slots_with_an_assignment_wear_a_skin() -> void:
	SkinStore.save_skin(_skin("mine"))
	SkinStore.save_skin(_skin("cpu_skin"))
	SkinStore.assign(0, "mine")       # human, assigned
	SkinStore.assign(1, "cpu_skin")   # a CPU slot: must be ignored
	# slot 2 is a human without an assignment, slot 3 a CPU without one
	var c: BattleController = _battle([H, EASY, H, EASY])
	assert_true(c.get_tank_view(0).has_skin(), "the human with a skin wears it")
	assert_eq(c.get_tank_view(0).get_skin().id, "mine")
	assert_false(c.get_tank_view(1).has_skin(), "a CPU never wears one")
	assert_false(c.get_tank_view(2).has_skin(), "a human without an assignment looks standard")
	assert_false(c.get_tank_view(3).has_skin())
	for i: int in range(4):
		assert_eq(c.get_tank_view(i).outline_color(), PlayerLooks.color(i), "tank %d keeps its identity colour" % i)


func test_the_skin_survives_a_restart_and_leaves_the_match_state_alone() -> void:
	SkinStore.save_skin(_skin("mine"))
	SkinStore.assign(1, "mine")
	var c: BattleController = _battle([H, H])
	assert_false(c.get_tank_view(0).has_skin())
	assert_true(c.get_tank_view(1).has_skin())
	c.restart_match()
	assert_true(c.get_tank_view(1).has_skin(), "a new match keeps the assignment")
	assert_false(c.get_tank_view(0).has_skin())
	# Skins are not part of what a save or the simulation knows.
	var meta: Dictionary = c.get_session().meta
	assert_false(JSON.stringify(meta).contains("mine"), "the autosave meta never mentions skins")


func test_a_missing_skin_file_falls_back_to_the_standard_look() -> void:
	SkinStore.save_skin(_skin("mine"))
	SkinStore.assign(0, "mine")
	DirAccess.remove_absolute(DIR + "/mine.json")
	var c: BattleController = _battle([H, EASY])
	assert_false(c.get_tank_view(0).has_skin())
