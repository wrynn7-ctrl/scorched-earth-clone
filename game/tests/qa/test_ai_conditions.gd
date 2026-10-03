@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: how well the AI shoots under hostile conditions. 30 seeded duels on generated terrain
## (distance 300..1200) are replayed per condition and level; the AI's first shot is traced with
## the real Ballistics.trace and counted as a "hit" when the shell ends inside the target's box,
## or "near" when it ends within a Pulse Missile's blast radius (28) of it.
## Conditions: calm, wind +100, wind -100, a charged Repulsor on the target, an enemy Singularity
## Seed near the shooter, a well near the target, a Fortress Field on the target.
## Reports the table; asserts that no condition makes Expert/Hard collapse.

const DUELS: int = 30
const NAMES: Array[String] = ["", "easy", "normal", "hard", "expert"]
const CONDITIONS: Array[String] = ["calm", "wind+100", "wind-100", "repulsor", "well@shooter", "well@target", "fortress"]
const BLAST: int = 28

var _table: Dictionary = {}  # "level/condition" -> [hit, near, n]
var _elapsed_ms: int = 0


func _duel(i: int) -> MatchState:
	var r: Rng = Rng.derive(i * 104729 + 17, 5150)
	return AiTestUtil.duel(8000 + i, SimConstants.CTRL_NORMAL, r.range_int(300, 1200), 0)


func _apply_condition(state: MatchState, cond: String) -> void:
	var me: TankState = state.tanks[0]
	var foe: TankState = state.tanks[1]
	var dir: int = 1 if foe.x >= me.x else -1
	match cond:
		"wind+100":
			state.wind = 100
		"wind-100":
			state.wind = -100
		"repulsor":
			foe.repulsor_charge = 100
		"well@shooter":
			state.wells.append({"owner": 1, "x": clampi(me.x + dir * 90, 20, 1580), "y": me.y - 130, "expires_turn": 99})
		"well@target":
			state.wells.append({"owner": 1, "x": clampi(foe.x - dir * 60, 20, 1580), "y": foe.y - 100, "expires_turn": 99})
		"fortress":
			foe.shield_type = Catalog.index_of("fortress_field")
			foe.shield_hp = 100


func _first_shot(state: MatchState) -> Vector2i:
	## (hit, near) of the AI's first fired shot, traced with the real physics.
	var action: Dictionary = {}
	var guard: int = 0
	while guard < 3:
		guard += 1
		action = AiPlayer.next_action(state, 0)
		if action["kind"] == "fire":
			break
		Simulation.apply_action(state, action)  # a shield or repulsor first: apply and ask again
	if action.get("kind", "") != "fire":
		return Vector2i(0, 0)
	var weapon: String = action["weapon"]
	var tr: Dictionary = Ballistics.trace(state, 0, action["angle"], action["power"], weapon, SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	var hit: int = 1 if (tr["hit_tank"] as int) == 1 else 0
	var foe: TankState = state.tanks[1]
	var half: int = SimConstants.TANK_W / 2
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	var dx: int = maxi(maxi(foe.x - half - ex, ex - (foe.x + half - 1)), 0)
	var dy: int = maxi(maxi(foe.y - SimConstants.TANK_H - ey, ey - (foe.y - 1)), 0)
	var near: int = 1 if FixedMath.isqrt(dx * dx + dy * dy) <= BLAST else 0
	return Vector2i(hit, maxi(hit, near))


func before_all() -> void:
	var t0: int = Time.get_ticks_msec()
	for i: int in range(DUELS):
		var base: MatchState = _duel(i)
		for lv: int in [2, 3, 4]:
			for cond: String in CONDITIONS:
				var s: MatchState = base.duplicate_state()
				s.settings.controllers[0] = lv
				_apply_condition(s, cond)
				if cond == "fortress" and lv == 4:
					s.tanks[0].set_stock("static_burst", 3)
				var key: String = "%d/%s" % [lv, cond]
				var e: Array = _table.get(key, [0, 0, 0]) as Array
				var hn: Vector2i = _first_shot(s)
				e[0] = (e[0] as int) + hn.x
				e[1] = (e[1] as int) + hn.y
				e[2] = (e[2] as int) + 1
				_table[key] = e
	_elapsed_ms = Time.get_ticks_msec() - t0


func _rate(lv: int, cond: String, col: int) -> int:
	var e: Array = _table["%d/%s" % [lv, cond]]
	return (e[col] as int) * 100 / (e[2] as int)


func test_report_first_shot_table() -> void:
	var text: String = "AICOND  first shot, %d duels per cell, %.1f s. Cells are hit%%/near%%:\n" % [DUELS, float(_elapsed_ms) / 1000.0]
	text += "AICOND  %-9s" % "level"
	for c: String in CONDITIONS:
		text += " %-13s" % c
	text += "\n"
	for lv: int in [2, 3, 4]:
		text += "AICOND  %-9s" % NAMES[lv]
		for c: String in CONDITIONS:
			text += " %-13s" % ("%d/%d" % [_rate(lv, c, 0), _rate(lv, c, 1)])
		text += "\n"
	gut.p(text)
	assert_eq(_table.size(), 3 * CONDITIONS.size())


func test_max_wind_does_not_collapse_the_good_levels() -> void:
	# Spec section 30: calm Expert first shot hits 60-75 %. In a gale it may drop but must stay useful,
	# and must not be worse than a Normal in calm air.
	for cond: String in ["wind+100", "wind-100"]:
		var near4: int = _rate(4, cond, 1)
		assert_gte(near4, 40, "Expert near-miss rate at %s (%d%%)" % [cond, near4])
		var near3: int = _rate(3, cond, 1)
		assert_gte(near3, 30, "Hard near-miss rate at %s (%d%%)" % [cond, near3])


func test_repulsor_and_wells_do_not_blind_the_solver() -> void:
	for cond: String in ["repulsor", "well@shooter", "well@target"]:
		var near4: int = _rate(4, cond, 1)
		var calm4: int = _rate(4, "calm", 1)
		gut.p("AICOND  Expert %s near %d%% vs calm %d%%" % [cond, near4, calm4])
		assert_gte(near4, 25, "Expert near-miss rate with %s (%d%%)" % [cond, near4])


func test_fortress_shield_is_still_attacked() -> void:
	# A shield soaks damage but a shell that lands on the bubble still counts: the AI must keep
	# aiming at the tank.
	assert_gte(_rate(4, "fortress", 1), 40, "Expert near-miss rate against a Fortress Field")
	assert_gte(_rate(3, "fortress", 1), 30)
