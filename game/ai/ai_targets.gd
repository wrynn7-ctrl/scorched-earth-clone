@warning_ignore_start("integer_division")
class_name AiTargets
extends RefCounted
## Who the AI shoots at, per difficulty (docs/ARCHITECTURE.md section 29):
##   Easy    the nearest enemy.
##   Normal  the nearest enemy, unless somebody has just shot at us (revenge).
##   Hard    the weakest enemy (health plus shield), to finish kills.
##   Expert  the best expected payoff: credits for the damage it can really do (shields soak
##           damage without paying anything), the kill bonus, and how dangerous the enemy is.
## Ties always go to the lower tank id, so the choice is a pure function of the state.


## Alive tanks on another team than `me`, in id order.
static func enemies_of(state: MatchState, me: TankState) -> Array[TankState]:
	var out: Array[TankState] = []
	for t: TankState in state.tanks:
		if t.alive and t.team != me.team:
			out.append(t)
	return out


## Health plus whatever shield is still up.
static func hp_eff(t: TankState) -> int:
	return t.health + (t.shield_hp if t.has_shield() else 0)


static func nearest(me: TankState, list: Array[TankState]) -> TankState:
	var best: TankState = null
	var best_d: int = 0
	for t: TankState in list:
		var d: int = absi(t.x - me.x)
		if best == null or d < best_d:
			best = t
			best_d = d
	return best


## True if enemy `e` fired within the last full round of turns and its shell came down within
## `radius` cells of `me`.
static func shot_at_me(state: MatchState, me: TankState, e: TankState, radius: int) -> bool:
	if e.last_fire_weapon < 0 or e.last_fire_x < 0:
		return false
	if state.turn_number - e.last_fire_turn > 2 * state.tanks.size():
		return false
	var dx: int = e.last_fire_x - me.x
	var dy: int = e.last_fire_y - me.y
	return dx * dx + dy * dy <= radius * radius


static func recent_threat(state: MatchState, me: TankState, radius: int) -> bool:
	for e: TankState in enemies_of(state, me):
		if shot_at_me(state, me, e, radius):
			return true
	return false


## Largest direct-hit damage among the explosive weapons the tank owns (spark dart if none).
static func best_damage(me: TankState) -> int:
	var best: int = WeaponDefs.get_def("spark_dart")["dmg"]
	for id: String in ["pulse_missile", "hyperpulse", "nova_core", "supernova"]:
		if me.stock_of(id) > 0:
			best = maxi(best, WeaponDefs.get_def(id)["dmg"] as int)
	return best


## The enemy to shoot at, or null when there is none.
static func pick(state: MatchState, me: TankState, level: int) -> TankState:
	var list: Array[TankState] = enemies_of(state, me)
	if list.is_empty():
		return null
	match AiProfile.for_level(level)["target"]:
		AiProfile.TARGET_REVENGE:
			var rev: TankState = _revenge(state, me, list)
			return rev if rev != null else nearest(me, list)
		AiProfile.TARGET_WEAKEST:
			return _weakest(me, list)
		AiProfile.TARGET_VALUE:
			return _best_value(state, me, list)
	return nearest(me, list)


static func _revenge(state: MatchState, me: TankState, list: Array[TankState]) -> TankState:
	var best: TankState = null
	for e: TankState in list:
		if shot_at_me(state, me, e, 90) and (best == null or e.last_fire_turn > best.last_fire_turn):
			best = e
	return best


static func _weakest(me: TankState, list: Array[TankState]) -> TankState:
	var best: TankState = null
	for e: TankState in list:
		if best == null:
			best = e
			continue
		var he: int = hp_eff(e)
		var hb: int = hp_eff(best)
		if he < hb or (he == hb and absi(e.x - me.x) < absi(best.x - me.x)):
			best = e
	return best


static func _best_value(state: MatchState, me: TankState, list: Array[TankState]) -> TankState:
	var dmg: int = best_damage(me)
	var best: TankState = null
	var best_score: int = 0
	for e: TankState in list:
		var dist: int = absi(e.x - me.x)
		var through_shield: int = maxi(0, dmg - (e.shield_hp if e.has_shield() else 0))
		var hp_dealt: int = mini(e.health, through_shield)
		var score: int = hp_dealt * SimConstants.CREDIT_PER_HP
		if through_shield >= e.health:
			score += SimConstants.KILL_BONUS
		# Threat: a healthy, close enemy is more dangerous.
		score += e.health * maxi(0, SimConstants.WORLD_W - dist) / 160
		if shot_at_me(state, me, e, 120):
			score += 600
		# Staying on the same target keeps the miss-correction working.
		if me.last_fire_weapon >= 0 and me.last_fire_x >= 0 and _nearest_to_x(me, list, me.last_fire_x) == e.id:
			score += 400
		score -= dist / 8
		if best == null or score > best_score:
			best = e
			best_score = score
	return best


static func _nearest_to_x(_me: TankState, list: Array[TankState], x: int) -> int:
	var best_id: int = -1
	var best_d: int = 0
	for t: TankState in list:
		var d: int = absi(t.x - x)
		if best_id < 0 or d < best_d:
			best_id = t.id
			best_d = d
	return best_id


## Id of the alive tank (any team, `me` excluded) nearest to column x; -1 if none.
static func nearest_tank_to_x(state: MatchState, me: TankState, x: int) -> int:
	var best_id: int = -1
	var best_d: int = 0
	for t: TankState in state.tanks:
		if not t.alive or t.id == me.id:
			continue
		var d: int = absi(t.x - x)
		if best_id < 0 or d < best_d:
			best_id = t.id
			best_d = d
	return best_id
