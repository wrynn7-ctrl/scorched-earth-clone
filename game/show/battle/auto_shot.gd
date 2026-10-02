@warning_ignore_start("integer_division")
class_name AutoShot
extends RefCounted
## Crude ballistic "AI" for screenshots and tests: finds an aim that lands on the nearest
## enemy using the pure Ballistics.trace (binary search on power for a set of angles). Not the
## game AI (that lives in game/ai/); this just needs to hit something deterministically.

const ANGLE_STEP: int = 100
const SEARCH_STEPS: int = 9


## Returns Vector2i(angle, power) for `tank_id` aiming at the nearest alive enemy.
static func find_shot(state: MatchState, tank_id: int) -> Vector2i:
	var me: TankState = state.tanks[tank_id]
	var target: TankState = null
	var best_gap: int = 1 << 30
	for t: TankState in state.tanks:
		if t.id != tank_id and t.alive and absi(t.x - me.x) < best_gap:
			best_gap = absi(t.x - me.x)
			target = t
	if target == null:
		return Vector2i(me.angle, me.power)
	var tx: int = target.x
	var ty: int = target.y - SimConstants.TANK_H / 2
	var right: bool = tx >= me.x
	var best: Vector2i = Vector2i(me.angle, me.power)
	var best_d: float = INF
	for a0: int in range(ANGLE_STEP * 2, ANGLE_STEP * 13, ANGLE_STEP):
		var angle: int = a0 if right else SimConstants.MAX_ANGLE - a0
		var lo: int = 40
		var hi: int = SimConstants.MAX_POWER
		for _i: int in range(SEARCH_STEPS):
			var mid: int = (lo + hi) / 2
			var tr: Dictionary = Ballistics.trace(state, tank_id, angle, mid, "pulse_missile",
					SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
			var ex: int = tr["end_x"]
			var ey: int = tr["end_y"]
			var reason: String = tr["end_reason"]
			if reason == "tank" and tr["hit_tank"] == target.id:
				return Vector2i(angle, mid)
			var d: float = Vector2(float(ex - tx), float(ey - ty)).length()
			if d < best_d and (reason == "terrain" or reason == "tank"):
				best_d = d
				best = Vector2i(angle, mid)
			var err: int = (ex - tx) if right else (tx - ex)
			if err < 0:
				lo = mid
			else:
				hi = mid
	return best
