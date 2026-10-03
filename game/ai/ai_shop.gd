@warning_ignore_start("integer_division")
class_name AiShop
extends RefCounted
## What the computer opponents buy (docs/ARCHITECTURE.md section 29):
##   Easy    40-60% of its money: Pulse Missiles up to a stock of 8-12, then a few random cheap things.
##   Normal  a simple balanced kit (missiles, a shield, a chute) out of 60-75% of its money.
##   Hard    a plan: shield first, strong weapons, chutes, a Seeker, one repair kit.
##   Expert  buys only what it needs and keeps a cash reserve; looks at what the opponents own
##           and counters it (Static Burst against shields, Photon Lance against repulsors).
## Every level first buys 1-2 Fuel Cells after a round spent out of range (_fuel_after_stalemate), and
## never holds more fuel than one walk burns (AiPlayer.OUT_OF_REACH_FUEL).
## Purchases are tried on a private copy of the state with the real validator, so every
## returned action is legal when applied in order. The list always ends with `ready`.


## A round of at least this many turns per tank counts as dragging on; LONG_ROUND_TURNS as very long.
const STALE_ROUND_TURNS: int = 10
const LONG_ROUND_TURNS: int = 25
## A last shot this far (cells) from every enemy was not an attempt that came close.
const FAR_MISS: int = 300


static func actions(state: MatchState, tank_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.phase != SimConstants.PHASE_SHOP or tank_id < 0 or tank_id >= state.tanks.size():
		return out
	if state.tanks[tank_id].ready:
		return out
	var sim: MatchState = state.duplicate_state()
	var level: int = AiProfile.level_of(state, tank_id)
	var rng: Rng = Rng.derive(state.seed, SimConstants.TAG_AI + tank_id).fork(
			900000000 + (state.round_index + 1) * 16 + tank_id)
	_fuel_after_stalemate(sim, out, tank_id)
	match level:
		SimConstants.CTRL_EASY:
			_easy(sim, out, tank_id, rng)
		SimConstants.CTRL_NORMAL:
			# A balanced kit out of 60-75% of the money; the rest stays in the bank.
			var money: int = sim.tanks[tank_id].money
			_fill(sim, out, tank_id, AiProfile.SHOP_NORMAL, money - money * rng.range_int(60, 75) / 100)
		SimConstants.CTRL_HARD:
			_fill(sim, out, tank_id, AiProfile.SHOP_HARD, 0)
		_:
			_expert(sim, out, tank_id)
	var ready: Dictionary = {"kind": "ready", "tank": tank_id}
	if Simulation.validate_action(sim, ready) == "":
		out.append(ready)
	return out


## A tank whose last round dragged on while its shots fell nowhere near an enemy buys 1 Fuel Cell (2 after
## a very long round), so it can walk closer next time. Never more fuel than one walk (200 units) can burn:
## see AiPlayer.OUT_OF_REACH_FUEL. No dice: a pure function of the state.
static func _fuel_after_stalemate(sim: MatchState, out: Array[Dictionary], tank_id: int) -> void:
	if not was_out_of_range(sim, tank_id):
		return
	var t: TankState = sim.tanks[tank_id]
	var cell: int = ItemDefs.get_def("fuel_cell")["amount"] as int
	var want: int = 2 if sim.turn_number >= LONG_ROUND_TURNS * sim.tanks.size() else 1
	while t.stock_of("fuel_cell") < want and t.fuel + (t.stock_of("fuel_cell") + 1) * cell <= AiPlayer.OUT_OF_REACH_FUEL:
		if not _try_buy(sim, out, tank_id, "fuel_cell", 1):
			break


## True if the round that just ended was long (about STALE_ROUND_TURNS own turns or more per tank) and the
## tank's last shot came down far from every other tank (or was lost off the map): it spent the round
## firing at nothing. Uses only what the state remembers (last_fire_*, turn_number).
static func was_out_of_range(state: MatchState, tank_id: int) -> bool:
	var me: TankState = state.tanks[tank_id]
	if me.last_fire_weapon < 0 or state.turn_number < STALE_ROUND_TURNS * state.tanks.size():
		return false
	if me.last_fire_x < 0:
		return true
	var nearest: int = 1 << 30
	for t: TankState in state.tanks:
		if t.id != tank_id and t.team != me.team:
			nearest = mini(nearest, absi(t.x - me.last_fire_x))
	return nearest != (1 << 30) and nearest > FAR_MISS


## Buys `qty` bundles if legal (on the private copy). True if bought.
static func _try_buy(sim: MatchState, out: Array[Dictionary], tank_id: int, item: String, qty: int) -> bool:
	if qty < 1:
		return false
	if item == "fuel_cell":
		var t: TankState = sim.tanks[tank_id]
		var cell: int = ItemDefs.get_def("fuel_cell")["amount"] as int
		if t.fuel + (t.stock_of(item) + qty) * cell > AiPlayer.OUT_OF_REACH_FUEL:
			return false
	var action: Dictionary = {"kind": "buy", "tank": tank_id, "item": item, "qty": qty}
	if Simulation.validate_action(sim, action) != "":
		return false
	Simulation.apply_action(sim, action)
	out.append(action)
	return true


## Buys towards each [id, units] of the wish list while at least `reserve` credits stay unspent.
static func _fill(sim: MatchState, out: Array[Dictionary], tank_id: int, wishes: Array, reserve: int) -> void:
	var t: TankState = sim.tanks[tank_id]
	for wish: Array in wishes:
		var id: String = wish[0]
		var want: int = wish[1]
		var def: Dictionary = Catalog.get_def(id)
		var have: int = t.stock_of(id)
		if have >= want:
			continue
		var bundle: int = def["bundle"]
		var bundles: int = (want - have + bundle - 1) / bundle
		var affordable: int = maxi(0, t.money - reserve) / maxi(1, def["price"] as int)
		_try_buy(sim, out, tank_id, id, mini(bundles, affordable))


## Easy spends 40-60% of its money, mostly on missiles: Pulse Missiles up to a stock of 8-12, a
## Hyperpulse bundle if the share allows, then one to three random cheap things out of what is
## left above a 20% reserve. It never goes into battle empty-handed (>= 3 Pulse Missiles).
static func _easy(sim: MatchState, out: Array[Dictionary], tank_id: int, rng: Rng) -> void:
	var t: TankState = sim.tanks[tank_id]
	var money: int = t.money
	var ammo_budget: int = money * rng.range_int(40, 60) / 100
	var want: int = rng.range_int(8, 12)
	var pulse: Dictionary = Catalog.get_def("pulse_missile")
	var bundle: int = pulse["bundle"]
	var bundles: int = (want - t.stock_of("pulse_missile") + bundle - 1) / bundle
	var affordable: int = ammo_budget / (pulse["price"] as int)
	if bundles > 0:
		_try_buy(sim, out, tank_id, "pulse_missile", mini(bundles, affordable))
	if t.stock_of("pulse_missile") < 3:
		_try_buy(sim, out, tank_id, "pulse_missile", 1)
	var left_in_budget: int = ammo_budget - (money - t.money)
	if t.stock_of("hyperpulse") < 3 and left_in_budget >= (Catalog.get_def("hyperpulse")["price"] as int):
		_try_buy(sim, out, tank_id, "hyperpulse", 1)
	var reserve: int = money / 5
	var pool: PackedStringArray = AiProfile.SHOP_EASY_POOL
	for _i: int in range(rng.range_int(1, 3)):
		var item: String = pool[rng.range_int(0, pool.size() - 1)]
		if t.money - (Catalog.get_def(item)["price"] as int) >= reserve:
			_try_buy(sim, out, tank_id, item, 1)


static func _expert(sim: MatchState, out: Array[Dictionary], tank_id: int) -> void:
	var reserve: int = AiProfile.EXPERT_RESERVE
	var wishes: Array = []
	for w: Array in AiProfile.SHOP_EXPERT:
		wishes.append(w)
	# Counters go right after the essentials (missiles and a shield).
	var counters: Array = _counters(sim, tank_id)
	var plan: Array = []
	for i: int in range(wishes.size()):
		plan.append(wishes[i])
		if i == 1:
			plan.append_array(counters)
	_fill(sim, out, tank_id, plan, reserve)
	# With plenty of cash left, a little something original.
	var t: TankState = sim.tanks[tank_id]
	if t.money - reserve >= 9000:
		_fill(sim, out, tank_id, [["singularity_seed", 1], ["riptide_anchor", 2]], reserve)


## Wish-list entries that answer what the opponents own.
static func _counters(sim: MatchState, tank_id: int) -> Array:
	var shields: bool = false
	var repulsors: bool = false
	var me: TankState = sim.tanks[tank_id]
	for e: TankState in AiTargets.enemies_of(sim, me):
		shields = shields or e.has_shield()
		for id: String in AiPlayer.SHIELDS:
			shields = shields or e.stock_of(id) > 0
		repulsors = repulsors or e.repulsor_charge > 0 or e.stock_of("repulsor_field") > 0
	var out: Array = []
	if shields:
		out.append(["static_burst", 2])
	if repulsors:
		out.append(["photon_lance", 2])
	return out
