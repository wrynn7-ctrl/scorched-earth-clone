@warning_ignore_start("integer_division")
extends GutTest
## Bore Shell / Deep Bore (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _len(e: Dictionary) -> int:
	var dx: int = (e["x1"] as int) - (e["x0"] as int)
	var dy: int = (e["y1"] as int) - (e["y0"] as int)
	return FixedMath.isqrt(dx * dx + dy * dy)


func _shot(weapon: String, angle: int = 450, target_x: int = 900) -> Array[Dictionary]:
	var s: MatchState = U.flat_state(2)
	return WU.fire(s, weapon, angle, WU.power_for_landing(s, angle, target_x))


func test_bore_shell_tunnel_has_the_configured_length_and_radius() -> void:
	var ev: Array[Dictionary] = _shot("bore_shell")
	var tun: Array[Dictionary] = U.find(ev, "tunnel")
	assert_eq(tun.size(), 1)
	assert_eq(tun[0]["radius"], 6)
	assert_true(absi(_len(tun[0]) - 80) <= 1, "length %d" % _len(tun[0]))
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq([tun[0]["x0"], tun[0]["y0"]], [end["x"], end["y"]], "starts at the impact cell")
	assert_eq(tun[0]["tick"], end["tick"])


func test_deep_bore_is_longer_and_wider() -> void:
	var ev: Array[Dictionary] = _shot("deep_bore", 200, 800)
	var tun: Dictionary = U.find(ev, "tunnel")[0]
	assert_eq(tun["radius"], 7)
	assert_true(absi(_len(tun) - 180) <= 1, "length %d" % _len(tun))
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([ex["x"], ex["y"], ex["radius"]], [tun["x1"], tun["y1"], 14])


func test_tunnel_continues_in_the_flight_direction_then_blasts_at_its_end() -> void:
	var ev: Array[Dictionary] = _shot("bore_shell", 450, 900)
	var tun: Dictionary = U.find(ev, "tunnel")[0]
	assert_gt(tun["x1"] as int, tun["x0"] as int, "the shell was flying right")
	assert_gt(tun["y1"] as int, tun["y0"] as int, "and down")
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([ex["x"], ex["y"], ex["radius"], ex["weapon"]], [tun["x1"], tun["y1"], 12, "bore_shell"])
	var types: Array[String] = U.types(ev)
	assert_true(types.find("tunnel") < types.find("explosion"))
	assert_true(types.find("explosion") < types.find("terrain_settle"))
	assert_eq(U.find(ev, "terrain_carve").size(), 1, "just the end blast crater")


func test_the_tunnel_event_replays_to_the_carved_capsule() -> void:
	var s: MatchState = U.flat_state(2)
	var before: Terrain = s.terrain.duplicate_terrain()
	var p: int = WU.power_for_landing(s, 450, 900)
	var ev: Array[Dictionary] = WU.fire(s, "bore_shell", 450, p)
	var upto: Array[Dictionary] = []
	for e: Dictionary in ev:
		upto.append(e)
		if e["type"] == "tunnel":
			break
	var carved: Terrain = WU.replay_terrain(before, upto)
	var tun: Dictionary = upto[upto.size() - 1]
	var x0: int = tun["x0"]
	var y0: int = tun["y0"]
	var x1: int = tun["x1"]
	var y1: int = tun["y1"]
	for i: int in range(0, 11):
		var cx: int = x0 + (x1 - x0) * i / 10
		var cy: int = y0 + (y1 - y0) * i / 10
		assert_false(carved.is_solid(cx, cy), "axis cell %d is air" % i)
		assert_true(before.is_solid(cx, cy) or cy < U.GROUND_Y, "it was ground before")
	var removed: int = WU.solid_count(before) - WU.solid_count(carved)
	assert_gt(removed, 80 * 8, "a real tunnel (80 cells long, 13 wide, partly above the ground)")
	assert_lt(removed, 80 * 14 + 200)


func test_a_tank_above_the_tunnel_falls_after_the_settle() -> void:
	# Shallow shot so the whole tunnel runs under the ground.
	var probe: MatchState = U.flat_state(2)
	var p: int = WU.power_for_landing(probe, 100, 800)
	var dry: Array[Dictionary] = WU.fire(probe, "bore_shell", 100, p)
	var tun: Dictionary = U.find(dry, "tunnel")[0]
	var xm: int = (tun["x0"] as int) + ((tun["x1"] as int) - (tun["x0"] as int)) * 3 / 4
	var s: MatchState = U.flat_state(2)
	WU.place_tank(s, 1, xm)
	var y_before: int = s.tanks[1].y
	var ev: Array[Dictionary] = WU.fire(s, "bore_shell", 100, p)
	var falls: Array[Dictionary] = []
	for e: Dictionary in U.find(ev, "tank_fall"):
		if e["tank"] == 1:
			falls.append(e)
	assert_eq(falls.size(), 1, "the tank above the tunnel falls")
	assert_gt(s.tanks[1].y, y_before)
	assert_eq(s.tanks[1].y, TankState.rest_y(s.terrain, xm), "and rests on the new surface")
	var types: Array[String] = U.types(ev)
	assert_true(types.find("terrain_settle") < types.find("tank_fall"))


func test_settle_covers_both_the_tunnel_and_the_crater() -> void:
	var ev: Array[Dictionary] = _shot("bore_shell")
	var tun: Dictionary = U.find(ev, "tunnel")[0]
	var st: Dictionary = U.find(ev, "terrain_settle")[0]
	assert_true((st["x0"] as int) <= (tun["x0"] as int) - 6)
	assert_true((st["x1"] as int) >= (tun["x1"] as int) + 12)
	assert_eq(U.find(ev, "terrain_settle").size(), 1)


func test_direct_hit_on_a_tank_just_blasts() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	assert_eq(WU.plain_trace(s, 450, p)["end_reason"], "tank")
	var ev: Array[Dictionary] = WU.fire(s, "bore_shell", 450, p)
	assert_eq(U.find(ev, "tunnel").size(), 0)
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq(ex["radius"], 12)
	var d: Dictionary = U.find(ev, "damage")[0]
	assert_eq([d["tank"], d["amount"]], [1, 20], "end blast damage 20 at distance 0")
	assert_eq(s.tanks[0].damage_dealt, 20)
	assert_eq(s.tanks[0].money, 15 * 20, "15 credits per HP removed (flat_state starts at 0)")


func test_lost_shell_has_no_tunnel() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = WU.fire(s, "bore_shell", 1750, 900)
	assert_eq(U.find(ev, "tunnel").size(), 0)
	assert_eq(U.find(ev, "explosion").size(), 0)


func test_bore_end_stops_before_a_tank() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 150  # box x 138..149, y 588..599
	var px: int = FixedMath.from_cell(100)
	var py: int = FixedMath.from_cell(590)
	var end: Vector2i = TunnelerBehavior.bore_end(s, px, py, 10 * FixedMath.ONE, 0, 80)
	assert_eq(end, Vector2i(137, 590))
	var free: Vector2i = TunnelerBehavior.bore_end(s, px, py - 40 * FixedMath.ONE, 10 * FixedMath.ONE, 0, 80)
	assert_eq(free, Vector2i(180, 550), "the full length when nothing is in the way")


func test_bore_end_ignores_dead_tanks() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 150
	s.tanks[1].alive = false
	var end: Vector2i = TunnelerBehavior.bore_end(s, FixedMath.from_cell(100), FixedMath.from_cell(590),
			10 * FixedMath.ONE, 0, 80)
	assert_eq(end, Vector2i(180, 590))


func test_bore_end_stops_at_the_map_edge() -> void:
	var s: MatchState = U.flat_state(2)
	var one: int = FixedMath.ONE
	assert_eq(TunnelerBehavior.bore_end(s, FixedMath.from_cell(1590), FixedMath.from_cell(300), 5 * one, 0, 80),
			Vector2i(1599, 300))
	assert_eq(TunnelerBehavior.bore_end(s, FixedMath.from_cell(10), FixedMath.from_cell(300), -5 * one, 0, 80),
			Vector2i(0, 300))
	assert_eq(TunnelerBehavior.bore_end(s, FixedMath.from_cell(800), FixedMath.from_cell(5), 0, -5 * one, 80),
			Vector2i(800, 0))
	assert_eq(TunnelerBehavior.bore_end(s, FixedMath.from_cell(800), FixedMath.from_cell(895), 0, 5 * one, 80),
			Vector2i(800, 899))


func test_bore_end_zero_velocity_and_diagonal() -> void:
	var s: MatchState = U.flat_state(2)
	var start: int = FixedMath.from_cell(500)
	assert_eq(TunnelerBehavior.bore_end(s, start, start, 0, 0, 80), Vector2i(500, 500))
	var d: Vector2i = TunnelerBehavior.bore_end(s, start, start, 3 * FixedMath.ONE, 4 * FixedMath.ONE, 100)
	assert_eq(d, Vector2i(559, 579), "3-4-5 direction, 100 cells (unit vector truncated to Q16.16)")
	assert_eq(TunnelerBehavior.bore_end(s, start, start, 3 * FixedMath.ONE, 4 * FixedMath.ONE, 0), Vector2i(500, 500))
