@warning_ignore_start("integer_division")
class_name Simulation
extends RefCounted
## Rules entry point. Only this class mutates MatchState (docs/ARCHITECTURE.md sections 9-14
## and 16-24).

const AIM_KINDS: Array[String] = ["fire", "move", "use_item", "pass"]
const SHOP_KINDS: Array[String] = ["buy", "sell", "ready"]


# --- match & rounds --------------------------------------------------------------------

## Creates a match in the shop (round_index -1, no terrain yet). Settings are clamped
## (section 23); the clamped values are stored.
static func new_match(settings: MatchSettings) -> MatchState:
	var state := MatchState.new()
	state.settings = settings.clamped()
	state.seed = settings.seed
	state.round_index = -1
	state.phase = SimConstants.PHASE_SHOP
	for i: int in range(state.settings.num_tanks):
		var t := TankState.new()
		t.id = i
		t.team = i
		t.color_index = i
		t.money = state.settings.start_money
		state.tanks.append(t)
	return state


## True when `state` is in the shop and every tank has submitted `ready`.
static func all_ready(state: MatchState) -> bool:
	if state.phase != SimConstants.PHASE_SHOP:
		return false
	for t: TankState in state.tanks:
		if not t.ready:
			return false
	return true


## Starts the next round. Valid only in "shop" with every tank ready; otherwise returns [].
## Returns [round_start, wind, turn].
static func start_round(state: MatchState) -> Array[Dictionary]:
	if not all_ready(state) or state.round_index + 1 >= state.settings.rounds:
		return []
	for t: TankState in state.tanks:
		t.ready = false
	return _begin_round(state)


static func _begin_round(state: MatchState) -> Array[Dictionary]:
	state.round_index += 1
	var r: int = state.round_index
	var n: int = state.tanks.size()
	state.terrain = Terrain.generate(SimConstants.WORLD_W, SimConstants.WORLD_H,
			Rng.derive(state.seed, SimConstants.TAG_TERRAIN + r))
	_place_tanks(state, n, Rng.derive(state.seed, SimConstants.TAG_PLACEMENT + r))
	var wind_rng: Rng = Rng.derive(state.seed, SimConstants.TAG_WIND + r)
	var wm: int = state.settings.wind_max
	state.wind = wind_rng.range_int(-wm, wm)
	state.wind_rng_state = wind_rng.get_state()
	state.wells.clear()
	state.current_tank = r % n
	state.turn_number = 0
	state.phase = SimConstants.PHASE_AIM
	var events: Array[Dictionary] = []
	events.append({"type": "round_start", "tick": 0, "round": r})
	events.append({"type": "wind", "tick": 0, "wind": state.wind})
	events.append({"type": "turn", "tick": 0, "tank": state.current_tank})
	return events


## n equal segments; one tank per segment at its centre +- seg/5, on a flattened pad.
## Round-scoped state is reset; money, stock, fuel and score are kept.
static func _place_tanks(state: MatchState, n: int, rng: Rng) -> void:
	var terrain: Terrain = state.terrain
	var seg: int = terrain.width / n
	var half_pad: int = (SimConstants.TANK_W + 4) / 2
	for i: int in range(n):
		var cx: int = i * seg + seg / 2 + rng.range_int(-seg / 5, seg / 5)
		var sy: int = terrain.surface_y(cx)
		terrain.flatten(cx - half_pad, cx + half_pad - 1, sy)
		var t: TankState = state.tanks[i]
		t.x = cx
		t.y = TankState.rest_y(terrain, cx)
		t.health = SimConstants.MAX_HEALTH
		t.alive = true
		t.angle = SimConstants.DEFAULT_ANGLE_LEFT if cx < terrain.width / 2 else SimConstants.DEFAULT_ANGLE_RIGHT
		t.power = SimConstants.DEFAULT_POWER
		t.shield_type = -1
		t.shield_hp = 0
		t.repulsor_charge = 0
		t.ready = false


## Tank ids, best first (section 18).
static func standings(state: MatchState) -> Array[int]:
	return Economy.standings(state)


# --- actions ---------------------------------------------------------------------------

## Converts whole-number floats (as JSON parsing produces, e.g. 452.0) to ints and leaves
## everything else untouched. Returns a new Dictionary.
static func normalize_action(a: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in a.keys():
		var v: Variant = a[key]
		if typeof(v) == TYPE_FLOAT:
			var i: int = int(v)
			if v == i:
				v = i
		out[key] = v
	return out


static func _has_int(action: Dictionary, key: String) -> bool:
	return action.has(key) and typeof(action[key]) == TYPE_INT


static func _has_string(action: Dictionary, key: String) -> bool:
	return action.has(key) and typeof(action[key]) == TYPE_STRING


## "" if the action is legal, otherwise an error key. Never mutates state.
static func validate_action(state: MatchState, action: Dictionary) -> String:
	if not _has_string(action, "kind"):
		return "bad_action"
	var kind: String = action["kind"]
	var is_aim: bool = AIM_KINDS.has(kind)
	if not is_aim and not SHOP_KINDS.has(kind):
		return "unknown_kind"
	if state.phase != (SimConstants.PHASE_AIM if is_aim else SimConstants.PHASE_SHOP):
		return "bad_phase"
	if not _has_int(action, "tank"):
		return "bad_field"
	var field_err: String = _check_fields(kind, action)
	if field_err != "":
		return field_err
	var tank_id: int = action["tank"]
	if tank_id < 0 or tank_id >= state.tanks.size():
		return "bad_tank"
	var tank: TankState = state.tanks[tank_id]
	if is_aim:
		if tank_id != state.current_tank:
			return "not_your_turn"
		if not tank.alive:
			return "tank_dead"
	match kind:
		"fire":
			return _validate_fire(tank, action)
		"move":
			return _validate_move(tank, action)
		"use_item":
			return _validate_use_item(tank, action)
		"buy":
			return _validate_buy(state, tank, action)
		"sell":
			return _validate_sell(tank, action)
		"ready":
			return "already_ready" if tank.ready else ""
	return ""


## Type check of the per-kind fields (bad_field), before any range check.
static func _check_fields(kind: String, action: Dictionary) -> String:
	var ints: Array[String] = []
	var strings: Array[String] = []
	match kind:
		"fire":
			ints = ["angle", "power"]
			strings = ["weapon"]
		"move":
			ints = ["dx"]
		"use_item":
			strings = ["item"]
		"buy", "sell":
			ints = ["qty"]
			strings = ["item"]
	for key: String in ints:
		if not _has_int(action, key):
			return "bad_field"
	for key: String in strings:
		if not _has_string(action, key):
			return "bad_field"
	return ""


static func _validate_fire(tank: TankState, action: Dictionary) -> String:
	var angle: int = action["angle"]
	if angle < 0 or angle > SimConstants.MAX_ANGLE:
		return "bad_angle"
	var power: int = action["power"]
	if power < SimConstants.MIN_POWER or power > SimConstants.MAX_POWER:
		return "bad_power"
	var weapon: String = action["weapon"]
	if not WeaponDefs.has(weapon):
		return "unknown_weapon"
	var unlimited: bool = WeaponDefs.get_def(weapon).get("unlimited", false)
	if not unlimited and tank.stock_of(weapon) <= 0:
		return "out_of_stock"
	return ""


static func _validate_move(tank: TankState, action: Dictionary) -> String:
	var dx: int = action["dx"]
	if dx == 0 or absi(dx) > SimConstants.MOVE_MAX_DX:
		return "bad_field"
	if tank.fuel <= 0 and tank.stock_of("fuel_cell") <= 0:
		return "no_fuel"
	return ""


static func _validate_use_item(tank: TankState, action: Dictionary) -> String:
	var item: String = action["item"]
	if not Catalog.has(item):
		return "unknown_item"
	if not ItemDefs.has(item):
		return "not_usable"
	var behavior: String = ItemDefs.get_def(item)["behavior"]
	if behavior != "shield" and behavior != "repulsor" and behavior != "repair":
		return "not_usable"
	if tank.stock_of(item) <= 0:
		return "out_of_stock"
	return ""


static func _validate_buy(state: MatchState, tank: TankState, action: Dictionary) -> String:
	var item: String = action["item"]
	var qty: int = action["qty"]
	if qty < 1:
		return "bad_field"
	if not Catalog.has(item):
		return "unknown_item"
	var def: Dictionary = Catalog.get_def(item)
	var unlimited: bool = def.get("unlimited", false)
	if unlimited:
		return "not_buyable"
	if def["tier"] == "full" and not state.settings.full_unlocked:
		return "locked_item"
	# qty > cap is over the cap whatever the bundle size (also keeps the maths overflow-free).
	if qty > SimConstants.INVENTORY_CAP or tank.stock_of(item) + Economy.buy_units(def, qty) > SimConstants.INVENTORY_CAP:
		return "inventory_full"
	if Economy.buy_cost(def, qty) > tank.money:
		return "no_money"
	return ""


static func _validate_sell(tank: TankState, action: Dictionary) -> String:
	var item: String = action["item"]
	var qty: int = action["qty"]
	if qty < 1:
		return "bad_field"
	if not Catalog.has(item):
		return "unknown_item"
	if tank.stock_of(item) <= 0:
		return "out_of_stock"
	return ""


## Applies a legal action and returns the Timeline. Illegal actions change nothing and
## return [].
static func apply_action(state: MatchState, action: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if validate_action(state, action) != "":
		return events
	var kind: String = action["kind"]
	match kind:
		"fire":
			_apply_fire(state, action, events)
		"move":
			_apply_move(state, action, events)
		"use_item":
			_apply_use_item(state, action, events)
		"pass":
			_finish_turn(state, 0, events)
		"buy":
			_apply_buy(state, action, events)
		"sell":
			_apply_sell(state, action, events)
		"ready":
			_apply_ready(state, action, events)
	return events


static func _apply_fire(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var tick: int = WeaponResolver.resolve(state, tank_id, action, events)
	_finish_turn(state, tick, events)


# --- shop ---------------------------------------------------------------------------------

static func _apply_buy(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var item: String = action["item"]
	var qty: int = action["qty"]
	var def: Dictionary = Catalog.get_def(item)
	var t: TankState = state.tanks[tank_id]
	t.inventory[Catalog.index_of(item)] += Economy.buy_units(def, qty)
	Economy.add_money(state, tank_id, -Economy.buy_cost(def, qty), "buy", 0, events)


static func _apply_sell(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var item: String = action["item"]
	var qty: int = action["qty"]
	var def: Dictionary = Catalog.get_def(item)
	var t: TankState = state.tanks[tank_id]
	var idx: int = Catalog.index_of(item)
	var owned: int = t.inventory[idx]
	var units: int = mini(qty, owned)
	t.inventory[idx] = owned - units
	Economy.add_money(state, tank_id, Economy.sell_refund(def, units, owned), "sell", 0, events)


static func _apply_ready(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	state.tanks[tank_id].ready = true
	events.append({"type": "ready", "tick": 0, "tank": tank_id})


# --- movement & items -----------------------------------------------------------------------

## Walks the tank |dx| cells (section 20). The tank keeps the turn.
static func _apply_move(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var dx: int = action["dx"]
	var dir: int = 1 if dx > 0 else -1
	var t: TankState = state.tanks[tank_id]
	var terrain: Terrain = state.terrain
	var half: int = SimConstants.TANK_W / 2
	var from_x: int = t.x
	var fall_runs: Array[Vector2i] = []  # (from_y, to_y) of each fall
	var run_from: int = -1
	var cell_idx: int = Catalog.index_of("fuel_cell")
	for _i: int in range(absi(dx)):
		var nx: int = t.x + dir
		if nx - half < 0 or nx + half > terrain.width or _blocked_by_tank(state, t, nx):
			break
		var ny: int = TankState.rest_y(terrain, nx)
		if t.y - ny > SimConstants.MAX_CLIMB:
			break
		if t.fuel <= 0:
			if t.inventory[cell_idx] <= 0:
				break
			t.inventory[cell_idx] -= 1
			t.fuel += ItemDefs.get_def("fuel_cell")["amount"] as int
		t.fuel -= 1
		t.x = nx
		if ny - t.y > SimConstants.WALK_DROP:
			if run_from < 0:
				run_from = t.y
		elif run_from >= 0:
			fall_runs.append(Vector2i(run_from, t.y))
			run_from = -1
		t.y = ny
	if run_from >= 0:
		fall_runs.append(Vector2i(run_from, t.y))
	events.append({"type": "tank_move", "tick": 0, "tank": tank_id, "from_x": from_x, "to_x": t.x, "fuel": t.fuel})
	var was_alive: Array[bool] = _alive_flags(state)
	for run: Vector2i in fall_runs:
		if not t.alive:
			break
		# Falls caused by walking are nobody's shot: no credit and no self-damage penalty.
		Settle.apply_fall(state, tank_id, run.x, run.y, -1, 0, events)
	emit_destroyed(state, was_alive, 0, events)
	if not t.alive:
		_finish_turn(state, 0, events)


## True if the tank's box at column `nx` would overlap another alive tank's box.
static func _blocked_by_tank(state: MatchState, mover: TankState, nx: int) -> bool:
	for o: TankState in state.tanks:
		if o.alive and o.id != mover.id and absi(o.x - nx) < SimConstants.TANK_W:
			return true
	return false


static func _apply_use_item(state: MatchState, action: Dictionary, events: Array[Dictionary]) -> void:
	var tank_id: int = action["tank"]
	var item: String = action["item"]
	var def: Dictionary = ItemDefs.get_def(item)
	var t: TankState = state.tanks[tank_id]
	t.inventory[Catalog.index_of(item)] -= 1
	match def["behavior"]:
		"shield":
			t.shield_type = Catalog.index_of(item)
			t.shield_hp = def["hp"]
			events.append({"type": "shield_on", "tick": 0, "tank": tank_id, "item": item, "hp": t.shield_hp})
		"repulsor":
			t.repulsor_charge = def["charge"]
			events.append({"type": "repulsor_on", "tick": 0, "tank": tank_id, "charge": t.repulsor_charge})
		"repair":
			var heal: int = def["heal"]
			var before: int = t.health
			t.health = mini(SimConstants.MAX_HEALTH, t.health + heal)
			events.append({"type": "repair", "tick": 0, "tank": tank_id, "amount": t.health - before,
					"health": t.health})
			_finish_turn(state, 0, events)


# --- damage pipeline ------------------------------------------------------------------------

## The one place damage is dealt (section 21). Shields absorb everything except cause "fall"
## (`shield_hit`, then `shield_down` at 0); the rest reduces health (`damage`, nominal
## amount after the shield). Credits use the HP actually removed: enemy +15/HP, kill +1500,
## yourself or a teammate -15/HP (never below 0 money). `attacker` -1 means nobody.
## A tank reaching 0 health is marked dead (the caller emits `tank_destroyed`).
## Returns the HP actually removed from health.
static func apply_damage(state: MatchState, attacker: int, target: int, amount: int, cause: String,
		tick: int, events: Array[Dictionary]) -> int:
	var t: TankState = state.tanks[target]
	if not t.alive or amount <= 0:
		return 0
	var remaining: int = amount
	if cause != "fall" and t.has_shield():
		var absorbed: int = mini(t.shield_hp, remaining)
		t.shield_hp -= absorbed
		remaining -= absorbed
		events.append({"type": "shield_hit", "tick": tick, "tank": target, "absorbed": absorbed, "hp": t.shield_hp})
		if t.shield_hp == 0:
			t.shield_type = -1
			events.append({"type": "shield_down", "tick": tick, "tank": target})
	if remaining <= 0:
		return 0
	var before: int = t.health
	t.health = maxi(0, t.health - remaining)
	var removed: int = before - t.health
	var killed: bool = t.health == 0
	if killed:
		t.alive = false
	events.append({"type": "damage", "tick": tick, "tank": target, "amount": remaining, "health": t.health,
			"cause": cause})
	if attacker < 0 or attacker >= state.tanks.size():
		return removed
	if state.tanks[attacker].team == t.team:
		Economy.add_money(state, attacker, -Economy.self_damage_penalty(removed), "self_damage", tick, events)
		return removed
	var a: TankState = state.tanks[attacker]
	a.damage_dealt += removed
	Economy.add_money(state, attacker, Economy.damage_credit(removed), "damage", tick, events)
	if killed:
		a.kills += 1
		Economy.add_money(state, attacker, SimConstants.KILL_BONUS, "kill", tick, events)
	return removed


static func _alive_flags(state: MatchState) -> Array[bool]:
	var flags: Array[bool] = []
	for t: TankState in state.tanks:
		flags.append(t.alive)
	return flags


## Emits `tank_destroyed` for every tank alive in `was_alive` that is dead now.
static func emit_destroyed(state: MatchState, was_alive: Array[bool], tick: int, events: Array[Dictionary]) -> void:
	for t: TankState in state.tanks:
		if was_alive[t.id] and not t.alive:
			events.append({"type": "tank_destroyed", "tick": tick, "tank": t.id})


# --- turns -----------------------------------------------------------------------------------

## round_end (+ round pay, then shop / match_over), or the next alive tank's turn plus a wind
## drift.
static func _finish_turn(state: MatchState, tick: int, events: Array[Dictionary]) -> void:
	var alive_count: int = 0
	var last_alive: int = -1
	for t: TankState in state.tanks:
		if t.alive:
			alive_count += 1
			last_alive = t.id
	if alive_count <= 1:
		events.append({"type": "round_end", "tick": tick, "winner": last_alive})
		Economy.pay_round(state, last_alive, tick, events)
		var last_round: bool = state.round_index + 1 >= state.settings.rounds
		state.phase = SimConstants.PHASE_MATCH_OVER if last_round else SimConstants.PHASE_SHOP
		return
	var n: int = state.tanks.size()
	var next: int = state.current_tank
	for step: int in range(1, n + 1):
		var cand: int = (state.current_tank + step) % n
		if state.tanks[cand].alive:
			next = cand
			break
	state.current_tank = next
	state.turn_number += 1
	_expire_wells(state, tick, events)
	var wind_rng: Rng = Rng.from_state(state.wind_rng_state)
	var wm: int = state.settings.wind_max
	state.wind = clampi(state.wind + wind_rng.range_int(-SimConstants.WIND_DRIFT, SimConstants.WIND_DRIFT), -wm, wm)
	state.wind_rng_state = wind_rng.get_state()
	events.append({"type": "wind", "tick": tick, "wind": state.wind})
	events.append({"type": "turn", "tick": tick, "tank": next})


## Removes wells with turn_number >= expires_turn (section 21), keeping owner order.
static func _expire_wells(state: MatchState, tick: int, events: Array[Dictionary]) -> void:
	var kept: Array[Dictionary] = []
	for w: Dictionary in state.wells:
		if state.turn_number >= (w["expires_turn"] as int):
			events.append({"type": "well_off", "tick": tick, "owner": w["owner"]})
		else:
			kept.append(w)
	state.wells = kept


## First 16 hex chars of SHA-256 over the fixed-order state serialization (StateSerial).
static func fingerprint(state: MatchState) -> String:
	return StateSerial.hash_hex(StateSerial.serialize(state))
