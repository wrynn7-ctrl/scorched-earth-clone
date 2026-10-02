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


## Round pay after round_end: survivors +1000, the winner +2500 more (and a round win).
## Events are emitted in tank id order, survive before win.
static func pay_round(state: MatchState, winner: int, tick: int, events: Array[Dictionary]) -> void:
	for t: TankState in state.tanks:
		if not t.alive:
			continue
		add_money(state, t.id, SimConstants.SURVIVE_PAY, "survive", tick, events)
		if t.id == winner:
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
