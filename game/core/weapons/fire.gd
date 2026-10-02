@warning_ignore_start("integer_division")
class_name FireBehavior
extends RefCounted
## Ember Rain / Inferno Gel (docs/ARCHITECTURE.md section 21): at the impact, `points` flame
## points scatter around the impact column and each walks downhill (<= MAX_STEPS steps) to
## rest on the surface. Every flame point damages each alive tank whose hit box is within
## `reach` cells of it (`dmg_per_point`), capped per tank at `cap`. Damage is applied once, at
## the impact tick, as cause "burn" (shields absorb it). The terrain is not changed.
## Events: flames {points: [x, y, ...]}, then damage*.

const MAX_STEPS: int = 200
## Scatter of the start columns around the impact column: offsets -SPREAD..SPREAD in a fixed
## shuffled order (11 is coprime with 2 * SPREAD + 1), so no random stream is needed.
const SPREAD: int = 10
const SCATTER_STEP: int = 11


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return ticks
	var points: PackedInt32Array = flame_points(state.terrain, tr["end_x"], def["points"])
	events.append({"type": "flames", "tick": ticks, "points": points})
	var per_point: int = def["dmg_per_point"]
	var reach: int = def["reach"]
	var cap: int = def["cap"]
	var totals: Array[int] = []
	for t: TankState in state.tanks:
		totals.append(0 if not t.alive else burn_total(points, t, per_point, reach, cap))
	for t: TankState in state.tanks:
		if totals[t.id] > 0:
			Simulation.apply_damage(state, tank_id, t.id, totals[t.id], "burn", ticks, events)
	return ticks


## Resting places [x, y, ...] of `count` flame points released around column `ex`.
static func flame_points(terrain: Terrain, ex: int, count: int) -> PackedInt32Array:
	var cache := SurfaceCache.new(terrain)
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in range(count):
		var c: int = clampi(ex + (i * SCATTER_STEP) % (2 * SPREAD + 1) - SPREAD, 0, terrain.width - 1)
		var steps: int = 0
		while steps < MAX_STEPS:
			var d: int = cache.pick_dir(c, i % 2 == 1)
			if d == 0:
				break
			c += d
			steps += 1
		out.append(c)
		out.append(maxi(0, cache.top(c) - 1))
	return out


## Damage a tank takes from `points`: per_point for each point within `reach` of its hit box,
## at most `cap`.
static func burn_total(points: PackedInt32Array, t: TankState, per_point: int, reach: int, cap: int) -> int:
	var sum: int = 0
	for i: int in range(0, points.size(), 2):
		if Damage.distance_to_tank(points[i], points[i + 1], t) <= reach:
			sum += per_point
	return mini(sum, cap)
