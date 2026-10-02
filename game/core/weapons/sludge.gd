@warning_ignore_start("integer_division")
class_name SludgeBehavior
extends RefCounted
## Sludge Shell (docs/ARCHITECTURE.md section 21): `volume` cells poured one at a time. Each
## cell starts at the impact column and walks downhill (see SurfaceCache.pick_dir; ties
## prefer left, then alternate) for at most MAX_STEPS steps, then lands on top of that column.
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
## made at L and at its predecessor on the path can change (a path moves strictly downhill, so
## it never doubles back), so each cell re-walks just the tail of the path. The result equals
## walking every cell from the impact column.
static func plan(terrain: Terrain, start: int, volume: int) -> PackedInt32Array:
	var cols: PackedInt32Array = PackedInt32Array()
	if start < 0 or start >= terrain.width or volume <= 0:
		return cols
	var cache := SurfaceCache.new(terrain)
	var path_x: PackedInt32Array = PackedInt32Array([start])
	var path_pref: PackedInt32Array = PackedInt32Array([0])  # prefer-right flag before each decision
	for _k: int in range(volume):
		var i: int = maxi(0, path_x.size() - 2)
		path_x.resize(i + 1)
		path_pref.resize(i + 1)
		var c: int = path_x[i]
		var pref: int = path_pref[i]
		while i < MAX_STEPS:
			var d: int = cache.pick_dir(c, pref == 1)
			if d == 0:
				break
			if cache.tied:
				pref = 1 - pref
			c += d
			i += 1
			path_x.append(c)
			path_pref.append(pref)
		if cache.top(c) <= 0:
			continue  # column full to the top of the map: this cell is lost
		cols.append(c)
		cache.bump(c)
	return cols
