@warning_ignore_start("integer_division")
extends GutTest
## Prism Splitter / Prism Cascade (docs/ARCHITECTURE.md section 21).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _fire(s: MatchState, weapon: String, angle: int = 450, power: int = 600) -> Array[Dictionary]:
	return WU.fire(s, weapon, angle, power)


func _children_ends(ev: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in U.find(ev, "projectile_end"):
		if (e["id"] as int) > 0:
			out.append(e)
	return out


func test_main_shell_stops_at_the_apex_and_children_follow_in_index_order() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire(s, "prism_splitter")
	var projectiles: Array[Dictionary] = U.find(ev, "projectile")
	assert_eq(projectiles.size(), 6, "main + 5 children")
	for i: int in range(6):
		assert_eq(projectiles[i]["id"], i)
		assert_eq(projectiles[i]["weapon"], "prism_splitter")
	var main_path: PackedInt32Array = projectiles[0]["path"]
	var main_end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(main_end["id"], 0)
	assert_eq(main_end["reason"], "split")
	assert_eq(main_end["tick"], main_path.size() / 2, "projectile_end.tick = path length")
	assert_eq(main_path[main_path.size() - 2] >> 16, main_end["x"])
	assert_eq(main_path[main_path.size() - 1] >> 16, main_end["y"])
	# The apex: the last path point is the highest point of the arc.
	var min_y: int = 1 << 40
	for k: int in range(1, main_path.size(), 2):
		min_y = mini(min_y, main_path[k])
	assert_true(absi(main_path[main_path.size() - 1] - min_y) <= 2 * FixedMath.ONE, "ends at the top of the arc")
	# Child events come in index order: projectile -> projectile_end -> explosion, one after the other.
	var types: Array[String] = U.types(ev)
	var seen: Array[int] = []
	for e: Dictionary in ev:
		if e["type"] == "projectile" and (e["id"] as int) > 0:
			seen.append(e["id"])
			assert_eq(e["tick"], main_end["tick"], "children start at the apex tick")
			var path: PackedInt32Array = e["path"]
			assert_gt(path.size(), 0)
	assert_eq(seen, [1, 2, 3, 4, 5] as Array[int])
	var order: Array[String] = []
	for e: Dictionary in ev:
		if e["type"] == "projectile" or e["type"] == "projectile_end" or e["type"] == "explosion":
			order.append("%s%s" % [e["type"], str(e.get("id", ""))])
	var expect: Array[String] = ["projectile0", "projectile_end0"]
	for i: int in range(1, 6):
		expect.append("projectile%d" % i)
		expect.append("projectile_end%d" % i)
		expect.append("explosion")
	assert_eq(order, expect)
	assert_eq(types.slice(types.size() - 2), ["wind", "turn"] as Array[String])


func test_child_end_ticks_are_apex_plus_path_length() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire(s, "prism_splitter")
	var projectiles: Array[Dictionary] = U.find(ev, "projectile")
	var ends: Array[Dictionary] = _children_ends(ev)
	var explosions: Array[Dictionary] = U.find(ev, "explosion")
	assert_eq(ends.size(), 5)
	for i: int in range(5):
		var path: PackedInt32Array = projectiles[i + 1]["path"]
		assert_eq(ends[i]["tick"], (projectiles[i + 1]["tick"] as int) + path.size() / 2)
		assert_eq(ends[i]["reason"], "terrain")
		assert_eq(explosions[i]["tick"], ends[i]["tick"])
		assert_eq([explosions[i]["x"], explosions[i]["y"]], [ends[i]["x"], ends[i]["y"]])
		assert_eq(explosions[i]["radius"], 24)
		assert_eq(path[path.size() - 2] >> 16, ends[i]["x"])


func test_spread_is_symmetric_around_the_main_path() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire(s, "prism_splitter")
	var xs: Array[int] = []
	for e: Dictionary in _children_ends(ev):
		xs.append(e["x"])
	for i: int in range(1, 5):
		assert_gt(xs[i], xs[i - 1], "children land left to right in index order")
	# The middle child keeps the main shell's velocity: it lands where a plain shell lands.
	var plain: Dictionary = WU.plain_trace(U.flat_state(2), 450, 600)
	assert_eq(xs[2], plain["end_x"])
	assert_lt(xs[0], xs[2])
	assert_gt(xs[4], xs[2])
	var left: int = xs[2] - xs[0]
	var right: int = xs[4] - xs[2]
	assert_true(absi(left - right) <= 3, "left %d vs right %d" % [left, right])
	assert_gt(left, 40, "a real fan of explosions")


func test_cascade_has_nine_small_children() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire(s, "prism_cascade")
	assert_eq(U.find(ev, "projectile").size(), 10)
	var explosions: Array[Dictionary] = U.find(ev, "explosion")
	assert_eq(explosions.size(), 9)
	for e: Dictionary in explosions:
		assert_eq(e["radius"], 18)
	var xs: Array[int] = []
	for e: Dictionary in _children_ends(ev):
		xs.append(e["x"])
	assert_eq(xs.size(), 9)
	for i: int in range(1, 9):
		assert_gt(xs[i], xs[i - 1])
	assert_eq(s.tanks[0].stock_of("prism_cascade"), 0, "one unit used")


func test_children_damage_the_enemy_and_pay_the_shooter() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 800
	var p: int = WU.power_for_landing(s, 450, 800)
	var money: int = s.tanks[0].money
	var ev: Array[Dictionary] = _fire(s, "prism_splitter", 450, p)
	var dmg: Dictionary = WU.damage_by_tank(ev)
	assert_true(dmg.has(1), "tank 1 is inside the fan")
	assert_false(dmg.has(0))
	assert_eq(s.tanks[1].health, maxi(0, 100 - (dmg[1] as int)))
	assert_eq(s.tanks[0].damage_dealt, 100 - s.tanks[1].health, "HP actually removed")
	assert_eq(s.tanks[0].money, money + 15 * (100 - s.tanks[1].health) + (1500 if not s.tanks[1].alive else 0))
	for e: Dictionary in U.find(ev, "damage"):
		assert_eq(e["cause"], "explosion")


func test_a_kill_by_a_child_is_credited_once() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].x = 800
	s.tanks[1].health = 5
	var p: int = WU.power_for_landing(s, 450, 800)
	var ev: Array[Dictionary] = _fire(s, "prism_splitter", 450, p)
	assert_false(s.tanks[1].alive)
	assert_eq(U.find(ev, "tank_destroyed").size(), 1)
	assert_eq(s.tanks[0].kills, 1)
	var kills: int = 0
	for e: Dictionary in U.find(ev, "money"):
		if e["reason"] == "kill":
			kills += 1
	assert_eq(kills, 1)


func test_main_shell_hitting_a_wall_before_its_apex_explodes_alone() -> void:
	var s: MatchState = U.flat_state(2)
	for x: int in range(330, 361):
		s.terrain.flatten(x, x, 100)  # a tall wall right next to the shooter
	var ev: Array[Dictionary] = _fire(s, "prism_splitter", 100, 800)
	assert_eq(U.find(ev, "projectile").size(), 1, "no children")
	var end: Dictionary = U.find(ev, "projectile_end")[0]
	assert_eq(end["reason"], "terrain")
	var ex: Array[Dictionary] = U.find(ev, "explosion")
	assert_eq(ex.size(), 1)
	assert_eq(ex[0]["radius"], 24)
	assert_eq(ex[0]["tick"], end["tick"])


func test_a_lost_main_shell_does_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].x = 20
	var ev: Array[Dictionary] = _fire(s, "prism_splitter", 1750, 900)
	assert_eq(U.find(ev, "projectile").size(), 1)
	assert_eq(U.find(ev, "projectile_end")[0]["reason"], "lost")
	assert_eq(U.find(ev, "explosion").size(), 0)


func test_trace_stops_at_the_apex_for_splitters() -> void:
	var s: MatchState = U.flat_state(2)
	var tr: Dictionary = Ballistics.trace(s, 0, 450, 600, "prism_splitter", 0, 1500)
	assert_eq(tr["end_reason"], "apex")
	assert_true(tr["apex"])
	assert_gte(tr["vy"] as int, 0)
	var ev: Array[Dictionary] = _fire(U.flat_state(2), "prism_splitter")
	assert_eq(tr["path"], U.find(ev, "projectile")[0]["path"], "the preview is the real main path")
	assert_eq(tr["ticks"], U.find(ev, "projectile_end")[0]["tick"])


func test_trace_children_matches_the_real_children_on_open_ground() -> void:
	var s: MatchState = U.flat_state(2)
	var kids: Array[Dictionary] = Ballistics.trace_children(s, 0, 450, 600, "prism_splitter", 0, 1500)
	assert_eq(kids.size(), 5)
	var ev: Array[Dictionary] = _fire(U.flat_state(2), "prism_splitter")
	var projectiles: Array[Dictionary] = U.find(ev, "projectile")
	for i: int in range(5):
		assert_eq(kids[i]["path"], projectiles[i + 1]["path"], "child %d" % i)
		assert_eq(kids[i]["start_tick"], projectiles[i + 1]["tick"])
	assert_eq(Ballistics.trace_children(s, 0, 450, 600, "pulse_missile", 0, 1500).size(), 0)
	assert_eq(Ballistics.trace_children(s, 0, 450, 600, "nonsense", 0, 1500).size(), 0)


func test_trace_children_does_not_mutate_the_state() -> void:
	var s: MatchState = U.flat_state(2)
	var before: String = Simulation.fingerprint(s)
	Ballistics.trace_children(s, 0, 450, 600, "prism_cascade", 0, 1500)
	assert_eq(Simulation.fingerprint(s), before)


func test_child_velocity_formula() -> void:
	var vx: int = 10 * FixedMath.ONE
	var step: int = 6 * FixedMath.ONE / 10
	assert_eq(Ballistics.child_vx(vx, 2, 5, 6), vx)
	assert_eq(Ballistics.child_vx(vx, 0, 5, 6), vx - 2 * step)
	assert_eq(Ballistics.child_vx(vx, 4, 5, 6), vx + 2 * step)
	assert_eq(Ballistics.child_vx(vx, 4, 9, 4), vx)
	assert_eq(Ballistics.child_vx(vx, 0, 2, 6), vx - step / 2, "even counts straddle the centre")


func test_children_start_from_the_apex_point() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _fire(s, "prism_splitter")
	var main_path: PackedInt32Array = U.find(ev, "projectile")[0]["path"]
	var child: PackedInt32Array = U.find(ev, "projectile")[3]["path"]
	var ax: int = main_path[main_path.size() - 2]
	var ay: int = main_path[main_path.size() - 1]
	assert_true(absi(child[0] - ax) <= 9 * FixedMath.ONE, "first child point is one tick from the apex")
	assert_true(absi(child[1] - ay) <= 2 * FixedMath.ONE)
