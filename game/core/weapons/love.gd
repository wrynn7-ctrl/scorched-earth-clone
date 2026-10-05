@warning_ignore_start("integer_division")
class_name LoveBehavior
extends RefCounted
## Heart (docs/ARCHITECTURE.md section 37). Normal flight; on a terrain/tank/shield impact there
## is no terrain change and no damage. Every alive tank other than the shooter within `r` gains
## love with the section 11 falloff (`amount` at the centre, at least 1), capped at LOVE_MAX.
## Events: `heart_burst`, then `love` per tank in id order; a full meter ends the match with
## `round_end {winner = shooter, winner_team = its team}` (the phase becomes "match_over"; Simulation then skips the
## turn change). A lost or timed-out shell emits no burst.


static func resolve(state: MatchState, tank_id: int, action: Dictionary, def: Dictionary,
		events: Array[Dictionary]) -> int:
	var tr: Dictionary = WeaponResolver.fly(state, tank_id, action, events)
	var tick: int = tr["ticks"]
	if not WeaponResolver.is_impact(tr["end_reason"]):
		return tick
	var ex: int = tr["end_x"]
	var ey: int = tr["end_y"]
	var radius: int = def["r"]
	events.append({"type": "heart_burst", "tick": tick, "x": ex, "y": ey, "radius": radius})
	var full: bool = false
	for t: TankState in state.tanks:
		if not t.alive or t.id == tank_id:
			continue
		var amt: int = Damage.amount(Damage.distance_to_tank(ex, ey, t), radius, def["amount"])
		var gained: int = mini(amt, SimConstants.LOVE_MAX - t.love)
		if gained <= 0:
			continue
		t.love += gained
		events.append({"type": "love", "tick": tick, "tank": t.id, "amount": gained, "love": t.love,
				"from": tank_id})
		full = full or t.love >= SimConstants.LOVE_MAX
	if full:
		# The shooter wins; round_wins keeps Simulation.standings consistent with the winner.
		state.tanks[tank_id].round_wins += 1
		events.append({"type": "round_end", "tick": tick, "winner": tank_id,
				"winner_team": state.tanks[tank_id].team})
		state.phase = SimConstants.PHASE_MATCH_OVER
	return tick
