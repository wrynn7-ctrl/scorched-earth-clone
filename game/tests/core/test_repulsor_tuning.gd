extends GutTest
## The repulsor must really turn a direct hit into a miss (M3-C2 tuning of REPULSOR_PUSH).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")


func test_a_repulsor_turns_a_direct_hit_from_400_cells_into_a_miss_in_most_cases() -> void:
	var misses: int = 0
	var total: int = 0
	for angle: int in range(100, 801, 50):
		var s: MatchState = U.flat_state(2)
		s.tanks[1].x = 700  # 400 cells from the shooter
		var p: int = WU.power_for_landing(s, angle, 700)
		var base: Dictionary = WU.plain_trace(s, angle, p)
		assert_eq(base["end_reason"], "tank", "angle %d: the plain shot is a direct hit" % angle)
		s.tanks[1].repulsor_charge = SimConstants.REPULSOR_CHARGE
		var tr: Dictionary = WU.plain_trace(s, angle, p)
		total += 1
		if tr["end_reason"] != "tank" and absi((tr["end_x"] as int) - 700) > 28:
			misses += 1
	assert_eq(total, 15)
	assert_true(misses * 100 >= total * 80, "%d of %d shots were turned away" % [misses, total])


func test_power_600_shots_are_turned_away_at_every_flat_angle() -> void:
	# Power ~600 reaches ~400 cells at the low and the high angle of the same range.
	for angle: int in [150, 200, 250, 300, 400, 450]:
		var s: MatchState = U.flat_state(2)
		s.tanks[1].x = 700
		var p: int = WU.power_for_landing(s, angle, 700)
		s.tanks[1].repulsor_charge = SimConstants.REPULSOR_CHARGE
		var tr: Dictionary = WU.plain_trace(s, angle, p)
		assert_true(tr["end_reason"] != "tank" and absi((tr["end_x"] as int) - 700) > 28, "angle %d power %d ends at %d (%s)" % [angle, p, tr["end_x"], tr["end_reason"]])


func test_an_active_repulsor_saves_the_tank_from_damage_in_a_real_shot() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].x = 700
	var p: int = WU.power_for_landing(s, 300, 700)
	var saved: MatchState = s.duplicate_state()
	saved.tanks[1].repulsor_charge = SimConstants.REPULSOR_CHARGE
	WU.fire(s, "pulse_missile", 300, p)
	WU.fire(saved, "pulse_missile", 300, p)
	assert_true(s.tanks[1].health < 100)
	assert_eq(saved.tanks[1].health, 100)
	assert_lt(saved.tanks[1].repulsor_charge, SimConstants.REPULSOR_CHARGE, "some charge was used")


func test_the_owner_of_the_field_is_not_pushed() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].repulsor_charge = SimConstants.REPULSOR_CHARGE
	var with_field: Dictionary = WU.plain_trace(s, 900, 400)
	s.tanks[0].repulsor_charge = 0
	assert_eq(with_field["path"], WU.plain_trace(s, 900, 400)["path"])
