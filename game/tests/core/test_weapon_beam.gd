@warning_ignore_start("integer_division")
extends GutTest
## Photon Lance (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _state(tank1_x: int = 600) -> MatchState:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].x = tank1_x
	s.tanks[2].x = 900
	return s


func test_beam_hits_the_first_tank_for_flat_damage() -> void:
	var s: MatchState = _state()
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	assert_eq(U.types(ev), ["fire", "beam", "damage", "money", "wind", "turn"] as Array[String])
	var b: Dictionary = ev[1]
	assert_eq(b["tick"], 0)
	assert_eq([b["x0"], b["y0"]], [314, 588], "the muzzle cell")
	assert_eq([b["x1"], b["y1"]], [588, 588], "the first cell inside the box of tank 1")
	var d: Dictionary = U.find(ev, "damage")[0]
	assert_eq([d["tank"], d["amount"], d["health"], d["cause"]], [1, 35, 65, "beam"])
	assert_eq(s.tanks[2].health, 100, "stops at the first tank")
	assert_eq(s.tanks[0].money, 15 * 35)
	assert_eq(s.tanks[0].damage_dealt, 35)
	assert_eq(s.tanks[0].stock_of("photon_lance"), 0)
	assert_eq(U.find(ev, "projectile").size(), 0, "no projectile")
	assert_eq(U.find(ev, "explosion").size(), 0, "no explosion")


func test_damage_does_not_depend_on_distance() -> void:
	for x: int in [400, 800, 1200]:
		var s: MatchState = _state(x)
		s.tanks[2].x = 1500
		WU.fire(s, "photon_lance", 0, 500)
		assert_eq(s.tanks[1].health, 65, "x=%d" % x)


func test_beam_ignores_wind_gravity_and_power() -> void:
	var ref: Array[Dictionary] = []
	for wind: int in [-100, 0, 100]:
		for power: int in [100, 1000]:
			var s: MatchState = _state()
			s.wind = wind
			var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, power)
			if ref.is_empty():
				ref = ev.slice(1, 4)
			else:
				assert_eq(ev.slice(1, 4), ref, "wind %d power %d" % [wind, power])
	var s2: MatchState = _state()
	var a: Dictionary = Ballistics.trace(s2, 0, 300, 500, "photon_lance", -100, 1500)
	s2.wind = 100
	var b: Dictionary = Ballistics.trace(s2, 0, 300, 500, "photon_lance", 100, 1500)
	var c: Dictionary = Ballistics.trace(s2, 0, 300, 1, "photon_lance", 0, 1500)
	assert_eq(a["path"], b["path"])
	assert_eq(a["path"], c["path"])


func test_beam_path_is_a_straight_line() -> void:
	var s: MatchState = _state()
	var tr: Dictionary = Ballistics.trace(s, 0, 300, 500, "photon_lance", 0, 1500)
	var path: PackedInt32Array = tr["path"]
	assert_gt(path.size() / 2, 100)
	var sx: int = path[2] - path[0]
	var sy: int = path[3] - path[1]
	for i: int in range(1, path.size() / 2):
		assert_eq(path[2 * i] - path[2 * i - 2], sx, "constant x step %d" % i)
		assert_eq(path[2 * i + 1] - path[2 * i - 1], sy, "constant y step %d" % i)
	assert_true(absi(sx) > 0 and sy < 0, "flying up and right at 30 degrees")


func test_a_shield_stops_the_beam_and_absorbs_the_damage() -> void:
	var s: MatchState = _state()
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	assert_eq(U.find(ev, "shield_hit")[0]["absorbed"], 30)
	assert_eq(U.find(ev, "shield_down").size(), 1)
	assert_eq(U.find(ev, "damage")[0]["amount"], 5)
	assert_eq(s.tanks[1].health, 95)
	var b: Dictionary = U.find(ev, "beam")[0]
	assert_true((b["x1"] as int) < 588, "stopped at the bubble, before the box")
	assert_eq(s.tanks[2].health, 100)


func test_beam_cuts_at_most_120_solid_cells() -> void:
	var s: MatchState = _state(1400)
	for x: int in range(400, 701):
		s.terrain.flatten(x, x, 500)  # a 300 cell thick wall across the beam (y 588)
	var before: Terrain = s.terrain.duplicate_terrain()
	var tr: Dictionary = Ballistics.trace(s, 0, 0, 500, "photon_lance", 0, 1500)
	assert_eq(tr["solid_steps"], 120)
	assert_eq(tr["end_reason"], "terrain")
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	var tun: Dictionary = U.find(ev, "tunnel")[0]
	assert_eq([tun["x0"], tun["y0"], tun["x1"], tun["y1"], tun["radius"]], [400, 588, 519, 588, 3])
	assert_eq(U.find(ev, "beam")[0]["x1"], 519, "the beam ends where the cut ends")
	assert_eq(U.find(ev, "damage").size(), 0, "the tank behind the wall is safe")
	var carved: Terrain = WU.replay_terrain(before, ev.slice(0, U.types(ev).find("tunnel") + 1))
	var removed: int = WU.solid_count(before) - WU.solid_count(carved)
	assert_true(removed <= 120 * 7 + 40 and removed >= 119 * 7, "removed %d cells" % removed)
	var types: Array[String] = U.types(ev)
	assert_true(types.find("beam") < types.find("tunnel"))
	assert_true(types.find("tunnel") < types.find("terrain_settle"))
	assert_true(WU.replay_matches(before, ev, s.terrain))


func test_a_thin_wall_does_not_stop_the_beam() -> void:
	var s: MatchState = _state()
	for x: int in range(400, 410):
		s.terrain.flatten(x, x, 500)
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	var tun: Dictionary = U.find(ev, "tunnel")[0]
	assert_eq([tun["x0"], tun["x1"]], [400, 409])
	assert_eq(s.tanks[1].health, 65, "it still reaches the tank")


func test_beam_tunnel_makes_the_ground_above_it_fall() -> void:
	var s: MatchState = _state(1400)
	for x: int in range(400, 500):
		s.terrain.flatten(x, x, 500)
	var top_before: int = s.terrain.surface_y(450)
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	assert_eq(U.find(ev, "terrain_settle").size(), 1)
	assert_eq(s.terrain.surface_y(450), top_before + 7, "7 rows were bored under it, the wall dropped into the hole")


func test_beam_leaving_the_map_hurts_nobody() -> void:
	for angle: int in [900, 1800]:
		var s: MatchState = _state()
		var tr: Dictionary = Ballistics.trace(s, 0, angle, 500, "photon_lance", 0, 1500)
		assert_eq(tr["end_reason"], "lost", "angle %d" % angle)
		var ev: Array[Dictionary] = WU.fire(s, "photon_lance", angle, 500)
		assert_eq(U.types(ev), ["fire", "beam", "wind", "turn"] as Array[String])
	var s2: MatchState = _state()
	s2.tanks[1].x = 1100
	s2.tanks[2].x = 1550
	var tr2: Dictionary = Ballistics.trace(s2, 0, 0, 500, "photon_lance", 0, 1500)
	assert_eq(tr2["end_reason"], "tank", "a tank within reach")
	s2.tanks[1].x = 1500
	s2.tanks[0].x = 100
	var far: Dictionary = Ballistics.trace(s2, 0, 0, 500, "photon_lance", 0, 1500)
	assert_eq(far["end_reason"], "lost", "beam length 900 ends at x = 1014")
	assert_eq(far["ticks"], 900)


func test_beam_is_deterministic() -> void:
	var a: MatchState = _state()
	var b: MatchState = _state()
	for x: int in range(400, 500):
		a.terrain.flatten(x, x, 500)
		b.terrain.flatten(x, x, 500)
	var ea: Array[Dictionary] = WU.fire(a, "photon_lance", 0, 500)
	var eb: Array[Dictionary] = WU.fire(b, "photon_lance", 0, 500)
	assert_eq(WU.events_digest(ea), WU.events_digest(eb))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
