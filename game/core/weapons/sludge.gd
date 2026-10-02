@warning_ignore_start("integer_division")
class_name SludgeBehavior
extends RefCounted
## Sludge Shell (docs/ARCHITECTURE.md section 21): `volume` cells poured one at a time. Each
## cell starts at the impact column and flows downhill (SurfaceCache.flow_dir: toward the lower
## neighbour, on across level ground, ties alternate by column parity) for at most MAX_STEPS
## steps, then lands on top of that column. Level ground does not stop it: the sludge spreads
## out and fills valleys from the bottom up.
## Events: terrain_pour {x, cells, material}; the show re-applies it with Terrain.pour.

const MAX_STEPS: int = 300


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var ticks: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return ticks
	var ex: int = tr["end_x"]
	var terrain: Terrain = state.terrain
	var material: int = WeaponResolver.surface_material(terrain, ex)
	var cols: PackedInt32Array = plan(terrain, ex, def["volume"])
	terrain.pour(cols, material)
	events.append({"type": "terrain_pour", "tick": ticks, "x": ex, "cells": cols, "material": material})
	return ticks


## Columns the poured cells land on, in placement order (does not modify the terrain).
## The walk of the previous cell is reused: after a cell lands on column L only the decisions
## made at L and at its predecessor on the path can change (a flow only moves one way, one
## column per step, so it never doubles back), hence each cell re-walks just the tail of the
## path. The result equals walking every cell from the impact column.
static func plan(terrain: Terrain, start: int, volume: int) -> PackedInt32Array:
	var cols: PackedInt32Array = PackedInt32Array()
	if start < 0 or start >= terrain.width or volume <= 0:
		return cols
	var cache := SurfaceCache.new(terrain)
	var path_x: PackedInt32Array = PackedInt32Array([start])
	for _k: int in range(volume):
		var i: int = maxi(0, path_x.size() - 2)
		path_x.resize(i + 1)
		var c: int = path_x[i]
		while i < MAX_STEPS:
			var dir: int = 0 if i == 0 else path_x[i] - path_x[i - 1]
			var d: int = cache.flow_dir(c, dir, true)
			if d == 0:
				break
			c += d
			i += 1
			path_x.append(c)
		if cache.top(c) <= 0:
			continue  # column full to the top of the map: this cell is lost
		cols.append(c)
		cache.bump(c)
	return cols
