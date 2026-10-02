@warning_ignore_start("integer_division")
class_name AnchorBehavior
extends RefCounted
## Riptide Anchor (docs/ARCHITECTURE.md section 21): on any impact every alive tank whose
## centre is within `pull_r` cells of the impact point (the shooter included) is dragged toward
## the impact column by up to `max_pull` cells (half with an active Fortress Field), never past
## it. The drag walks one cell at a time like `move` but costs no fuel, may climb up to
## MAX_CLIMB_DRAG cells per step (a taller step stops it) and stops at the map edge or before
## another alive tank. Drops accumulate into falls exactly like a walk (Settle.apply_fall:
## fall damage unless a Drift Chute is used), credited to the shooter.
## Events per dragged tank in id order: tank_drag {tank, from_x, to_x}, then tank_fall /
## chute / damage as usual. The terrain is not changed.

const MAX_CLIMB_DRAG: int = 6


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return ticks
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	var pull_r2: int = (def["pull_r"] as int) * (def["pull_r"] as int)
	var fortress: int = Catalog.index_of("fortress_field")
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		var dx: int = t.x - ex
		var dy: int = t.y - SimConstants.SHIELD_CENTER_DY - ey
		if dx * dx + dy * dy > pull_r2:
			continue
		var limit: int = def["max_pull"]
		if t.has_shield() and t.shield_type == fortress:
			limit /= 2
		_drag(state, t, ex, limit, tank_id, ticks, events)
	return ticks


static func _drag(state: MatchState, t: TankState, target_x: int, limit: int, attacker: int, tick: int,
		events: Array[Dictionary]) -> void:
	var terrain: Terrain = state.terrain
	var half: int = SimConstants.TANK_W / 2
	var from_x: int = t.x
	var dir: int = 1 if target_x > t.x else -1
	var fall_runs: Array[Vector2i] = []
	var run_from: int = -1
	for _i: int in range(mini(absi(target_x - t.x), limit)):
		var nx: int = t.x + dir
		if nx - half < 0 or nx + half > terrain.width or _blocked(state, t, nx):
			break
		var ny: int = TankState.rest_y(terrain, nx)
		if t.y - ny > MAX_CLIMB_DRAG:
			break
		t.x = nx
		if ny - t.y > SimConstants.WALK_DROP:
			if run_from < 0:
				run_from = t.y
		elif run_from >= 0:
			fall_runs.append(Vector2i(run_from, t.y))
			run_from = -1
		t.y = ny
	if run_from >= 0:
		fall_runs.append(Vector2i(run_from, t.y))
	if t.x == from_x:
		return
	events.append({"type": "tank_drag", "tick": tick, "tank": t.id, "from_x": from_x, "to_x": t.x})
	for run: Vector2i in fall_runs:
		if not t.alive:
			break
		Settle.apply_fall(state, t.id, run.x, run.y, attacker, tick, events)


static func _blocked(state: MatchState, mover: TankState, nx: int) -> bool:
	for o: TankState in state.tanks:
		if o.alive and o.id != mover.id and absi(o.x - nx) < SimConstants.TANK_W:
			return true
	return false
