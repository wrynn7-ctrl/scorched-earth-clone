@warning_ignore_start("integer_division")
class_name Economy
extends RefCounted
## Credits, prices and standings (docs/ARCHITECTURE.md section 18). Pure helpers; every
## state change still goes through Simulation.


## Price of `qty` bundles of a catalog entry.
static func buy_cost(def: Dictionary, qty: int) -> int:
	return (def["price"] as int) * qty


## Units gained by buying `qty` bundles.
static func buy_units(def: Dictionary, qty: int) -> int:
	return (def["bundle"] as int) * qty


## Refund for selling `units` units: price * units / bundle / 2 (integer division).
## `owned` caps the units that can be sold.
static func sell_refund(def: Dictionary, units: int, owned: int) -> int:
	var n: int = mini(units, owned)
	if n <= 0:
		return 0
	return (def["price"] as int) * n / (def["bundle"] as int) / 2


## Credits for removing `hp` health from an enemy.
static func damage_credit(hp: int) -> int:
	return maxi(0, hp) * SimConstants.CREDIT_PER_HP


## Money penalty for removing `hp` health from yourself (positive number).
static func self_damage_penalty(hp: int) -> int:
	return maxi(0, hp) * SimConstants.CREDIT_PER_HP


## Adds `delta` to the tank's money (never below 0) and emits a `money` event with the
## delta that was actually applied. Nothing is emitted when the applied delta is 0.
## Returns the applied delta.
static func add_money(state: MatchState, tank_id: int, delta: int, reason: String, tick: int,
		events: Array[Dictionary]) -> int:
	var t: TankState = state.tanks[tank_id]
	var applied: int = maxi(delta, -t.money)
	if applied == 0:
		return 0
	t.money += applied
	events.append({"type": "money", "tick": tick, "tank": tank_id, "delta": applied, "money": t.money,
			"reason": reason})
	return applied


## Round pay after round_end (section 39): every living tank +1000 (survive); every tank on the
## winning team, alive or destroyed, +2500 more (win) and a round win. `winner_team` is -1 for a draw
## (nobody paid a win). Without teams a team is one tank, so this is the plain "last tank standing" rule.
## Events are emitted in tank id order, survive before win.
static func pay_round(state: MatchState, winner_team: int, tick: int, events: Array[Dictionary]) -> void:
	for t: TankState in state.tanks:
		if t.alive:
			add_money(state, t.id, SimConstants.SURVIVE_PAY, "survive", tick, events)
		if winner_team >= 0 and t.team == winner_team:
			t.round_wins += 1
			add_money(state, t.id, SimConstants.WIN_PAY, "win", tick, events)


## Tank ids, best first: most round_wins, then damage_dealt, then kills, then lower id.
static func standings(state: MatchState) -> Array[int]:
	var order: Array[int] = []
	for t: TankState in state.tanks:
		order.append(t.id)
	# Insertion sort: stable and deterministic.
	for i: int in range(1, order.size()):
		var cur: int = order[i]
		var j: int = i - 1
		while j >= 0 and _better(state.tanks[cur], state.tanks[order[j]]):
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = cur
	return order


static func _better(a: TankState, b: TankState) -> bool:
	if a.round_wins != b.round_wins:
		return a.round_wins > b.round_wins
	if a.damage_dealt != b.damage_dealt:
		return a.damage_dealt > b.damage_dealt
	if a.kills != b.kills:
		return a.kills > b.kills
	return a.id < b.id


## Team ids, best first (section 39): most round_wins (teammates share them, the highest member is
## used), then the team's summed damage_dealt, then summed kills, then the lower team id. Empty when
## the match has no teams.
static func team_standings(state: MatchState) -> Array[int]:
	var order: Array[int] = []
	if not state.settings.has_teams():
		return order
	var wins: Dictionary = {}
	var dmg: Dictionary = {}
	var kills: Dictionary = {}
	for t: TankState in state.tanks:
		if not wins.has(t.team):
			order.append(t.team)
			wins[t.team] = 0
			dmg[t.team] = 0
			kills[t.team] = 0
		wins[t.team] = maxi(wins[t.team] as int, t.round_wins)
		dmg[t.team] = (dmg[t.team] as int) + t.damage_dealt
		kills[t.team] = (kills[t.team] as int) + t.kills
	# Insertion sort: stable and deterministic. Dictionaries are only looked up, never iterated.
	for i: int in range(1, order.size()):
		var cur: int = order[i]
		var j: int = i - 1
		while j >= 0 and _team_better(cur, order[j], wins, dmg, kills):
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = cur
	return order


static func _team_better(a: int, b: int, wins: Dictionary, dmg: Dictionary, kills: Dictionary) -> bool:
	if wins[a] != wins[b]:
		return (wins[a] as int) > (wins[b] as int)
	if dmg[a] != dmg[b]:
		return (dmg[a] as int) > (dmg[b] as int)
	if kills[a] != kills[b]:
		return (kills[a] as int) > (kills[b] as int)
	return a < b
