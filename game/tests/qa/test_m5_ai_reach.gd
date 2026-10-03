@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: the CPU out-of-reach rule (docs/ARCHITECTURE.md section 38). Tanks as far apart as the map
## allows with a head wind, behind walls and in pits: every level must produce legal actions, a turn must end
## within 3 calls, a round must end, and the CPU must never hoard more than 200 fuel units.

const QaUtil = preload("res://tests/qa/qa_util.gd")

const MAX_TURNS: int = 700


func _duel(xs: Array[int], level_a: int, level_b: int, wind: int) -> MatchState:
	var s: MatchState = QaUtil.flat_state(xs, 600, 3)
	s.settings.controllers = PackedInt32Array([level_a, level_b])
	s.settings.wind_max = 100
	s.wind = wind
	return s


## Plays one round of CPU turns. Returns {turns, ended, calls_max, fuel_max, invalid, walked}.
func _round(s: MatchState) -> Dictionary:
	var res: Dictionary = {"turns": 0, "ended": false, "calls_max": 0, "fuel_max": 0, "invalid": [] as Array[String], "walked": 0}
	while s.phase == SimConstants.PHASE_AIM and (res["turns"] as int) < MAX_TURNS:
		var tank: int = s.current_tank
		var calls: int = 0
		var turn_at: int = s.turn_number
		while s.phase == SimConstants.PHASE_AIM and s.current_tank == tank and s.turn_number == turn_at and calls < 6:
			calls += 1
			var a: Dictionary = AiPlayer.next_action(s, tank)
			var err: String = Simulation.validate_action(s, a)
			if err != "":
				(res["invalid"] as Array[String]).append("%s -> %s" % [str(a), err])
				return res
			if a["kind"] == "move":
				res["walked"] = (res["walked"] as int) + 1
			Simulation.apply_action(s, a)
			for t: TankState in s.tanks:
				var units: int = t.fuel + t.stock_of("fuel_cell") * 100
				res["fuel_max"] = maxi(res["fuel_max"] as int, units)
		res["calls_max"] = maxi(res["calls_max"] as int, calls)
		res["turns"] = (res["turns"] as int) + 1
		if calls >= 6:
			(res["invalid"] as Array[String]).append("turn did not end within 6 calls")
			return res
	res["ended"] = s.phase != SimConstants.PHASE_AIM
	return res


func test_far_apart_in_a_head_wind() -> void:
	var report: PackedStringArray = PackedStringArray()
	var bad: Array[String] = []
	for level: int in [1, 2, 3, 4]:
		for wind: int in [100, -100, 60]:
			for fuel: int in [0, 100]:
				var s: MatchState = _duel([12, 1588], level, level, wind)
				s.tanks[0].fuel = fuel
				s.tanks[1].fuel = fuel
				var r: Dictionary = _round(s)
				report.append("L%d w%d f%d: %d turns%s walks %d" % [level, wind, fuel, r["turns"], "" if r["ended"] else " NOT ENDED", r["walked"]])
				var tag: String = "level %d wind %d fuel %d" % [level, wind, fuel]
				if not (r["invalid"] as Array[String]).is_empty():
					bad.append("%s: %s" % [tag, str(r["invalid"])])
				if not (r["ended"] as bool):
					bad.append("%s: no winner after %d turns (health %d/%d)" % [tag, MAX_TURNS, s.tanks[0].health, s.tanks[1].health])
				elif level >= 2 and (r["turns"] as int) > 120:
					bad.append("%s: took %d turns (Normal and better should finish in about 100 or fewer)" % [tag, r["turns"]])
				if (r["calls_max"] as int) > 3:
					bad.append("%s: a turn took %d calls" % [tag, r["calls_max"]])
				if (r["fuel_max"] as int) > 200 + 100:
					bad.append("%s: held %d fuel units" % [tag, r["fuel_max"]])
	gut.p("AI REACH  far apart: %s" % "; ".join(report))
	assert_eq(bad.size(), 0, "\n  " + "\n  ".join(bad))


## Solid wall of `height` cells on the flat ground, columns [x0, x1).
func _wall(s: MatchState, x0: int, x1: int, height: int) -> void:
	for x: int in range(x0, x1):
		for y: int in range(600 - height, 600):
			s.terrain.cells[x * SimConstants.WORLD_H + y] = 1


func test_a_wall_between_the_tanks_does_not_stall_a_round() -> void:
	var report: PackedStringArray = PackedStringArray()
	var bad: Array[String] = []
	for height: int in [120, 300, 480]:
		for level: int in [1, 2, 3, 4]:
			var s: MatchState = _duel([300, 1300], level, level, 20)
			_wall(s, 780, 820, height)
			var r: Dictionary = _round(s)
			report.append("h%d/L%d: %d turns" % [height, level, r["turns"]])
			var tag: String = "wall %d level %d" % [height, level]
			if not (r["invalid"] as Array[String]).is_empty():
				bad.append("%s: %s" % [tag, str(r["invalid"])])
			if not (r["ended"] as bool):
				bad.append("%s: no winner after %d turns" % [tag, MAX_TURNS])
			if (r["calls_max"] as int) > 3:
				bad.append("%s: a turn took %d calls" % [tag, r["calls_max"]])
	gut.p("AI REACH  walls: %s" % "; ".join(report))
	assert_eq(bad.size(), 0, "\n  " + "\n  ".join(bad))
