@warning_ignore_start("integer_division")
class_name Damage
extends RefCounted
## Explosion damage (docs/ARCHITECTURE.md section 11).


## Integer distance (isqrt of the squared distance) from (cx, cy) to the closest cell of
## the tank's hit box. 0 if the point is inside the box.
static func distance_to_tank(cx: int, cy: int, tank: TankState) -> int:
	var half: int = SimConstants.TANK_W / 2
	var nx: int = clampi(cx, tank.x - half, tank.x + half - 1)
	var ny: int = clampi(cy, tank.y - SimConstants.TANK_H, tank.y - 1)
	var dx: int = cx - nx
	var dy: int = cy - ny
	return FixedMath.isqrt(dx * dx + dy * dy)


## Damage for distance d: D * (r - d) / r, at least 1 when d < r, else 0.
static func amount(d: int, r: int, max_damage: int) -> int:
	if r <= 0 or d >= r:
		return 0
	return maxi(1, max_damage * (r - d) / r)


## Damage to each alive tank, in tank id order: [{tank, amount}, ...] (amount > 0 only).
## Does not modify the state.
static func compute(state: MatchState, cx: int, cy: int, r: int, max_damage: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		var amt: int = amount(distance_to_tank(cx, cy, t), r, max_damage)
		if amt > 0:
			out.append({"tank": t.id, "amount": amt})
	return out
