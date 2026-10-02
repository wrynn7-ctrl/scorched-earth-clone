@warning_ignore_start("integer_division")
class_name SurfaceCache
extends RefCounted
## Lazy per-column surface heights (first solid y) of one terrain plus the "walk downhill"
## rule shared by the roller, the sludge and the fire weapons (docs/ARCHITECTURE.md section 21).
## Scanning a column costs ~25 us, so every behaviour keeps one cache for its whole run and
## calls bump() when it adds a cell on top of a column.

var terrain: Terrain
## Set by pick_dir(): true when both neighbours were equally low and the preference decided.
var tied: bool = false
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


## Direction (-1 left, +1 right, 0 none) of the lowest neighbouring column that is strictly
## lower than column x (greater surface y). Out-of-map neighbours do not exist. On equal
## neighbours `prefer_right` decides and `tied` is set.
func pick_dir(x: int, prefer_right: bool) -> int:
	tied = false
	var h: int = top(x)
	var hl: int = h
	var hr: int = h
	if x > 0:
		hl = top(x - 1)
	if x < terrain.width - 1:
		hr = top(x + 1)
	var left_low: bool = hl > h
	var right_low: bool = hr > h
	if left_low and right_low:
		if hl > hr:
			return -1
		if hr > hl:
			return 1
		tied = true
		return 1 if prefer_right else -1
	if left_low:
		return -1
	if right_low:
		return 1
	return 0
