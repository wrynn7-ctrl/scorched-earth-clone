@warning_ignore_start("integer_division")
extends GutTest
## Mound Mortar / Landslide (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _air_cells_in_circle(t: Terrain, cx: int, cy: int, r: int) -> int:
	var c: Terrain = t.duplicate_terrain()
	var before: int = WU.solid_count(c)
	c.add_circle(cx, cy, r, 1)
	return WU.solid_count(c) - before


func test_mound_adds_exactly_the_air_cells_of_the_circle() -> void:
	var s: MatchState = U.flat_state(2)
	var p: int = WU.power_for_landing(s, 450, 900)
	var before: Terrain = s.terrain.duplicate_terrain()
	var solid_before: int = WU.solid_count(before)
	var ev: Array[Dictionary] = WU.fire(s, "mound_mortar", 450, p)
	var add: Array[Dictionary] = U.find(ev, "terrain_add")
	assert_eq(add.size(), 1)
	var a: Dictionary = add[0]
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq([a["x"], a["y"], a["radius"]], [end["x"], end["y"], 40])
	assert_eq(a["tick"], end["tick"])
	assert_eq(a["material"], 1, "the surface material of the impact column")
	assert_eq((a["skip"] as PackedInt32Array).size(), 0, "no tank near")
	var expect: int = _air_cells_in_circle(before, a["x"], a["y"], 40)
	assert_gt(expect, 1000)
	assert_eq(WU.solid_count(s.terrain) - solid_before, expect)
	assert_lt(s.terrain.surface_y(end["x"]), U.GROUND_Y - 30, "a mound now stands there")
	assert_eq(U.find(ev, "explosion").size(), 0, "dirt weapons do not explode")
	assert_eq(U.find(ev, "damage").size(), 0)


func test_event_order_add_then_settle() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "mound_mortar", 450, WU.power_for_landing(s, 450, 900))
	var types: Array[String] = U.types(ev)
	assert_eq(types, ["fire", "projectile", "projectile_end", "terrain_add", "terrain_settle", "wind", "turn"] as Array[String])
	var st: Dictionary = U.find(ev, "terrain_settle")[0]
	var a: Dictionary = U.find(ev, "terrain_add")[0]
	assert_eq(st["x0"], (a["x"] as int) - 40)
	assert_eq(st["x1"], (a["x"] as int) + 40)


func test_landslide_is_bigger() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "landslide", 450, WU.power_for_landing(s, 450, 900))
	var a: Dictionary = U.find(ev, "terrain_add")[0]
	assert_eq(a["radius"], 80)
	assert_eq(s.tanks[0].stock_of("landslide"), 0)


func test_cells_are_never_added_inside_a_tank_box() -> void:
	var s: MatchState = U.flat_state(2)
	var p: int = WU.power_for_landing(s, 450, 900)
	WU.place_tank(s, 1, 920)  # the box overlaps the circle but is not on the shell's way
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "terrain")
	var before: Terrain = s.terrain.duplicate_terrain()
	var ev: Array[Dictionary] = WU.fire(s, "mound_mortar", 450, p)
	var a: Dictionary = U.find(ev, "terrain_add")[0]
	var skip: PackedInt32Array = a["skip"]
	assert_eq(skip, PackedInt32Array([908, U.GROUND_Y - 12, 932, U.GROUND_Y]), "the box of tank 1, half-open")
	# Only the add event (before any settle): the box stays empty.
	var added: Terrain = before.duplicate_terrain()
	added.add_circle_skipping(a["x"], a["y"], a["radius"], a["material"], skip)
	assert_eq(WU.solid_in_box(added, s.tanks[1]), 0)
	var plain: Terrain = before.duplicate_terrain()
	plain.add_circle(a["x"], a["y"], a["radius"], a["material"])
	assert_gt(WU.solid_in_box(plain, s.tanks[1]), 0, "a plain add_circle would have buried it")
	assert_eq(U.find(ev, "damage").size(), 0)


func test_skip_boxes_lists_only_alive_overlapping_tanks() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].x = 300
	s.tanks[1].x = 340
	s.tanks[2].x = 900
	var boxes: PackedInt32Array = DirtBehavior.skip_boxes(s, 320, U.GROUND_Y, 40)
	assert_eq(boxes.size(), 8, "tanks 0 and 1")
	assert_eq(boxes[0], 288)
	assert_eq(boxes[4], 328)
	s.tanks[1].alive = false
	assert_eq(DirtBehavior.skip_boxes(s, 320, U.GROUND_Y, 40).size(), 4)
	assert_eq(DirtBehavior.skip_boxes(s, 1200, U.GROUND_Y, 40).size(), 0)


func test_a_tank_under_the_mound_is_buried_and_firing_from_inside_dirt_explodes_at_once() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "tank")
	var ev: Array[Dictionary] = WU.fire(s, "mound_mortar", 450, p)
	assert_gt((U.find(ev, "terrain_add")[0]["skip"] as PackedInt32Array).size(), 0)
	assert_gt(WU.solid_in_box(s.terrain, s.tanks[1]), 100, "dirt fell into the box while settling: buried")
	assert_eq(s.tanks[1].health, 100, "burying does no damage")
	assert_eq(s.current_tank, 1)
	# The buried tank fires: the shell starts inside dirt and bursts at the muzzle.
	var ev2: Array[Dictionary] = WU.fire(s, "pulse_missile", 450, 600)
	var end: Dictionary = U.find(ev2, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	assert_lte(end["tick"] as int, 1, "explodes immediately")
	var muzzle_x: int = 800 + (FixedMath.cos10(450) * SimConstants.BARREL_LEN >> 16)
	assert_true(absi((end["x"] as int) - muzzle_x) <= 16)
	assert_lt(s.tanks[1].health, 100, "its own blast hurts it")
	assert_gt(U.find(ev2, "damage").size(), 0)


func test_lost_shell_adds_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var before: PackedByteArray = s.terrain.cells.duplicate()
	var ev: Array[Dictionary] = WU.fire(s, "mound_mortar", 1750, 900)
	assert_eq(U.find(ev, "terrain_add").size(), 0)
	assert_eq(s.terrain.cells, before)
