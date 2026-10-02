@warning_ignore_start("integer_division")
extends GutTest
## Ember Rain / Inferno Gel (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _valley() -> MatchState:
	var s: MatchState = WU.shaped_state(2, func(x: int) -> int: return clampi(820 - absi(x - 800), 250, 820))
	WU.place_tank(s, 0, 100)
	WU.place_tank(s, 1, 1500)
	return s


func _hit_tank_one(s: MatchState, weapon: String) -> Array[Dictionary]:
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "tank")
	return WU.fire(s, weapon, 450, p)


func test_flames_event_then_damage_and_nothing_else_changes() -> void:
	var s: MatchState = U.flat_state(2)
	var terrain_before: PackedByteArray = s.terrain.cells.duplicate()
	var ev: Array[Dictionary] = _hit_tank_one(s, "ember_rain")
	assert_eq(U.types(ev), ["fire", "projectile", "projectile_end", "flames", "damage", "money", "wind", "turn"] as Array[String])
	var fl: Dictionary = U.find(ev, "flames")[0]
	assert_eq((fl["points"] as PackedInt32Array).size(), 120, "60 flame points = 120 ints")
	assert_eq(fl["tick"], U.find(ev, "projectile_end")[0]["tick"])
	assert_eq(U.find(ev, "damage")[0]["tick"], fl["tick"], "damage at the impact tick")
	assert_eq(s.terrain.cells, terrain_before, "fire never changes the terrain")


func test_damage_is_capped_per_tank() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _hit_tank_one(s, "ember_rain")
	var d: Array[Dictionary] = U.find(ev, "damage")
	assert_eq(d.size(), 1, "one damage event per tank")
	assert_eq(d[0]["amount"], 40, "60 points x 2 = 120, capped at 40")
	assert_eq(d[0]["cause"], "burn")
	assert_eq(s.tanks[1].health, 60)
	var s2: MatchState = U.flat_state(2)
	var ev2: Array[Dictionary] = _hit_tank_one(s2, "inferno_gel")
	assert_eq(U.find(ev2, "damage")[0]["amount"], 70, "inferno cap 70 (110 x 3 = 330)")
	assert_eq(s2.tanks[1].health, 30)


func test_money_and_kills_go_to_the_shooter() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _hit_tank_one(s, "ember_rain")
	assert_eq(s.tanks[0].money, 15 * 40)
	assert_eq(s.tanks[0].damage_dealt, 40)
	assert_eq(U.find(ev, "money")[0]["reason"], "damage")
	var k: MatchState = U.flat_state(3)
	k.tanks[1].health = 20
	var ev2: Array[Dictionary] = _hit_tank_one(k, "ember_rain")
	assert_false(k.tanks[1].alive)
	assert_eq(k.tanks[0].kills, 1)
	assert_eq(k.tanks[0].money, 15 * 20 + 1500, "HP actually removed + kill bonus")
	assert_eq(U.find(ev2, "tank_destroyed").size(), 1)


func test_shields_absorb_burn_damage_first() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	var ev: Array[Dictionary] = WU.fire(s, "ember_rain", 450, p)
	var types: Array[String] = U.types(ev)
	assert_true(types.find("shield_hit") < types.find("damage"))
	assert_eq(U.find(ev, "shield_hit")[0]["absorbed"], 30)
	assert_eq(U.find(ev, "damage")[0]["amount"], 10, "40 - 30 absorbed")
	assert_eq(s.tanks[1].health, 90)


func test_no_damage_beyond_six_cells() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 830
	var p: int = WU.power_for_landing(s, 450, 800)
	var ev: Array[Dictionary] = WU.fire(s, "ember_rain", 450, p)
	assert_eq(U.find(ev, "projectile_end")[0]["reason"], "terrain")
	var ex: int = U.find(ev, "projectile_end")[0]["x"]
	assert_true(absi(ex - 800) <= 3)
	assert_eq(U.find(ev, "damage").size(), 0, "the tank is 18+ cells from the nearest point")
	assert_eq(s.tanks[1].health, 100)


func test_burn_total_reach_is_exactly_six_cells_and_caps() -> void:
	var t := TankState.new()
	t.x = 300
	t.y = 600  # box x 288..311, y 588..599
	var pts: PackedInt32Array = PackedInt32Array([317, 590, 318, 590, 300, 582, 300, 581, 318, 582, 306, 595])
	# 317 (6 right of x=311): in; 318: out; 582 (6 above 588): in; 581: out; corner (318,582): 8: out; inside: in.
	assert_eq(FireBehavior.burn_total(pts, t, 2, 6, 1000), 3 * 2)
	assert_eq(FireBehavior.burn_total(pts, t, 2, 6, 5), 5, "capped")
	assert_eq(FireBehavior.burn_total(pts, t, 2, 7, 1000), 5 * 2, "reach 7 admits (318, 590) and (300, 581) too")
	assert_eq(FireBehavior.burn_total(PackedInt32Array(), t, 2, 6, 40), 0)


func test_points_follow_the_downhill_slope() -> void:
	var s: MatchState = _valley()
	var p: int = WU.power_for_landing(s, 450, 600)
	var ev: Array[Dictionary] = WU.fire(s, "ember_rain", 450, p)
	var impact_x: int = U.find(ev, "projectile_end")[0]["x"]
	var pts: PackedInt32Array = U.find(ev, "flames")[0]["points"]
	assert_eq(pts.size(), 120)
	for i: int in range(0, pts.size(), 2):
		var x: int = pts[i]
		var y: int = pts[i + 1]
		assert_gt(x, impact_x + 150, "flowed far down the slope (x %d)" % x)
		assert_true(x <= 800, "never past the valley bottom")
		assert_eq(y, s.terrain.surface_y(x) - 1, "resting on the ground")


func test_flames_cross_level_steps_on_gentle_slopes() -> void:
	var s: MatchState = WU.shaped_state(2, func(x: int) -> int: return clampi(820 - absi(x - 800) / 2, 250, 820))
	WU.place_tank(s, 0, 100)
	WU.place_tank(s, 1, 1500)
	var p: int = WU.power_for_landing(s, 450, 650)
	var ev: Array[Dictionary] = WU.fire(s, "ember_rain", 450, p)
	var pts: PackedInt32Array = U.find(ev, "flames")[0]["points"]
	var impact_x: int = U.find(ev, "projectile_end")[0]["x"]
	for i: int in range(0, pts.size(), 2):
		assert_gt(pts[i], impact_x + 100, "slid well down the gentle slope: %d" % pts[i])


func test_inferno_has_more_points() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "inferno_gel", 450, WU.power_for_landing(s, 450, 800))
	assert_eq((U.find(ev, "flames")[0]["points"] as PackedInt32Array).size(), 220)


func test_flame_points_are_deterministic_scattered_and_clamped() -> void:
	var s: MatchState = U.flat_state(2)
	var a: PackedInt32Array = FireBehavior.flame_points(s.terrain, 800, 60)
	var b: PackedInt32Array = FireBehavior.flame_points(s.terrain, 800, 60)
	assert_eq(a, b)
	var xs: Dictionary = {}
	for i: int in range(0, a.size(), 2):
		xs[a[i]] = true
		assert_true(a[i] >= 790 and a[i] <= 810)
		assert_eq(a[i + 1], U.GROUND_Y - 1)
	assert_gt(xs.size(), 15, "scattered over the 21 columns")
	var edge: PackedInt32Array = FireBehavior.flame_points(s.terrain, 2, 60)
	for i: int in range(0, edge.size(), 2):
		assert_true(edge[i] >= 0)
	assert_eq(FireBehavior.flame_points(s.terrain, 800, 0).size(), 0)


func test_lost_shell_burns_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = WU.fire(s, "ember_rain", 1750, 900)
	assert_eq(U.find(ev, "flames").size(), 0)
	assert_eq(U.find(ev, "damage").size(), 0)


func test_team_damage_costs_the_shooter() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].team = 0
	s.tanks[0].money = 1000
	_hit_tank_one(s, "ember_rain")
	assert_eq(s.tanks[0].money, 1000 - 15 * 40, "burning a teammate counts as self damage")
