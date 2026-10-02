@warning_ignore_start("integer_division")
extends GutTest
## Seeker (docs/ARCHITECTURE.md section 21): homing after the apex.

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func _seeker_trace(s: MatchState, angle: int, power: int, wind: int = 0) -> Dictionary:
	return Ballistics.trace(s, 0, angle, power, "seeker", wind, SimConstants.MAX_FLIGHT_TICKS)


func _plain_trace(s: MatchState, angle: int, power: int, wind: int = 0) -> Dictionary:
	return Ballistics.trace(s, 0, angle, power, "pulse_missile", wind, SimConstants.MAX_FLIGHT_TICKS)


func _apex_index(path: PackedInt32Array) -> int:
	var best: int = 0
	for i: int in range(0, path.size(), 2):
		if path[i + 1] < path[best + 1]:
			best = i
	return best / 2


func test_seeker_hits_a_stationary_target_it_would_otherwise_miss_by_about_100_cells() -> void:
	var rng := Rng.new(77)
	var cases: int = 0
	var hits: int = 0
	for _k: int in range(24):
		var s: MatchState = U.flat_state(2)
		var angle: int = rng.range_int(250, 800)
		var tx: int = 700 + rng.range_int(0, 500)
		var off: int = (rng.range_int(0, 1) * 2 - 1) * rng.range_int(80, 120)
		s.tanks[1].x = tx
		var p: int = WU.power_for_landing(s, angle, tx + off)
		var plain: Dictionary = _plain_trace(s, angle, p)
		if absi((plain["end_x"] as int) - tx) <= 40:
			continue  # not a real miss
		cases += 1
		var tr: Dictionary = _seeker_trace(s, angle, p)
		if tr["end_reason"] == "tank" or absi((tr["end_x"] as int) - tx) <= 20:
			hits += 1
	assert_gt(cases, 15)
	assert_true(hits * 100 >= cases * 75, "seeker corrected %d of %d ~100-cell misses" % [hits, cases])


func test_path_is_identical_to_a_plain_shell_until_the_apex() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 1000
	var seek: Dictionary = _seeker_trace(s, 450, 600)
	var plain: Dictionary = _plain_trace(s, 450, 600)
	var apex: int = _apex_index(plain["path"])
	var a: PackedInt32Array = seek["path"]
	var b: PackedInt32Array = plain["path"]
	for i: int in range(2 * (apex + 1)):
		assert_eq(a[i], b[i], "entry %d" % i)
	assert_ne(a, b, "and it bends afterwards")


func test_nothing_to_chase_means_a_plain_flight() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].alive = false
	assert_eq(_seeker_trace(s, 450, 600)["path"], _plain_trace(s, 450, 600)["path"], "no enemy alive")
	var t: MatchState = U.flat_state(2)
	t.tanks[1].team = 0
	assert_eq(_seeker_trace(t, 450, 600)["path"], _plain_trace(t, 450, 600)["path"], "teammates are not chased")


func test_chases_the_nearest_alive_enemy_to_the_apex() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].x = 900
	s.tanks[2].x = 1500
	var near: Dictionary = _seeker_trace(s, 450, 600)
	s.tanks[1].alive = false
	var far: Dictionary = _seeker_trace(s, 450, 600)
	assert_ne(near["path"], far["path"])
	var plain_x: int = _plain_trace(s, 450, 600)["end_x"]
	assert_true(absi((near["end_x"] as int) - 900) < absi(plain_x - 900) or near["end_reason"] == "tank")
	assert_gt(far["end_x"] as int, plain_x, "pulled toward the far tank (to the right of the plain landing)")


func test_preview_equals_the_resolved_flight() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 1000
	var tr: Dictionary = _seeker_trace(s, 450, 600)
	var ev: Array[Dictionary] = WU.fire(s, "seeker", 450, 600)
	assert_eq(U.find(ev, "projectile")[0]["path"], tr["path"])
	var ex: Dictionary = U.find(ev, "explosion")[0]
	assert_eq([ex["x"], ex["y"], ex["radius"], ex["weapon"]], [tr["end_x"], tr["end_y"], 28, "seeker"])


func test_homing_responds_to_wind() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 1000
	var calm: Dictionary = _seeker_trace(s, 450, 600, 0)
	var windy: Dictionary = _seeker_trace(s, 450, 600, 80)
	assert_ne(calm["path"], windy["path"])
	var plain_calm: int = _plain_trace(s, 450, 600, 0)["end_x"]
	var plain_windy: int = _plain_trace(s, 450, 600, 80)["end_x"]
	assert_true(absi((windy["end_x"] as int) - 1000) < absi(plain_windy - 1000), "still closes in on the target")
	assert_gt(plain_windy, plain_calm)


func test_damage_goes_to_the_shooter_account() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 1000
	var p: int = WU.power_for_landing(s, 450, 1000)
	var ev: Array[Dictionary] = WU.fire(s, "seeker", 450, p)
	assert_true(s.tanks[1].health < 100, "the seeker found the tank")
	assert_eq(s.tanks[0].damage_dealt, 100 - s.tanks[1].health)
	assert_eq(s.tanks[0].money, 15 * (100 - s.tanks[1].health))
	assert_eq(U.find(ev, "explosion").size(), 1)


func test_seeker_is_deterministic() -> void:
	var a: MatchState = U.flat_state(2)
	var b: MatchState = U.flat_state(2)
	a.tanks[1].x = 1000
	b.tanks[1].x = 1000
	assert_eq(WU.events_digest(WU.fire(a, "seeker", 450, 600)), WU.events_digest(WU.fire(b, "seeker", 450, 600)))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))


func test_homing_accel_clamps_and_has_the_right_sign() -> void:
	var accel: int = 6554
	var one: int = FixedMath.ONE
	assert_eq(Ballistics._homing_accel(0, accel), 0)
	assert_eq(Ballistics._homing_accel(1000 * one, accel), accel)
	assert_eq(Ballistics._homing_accel(-1000 * one, accel), -accel)
	assert_eq(Ballistics._homing_accel(Ballistics.HOMING_SATURATION * one, accel), accel, "saturates exactly there")
	var half: int = Ballistics._homing_accel(Ballistics.HOMING_SATURATION * one / 2, accel)
	assert_true(absi(half - accel / 2) <= 1)


func test_predicted_landing_x() -> void:
	var one: int = FixedMath.ONE
	# At the target height with no vertical speed: lands right here.
	assert_eq(Ballistics._predict_x(500 * one, 300 * one, 7 * one, 0, 300 * one, 0), 500 * one)
	# Falling 100 cells from rest takes sqrt(2*100/0.15) ~ 36.5 ticks.
	var x: int = Ballistics._predict_x(500 * one, 300 * one, 7 * one, 0, 400 * one, 0)
	var expect: int = 500 * one + 7 * one * 3650 / 100
	assert_true(absi(x - expect) < 3 * one, "pred %d vs %d" % [x, expect])
	# A target above a falling shell is never reached.
	assert_eq(Ballistics._predict_x(500 * one, 300 * one, 7 * one, 5 * one, 100 * one, 0), 500 * one)
	# Wind adds its drift.
	var windy: int = Ballistics._predict_x(500 * one, 300 * one, 7 * one, 0, 400 * one, 13 * 50)
	assert_gt(windy, x)
