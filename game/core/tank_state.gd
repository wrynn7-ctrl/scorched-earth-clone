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

# --- economy & items (section 18) ---
var money: int = 0
var kills: int = 0
var damage_dealt: int = 0
var round_wins: int = 0
var ready: bool = false
var fuel: int = SimConstants.START_FUEL
## Catalog index of the active shield, or -1.
var shield_type: int = -1
var shield_hp: int = 0
var repulsor_charge: int = 0
## Love meter 0..100 (section 37); always 0 outside love mode.
var love: int = 0
## Units owned per catalog index (spark_dart is unlimited and never stored).
var inventory: PackedInt32Array = Catalog.new_inventory()

# --- last shot (section 27): the AI's only memory, written by every successful fire ---
# Conventions (all ints; reset by start_round to -1 for weapon/x/y/turn and 0 for the rest):
#  - last_fire_weapon: catalog index of the weapon fired, -1 = none yet this round.
#  - last_fire_x/y: the cell where the main projectile ended in an impact (terrain, tank or
#    shield). -1/-1 when it was lost or timed out. A roller reports where it came to rest and a
#    tunneler its entry point. For splitters whose main shell ends at the apex ("split") the
#    FIRST child's impact is used (-1/-1 if that child was lost). A beam reports its end point
#    (the cell where it stopped; this can be just outside the map, e.g. x = -1, y = -1).
#  - last_fire_wind: state.wind when the shot was fired.
#  - last_fire_turn: state.turn_number when the shot was fired.
var last_fire_angle: int = 0
var last_fire_power: int = 0
var last_fire_weapon: int = -1
var last_fire_x: int = -1
var last_fire_y: int = -1
var last_fire_wind: int = 0
var last_fire_turn: int = -1


## Clears the last-shot record (start of a round).
func reset_last_fire() -> void:
	last_fire_angle = 0
	last_fire_power = 0
	last_fire_weapon = -1
	last_fire_x = -1
	last_fire_y = -1
	last_fire_wind = 0
	last_fire_turn = -1


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


## Units of a catalog entry owned (0 for an unknown id).
func stock_of(item_id: String) -> int:
	var idx: int = Catalog.index_of(item_id)
	if idx < 0 or idx >= inventory.size():
		return 0
	return inventory[idx]


## Sets the stock of a catalog entry (ignored for an unknown id). Setup/test helper; the
## simulation changes stock through actions.
func set_stock(item_id: String, units: int) -> void:
	var idx: int = Catalog.index_of(item_id)
	if idx >= 0 and idx < inventory.size():
		inventory[idx] = units


## True while the tank has an active shield bubble.
func has_shield() -> bool:
	return shield_type >= 0 and shield_hp > 0


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
	t.money = money
	t.kills = kills
	t.damage_dealt = damage_dealt
	t.round_wins = round_wins
	t.ready = ready
	t.fuel = fuel
	t.shield_type = shield_type
	t.shield_hp = shield_hp
	t.repulsor_charge = repulsor_charge
	t.love = love
	t.inventory = inventory.duplicate()
	t.last_fire_angle = last_fire_angle
	t.last_fire_power = last_fire_power
	t.last_fire_weapon = last_fire_weapon
	t.last_fire_x = last_fire_x
	t.last_fire_y = last_fire_y
	t.last_fire_wind = last_fire_wind
	t.last_fire_turn = last_fire_turn
	return t
