@warning_ignore_start("integer_division")
class_name SurfaceCache
extends RefCounted
## Lazy per-column surface heights (first solid y) of one terrain plus the "walk downhill"
## flow rule shared by the roller, the sludge and the fire weapons (docs/ARCHITECTURE.md
## section 21).
## Scanning a column costs ~25 us, so every behaviour keeps one cache for its whole run and
## calls bump() when it adds a cell on top of a column.

const LOOKAHEAD: int = 8

var terrain: Terrain
var _top: PackedInt32Array = PackedInt32Array()


func _init(t: Terrain) -> void:
	terrain = t
	_top.resize(t.width)
	_top.fill(-1)


## Surface y of column x (`height` for an empty column).
func top(x: int) -> int:
	var v: int = _top[x]
	if v < 0:
		v = terrain.surface_y(x)
		_top[x] = v
	return v


## Records one cell added on top of column x.
func bump(x: int) -> void:
	_top[x] = top(x) - 1


## Next step (-1 left, 0 stop, +1 right) of something flowing over the surface, currently at
## column x and moving in direction `dir` (0 = it has not moved yet):
##  1. a neighbour column that is strictly lower (greater surface y) wins, the lower of the two
##     if both are; equally low neighbours alternate by column parity (left on even columns);
##  2. else it keeps going in `dir` over level ground (equal surface height);
##  3. else it stops. A thing that has not moved yet (`dir` 0) starts on level ground only
##     if `level_start` is set (then the same parity rule picks the side), or if the level
##     stretch ends in a drop within LOOKAHEAD columns (it rolls off the ledge).
## Out-of-map neighbours do not exist (the map walls stop the flow). A flow only ever moves one
## way, so it never visits a column twice.
func flow_dir(x: int, dir: int, level_start: bool) -> int:
	var h: int = top(x)
	var has_l: bool = x > 0
	var has_r: bool = x < terrain.width - 1
	var hl: int = top(x - 1) if has_l else h
	var hr: int = top(x + 1) if has_r else h
	var left_low: bool = has_l and hl > h
	var right_low: bool = has_r and hr > h
	if left_low and right_low:
		if hl > hr:
			return -1
		if hr > hl:
			return 1
		return -1 if x % 2 == 0 else 1
	if left_low:
		return -1
	if right_low:
		return 1
	if dir != 0:
		var ahead_level: bool = (has_l and hl == h) if dir < 0 else (has_r and hr == h)
		return dir if ahead_level else 0
	if not level_start:
		var left_drop: bool = has_l and hl == h and _level_run_ends_in_drop(x, -1)
		var right_drop: bool = has_r and hr == h and _level_run_ends_in_drop(x, 1)
		if left_drop and right_drop:
			return -1 if x % 2 == 0 else 1
		if left_drop:
			return -1
		return 1 if right_drop else 0
	var left_level: bool = has_l and hl == h
	var right_level: bool = has_r and hr == h
	if left_level and right_level:
		return -1 if x % 2 == 0 else 1
	if left_level:
		return -1
	if right_level:
		return 1
	return 0


## True if the level stretch starting next to column x in direction `d` ends, within
## LOOKAHEAD columns, at a strictly lower column.
func _level_run_ends_in_drop(x: int, d: int) -> bool:
	var h: int = top(x)
	var c: int = x + d
	for _i: int in range(LOOKAHEAD):
		if c < 0 or c >= terrain.width:
			return false
		var hc: int = top(c)
		if hc > h:
			return true
		if hc < h:
			return false
		c += d
	return false
