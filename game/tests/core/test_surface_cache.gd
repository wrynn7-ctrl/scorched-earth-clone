extends GutTest
## SurfaceCache: lazy surface heights and the flow rule shared by roller, sludge and fire.

const W: int = 40
const H: int = 100


## Terrain whose column x has its surface at tops[x] (solid from there down).
func _terrain(tops: Array[int]) -> Terrain:
	var t := Terrain.new(tops.size(), H)
	for x: int in range(tops.size()):
		t.flatten(x, x, tops[x])
	return t


func test_top_matches_surface_y_and_is_cached() -> void:
	var t: Terrain = _terrain([50, 60, 70, 100])
	var c := SurfaceCache.new(t)
	assert_eq([c.top(0), c.top(1), c.top(2), c.top(3)], [50, 60, 70, 100])
	t.flatten(1, 1, 10)  # the cache does not notice terrain edits...
	assert_eq(c.top(1), 60)
	c.bump(1)  # ...only its own bumps
	assert_eq(c.top(1), 59)
	assert_eq(SurfaceCache.new(t).top(1), 10)


func test_strictly_lower_neighbour_wins_and_the_lower_of_two_is_chosen() -> void:
	var t: Terrain = _terrain([50, 60, 55, 80, 55, 50])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(2, 0, true), 1, "toward the 80")
	assert_eq(c.flow_dir(2, 0, false), 1)
	assert_eq(c.flow_dir(0, 0, true), 1, "the left wall does not exist")
	assert_eq(c.flow_dir(3, 0, true), 0, "a local minimum")
	assert_eq(c.flow_dir(4, 1, true), -1, "toward the 80 on its left")
	assert_eq(c.flow_dir(4, 0, false), -1)


func test_equally_low_neighbours_alternate_by_column_parity() -> void:
	var t: Terrain = _terrain([80, 50, 80, 80, 50, 80])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(1, 0, true), 1, "odd column: right")
	assert_eq(c.flow_dir(4, 0, true), -1, "even column: left")


func test_level_ground_is_crossed_only_while_moving() -> void:
	var t: Terrain = _terrain([70, 60, 60, 60, 60, 50])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(2, 1, false), 1, "moving right over a level stretch keeps going")
	assert_eq(c.flow_dir(2, -1, false), -1)
	assert_eq(c.flow_dir(4, 1, false), 0, "a step up ahead stops it")
	assert_eq(c.flow_dir(3, 0, false), -1, "at rest it rolls off the ledge at the end of the level run (the 70 on the left is lower)")
	assert_eq(c.flow_dir(2, 0, true), -1, "the sludge does start on level ground (even column: left)")
	assert_eq(c.flow_dir(3, 0, true), 1, "(odd column: right)")


func test_walls_stop_the_flow() -> void:
	var t: Terrain = _terrain([60, 60, 60, 60])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(0, -1, true), 0, "left wall")
	assert_eq(c.flow_dir(3, 1, true), 0, "right wall")
	assert_eq(c.flow_dir(0, 0, true), 1)
	assert_eq(c.flow_dir(3, 0, true), -1)


func test_higher_neighbours_never_attract() -> void:
	var t: Terrain = _terrain([40, 60, 40])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(1, 0, true), 0)
	assert_eq(c.flow_dir(1, 1, true), 0)


func test_a_resting_thing_rolls_off_a_ledge_within_eight_columns() -> void:
	var tops: Array[int] = [60, 60, 60, 60, 70]
	for _i: int in range(15):
		tops.append(60)
	var c := SurfaceCache.new(_terrain(tops))
	assert_eq(c.flow_dir(1, 0, false), 1, "the ledge is 3 columns away on the right")
	assert_eq(c.flow_dir(0, 0, false), 1)
	assert_eq(c.flow_dir(8, 0, false), -1, "only the left side drops: the right run is flat to the wall")


func test_a_long_plateau_does_not_start_anything() -> void:
	var tops: Array[int] = [100]
	for _i: int in range(29):
		tops.append(60)
	var c := SurfaceCache.new(_terrain(tops))
	assert_eq(c.flow_dir(15, 0, false), 0, "the drop is 15 columns away")
	assert_eq(c.flow_dir(5, 0, false), -1, "but 5 columns away it is within reach")
	assert_eq(c.flow_dir(15, 0, true), 1, "the sludge starts anyway: odd column goes right")


func test_ledge_lookahead_stops_at_a_rise_and_at_the_walls() -> void:
	var t: Terrain = _terrain([60, 60, 40, 80])
	var c := SurfaceCache.new(t)
	assert_eq(c.flow_dir(0, 0, false), 0, "a rise blocks the run before the drop")
	assert_eq(c.flow_dir(1, 0, false), 0)
	var edge: Terrain = _terrain([60, 60, 60, 60])
	assert_eq(SurfaceCache.new(edge).flow_dir(1, 0, false), 0, "walls are not drops")
	var up: Terrain = _terrain([50, 60, 60, 60])
	assert_eq(SurfaceCache.new(up).flow_dir(1, 0, false), 0, "a higher neighbour and a flat run to the wall")
