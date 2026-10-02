@warning_ignore_start("integer_division")
class_name TankState
extends RefCounted
## One tank. x, y are cells; y is the ground line the tank rests on (hit box is
## x in [x-12, x+12), y in [y-12, y)).

var id: int = 0
var team: int = 0
var x: int = 0
var y: int = 0
var health: int = SimConstants.MAX_HEALTH
var angle: int = SimConstants.DEFAULT_ANGLE_LEFT
var power: int = SimConstants.DEFAULT_POWER
var alive: bool = true
var color_index: int = 0


## Tanks rest on the highest surface point under their width.
static func rest_y(terrain: Terrain, tx: int) -> int:
	var best: int = terrain.height
	var half: int = SimConstants.TANK_W / 2
	for c: int in range(tx - half, tx + half):
		best = mini(best, terrain.surface_y(c))
	return best


## True if the cell (cx, cy) lies inside this tank's hit box.
func contains_cell(cx: int, cy: int) -> bool:
	var half: int = SimConstants.TANK_W / 2
	return cx >= x - half and cx < x + half and cy >= y - SimConstants.TANK_H and cy < y


func duplicate_tank() -> TankState:
	var t := TankState.new()
	t.id = id
	t.team = team
	t.x = x
	t.y = y
	t.health = health
	t.angle = angle
	t.power = power
	t.alive = alive
	t.color_index = color_index
	return t
