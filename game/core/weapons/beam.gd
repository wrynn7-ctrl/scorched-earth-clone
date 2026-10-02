@warning_ignore_start("integer_division")
class_name BeamBehavior
extends RefCounted
## Photon Lance (docs/ARCHITECTURE.md section 21): an instant straight beam from the muzzle
## (see Ballistics.trace_beam: no wind, gravity, wells or repulsors). It bores a tunnel of
## radius `beam_r` through the first stretch of solid ground (at most `cut` solid cells, then
## it stops), and damages the first tank or shield it meets by a flat `dmg` (cause "beam").
## There is no projectile and no explosion. Everything happens at tick 0.
## Events: beam {x0, y0, x1, y1} (muzzle cell to the end cell), tunnel {x0, y0, x1, y1, radius}
## (first to last solid cell crossed, only if any), damage*, terrain_settle ...


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = Ballistics.trace(state, tank_id, action["angle"], action["power"], action["weapon"],
			SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
	events.append({"type": "beam", "tick": 0, "x0": tr["start_x"], "y0": tr["start_y"],
			"x1": tr["end_x"], "y1": tr["end_y"]})
	var rect := Rect2i()
	if (tr["solid_steps"] as int) > 0:
		var radius: int = def["beam_r"]
		events.append({"type": "tunnel", "tick": 0, "x0": tr["first_solid_x"], "y0": tr["first_solid_y"],
				"x1": tr["last_solid_x"], "y1": tr["last_solid_y"], "radius": radius})
		rect = state.terrain.carve_tunnel(tr["first_solid_x"], tr["first_solid_y"], tr["last_solid_x"],
				tr["last_solid_y"], radius)
	var hit: int = tr["hit_tank"]
	if hit >= 0:
		Simulation.apply_damage(state, tank_id, hit, def["dmg"], "beam", 0, events)
	if rect.size.x > 0:
		Settle.settle_region(state, rect.position.x, rect.end.x - 1, tank_id, 0, events)
	return 0
