class_name NameTagLayout
extends RefCounted
## Picks a row for every tank's name tag so neighbouring tags never overlap (ARCHITECTURE section 42).
## Tanks stand only 3/5 of a lane apart in the worst case (8 players: 124 world units) while a tag with a team
## badge can be about 195 units wide, so a tag whose neighbour is too close is lifted one row, then another.
## Pure and cheap (a handful of tanks); the battle recomputes it only when a tank moved or a tag changed.

## Empty space kept between two tags on the same row, world units.
const GAP: float = 6.0
const MAX_ROWS: int = 3


## Row (0 = the normal height, 1 = one step up, ...) per tank. `xs` and `widths` are world units, one entry per
## tank; a width of 0 means "no tag" and takes no room. Tanks are served left to right and each takes the lowest
## row where it clears every tag already placed there; with no free row it takes the row where it overlaps least.
static func rows(xs: PackedFloat32Array, widths: PackedFloat32Array) -> PackedInt32Array:
	var n: int = mini(xs.size(), widths.size())
	var out := PackedInt32Array()
	out.resize(n)
	var order: Array[int] = []
	for i: int in range(n):
		if widths[i] > 0.0:
			order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return xs[a] < xs[b] or (xs[a] == xs[b] and a < b))
	var placed: Array[int] = []
	for i: int in order:
		var best_row: int = 0
		var best_slack: float = -INF
		for row: int in range(MAX_ROWS):
			var slack: float = INF
			for j: int in placed:
				if out[j] == row:
					slack = minf(slack, absf(xs[i] - xs[j]) - (widths[i] + widths[j]) * 0.5 - GAP)
			if slack >= 0.0:
				best_row = row
				break
			if slack > best_slack:
				best_slack = slack
				best_row = row
		out[i] = best_row
		placed.append(i)
	return out
