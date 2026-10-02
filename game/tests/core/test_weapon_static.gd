@warning_ignore_start("integer_division")
extends GutTest
## Static Burst (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _shielded(t: TankState, charge: int = 100) -> void:
	t.shield_type = Catalog.index_of("glow_shield")
	t.shield_hp = 30
	t.repulsor_charge = charge


func test_strip_fields_radius_boundary_is_exact() -> void:
	var s: MatchState = U.flat_state(3)
	# Tank centre = (x, y - 6). Blast at (500, 594): tank 1 centre is 40 away, tank 2's is 41 away.
	s.tanks[0].x = 460  # centre (460, 594): 40 to the left
	s.tanks[1].x = 541  # 41 to the right
	s.tanks[2].x = 800
	for t: TankState in s.tanks:
		_shielded(t)
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 500, 594, 40, 7, ev)
	assert_false(s.tanks[0].has_shield())
	assert_eq(s.tanks[0].repulsor_charge, 0)
	assert_true(s.tanks[1].has_shield(), "41 cells away keeps its shield")
	assert_eq(s.tanks[1].repulsor_charge, 100)
	assert_true(s.tanks[2].has_shield())
	assert_eq(U.types(ev), ["shield_down", "repulsor_down"] as Array[String])
	assert_eq([ev[0]["tank"], ev[0]["tick"], ev[1]["tank"]], [0, 7, 0])
	assert_eq(s.tanks[0].shield_type, -1)
	assert_eq(s.tanks[0].shield_hp, 0)


func test_strip_fields_only_removes_what_is_there_and_skips_the_dead() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].x = 500
	s.tanks[1].x = 520
	s.tanks[2].x = 540
	s.tanks[0].shield_type = Catalog.index_of("glow_shield")
	s.tanks[0].shield_hp = 30
	s.tanks[1].repulsor_charge = 50
	s.tanks[2].alive = false
	s.tanks[2].repulsor_charge = 50
	var ev: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 510, 594, 40, 0, ev)
	assert_eq(U.types(ev), ["shield_down", "repulsor_down"] as Array[String])
	assert_eq([ev[0]["tank"], ev[1]["tank"]], [0, 1])
	assert_eq(s.tanks[2].repulsor_charge, 50, "dead tanks are left alone")
	var none: Array[Dictionary] = []
	WeaponResolver.strip_fields(s, 510, 594, 40, 0, none)
	assert_eq(none.size(), 0, "nothing left to strip")


func test_burst_on_a_shielded_tank_strips_it_before_the_damage() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].x = 800
	s.tanks[2].x = 880  # centre 80 from tank 1, out of the 40 cell blast
	_shielded(s.tanks[1], 0)
	_shielded(s.tanks[2], 0)
	var p: int = WU.power_for_landing(s, 450, 800)
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "shield")
	var ev: Array[Dictionary] = WU.fire(s, "static_burst", 450, p)
	var types: Array[String] = U.types(ev)
	assert_true(types.find("explosion") < types.find("terrain_carve"))
	assert_true(types.find("terrain_carve") < types.find("shield_down"))
	assert_true(types.find("shield_down") < types.find("damage"))
	assert_eq(U.find(ev, "shield_hit").size(), 0, "the shield was gone before the damage")
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([ex["radius"], ex["weapon"]], [40, "static_burst"])
	assert_false(s.tanks[1].has_shield())
	assert_true(s.tanks[1].health < 100)
	assert_true(s.tanks[2].has_shield(), "outside the radius")
	assert_eq(s.tanks[2].shield_hp, 30)
	var sd: Array[Dictionary] = U.find(ev, "shield_down")
	assert_eq(sd.size(), 1)
	assert_eq(sd[0]["tank"], 1)
	assert_eq(s.tanks[0].damage_dealt, 100 - s.tanks[1].health)


func test_burst_strips_the_shooters_own_field_when_it_lands_on_it() -> void:
	var s: MatchState = U.flat_state(2)
	_shielded(s.tanks[0])
	var ev: Array[Dictionary] = WU.fire(s, "static_burst", 900, 300)
	assert_eq(U.find(ev, "projectile_end")[0]["reason"], "shield", "it falls back on its own bubble")
	var types: Array[String] = U.types(ev)
	assert_eq(types.count("shield_down"), 1)
	assert_eq(types.count("repulsor_down"), 1)
	assert_true(types.find("shield_down") < types.find("repulsor_down"))
	assert_false(s.tanks[0].has_shield())
	assert_eq(s.tanks[0].repulsor_charge, 0)


func test_damage_is_ten_scaled_by_distance() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "tank")
	var ev: Array[Dictionary] = WU.fire(s, "static_burst", 450, p)
	assert_eq(U.find(ev, "damage")[0]["amount"], 10)
	assert_eq(U.find(ev, "shield_down").size(), 0)


func test_lost_shell_strips_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	_shielded(s.tanks[1])
	var ev: Array[Dictionary] = WU.fire(s, "static_burst", 1750, 900)
	assert_eq(U.find(ev, "explosion").size(), 0)
	assert_true(s.tanks[1].has_shield())
