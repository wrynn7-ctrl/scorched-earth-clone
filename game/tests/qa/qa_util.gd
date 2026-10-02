@warning_ignore_start("integer_division")
extends RefCounted
## Shared QA helpers (not a test file). Load with
## `const QaUtil = preload("res://tests/qa/qa_util.gd")`.
##
## Holds: the seeded test bot, scenario runner/recorder for golden fixtures, event-contract
## field table (docs/ARCHITECTURE.md section 10) and state invariants.

const FIXTURE_DIR: String = "res://tests/qa/fixtures/"
const REGEN_ENV: String = "QA_REGEN_GOLDEN"
const WEAPON: String = "pulse_missile"
const FALLBACK_WEAPON: String = "spark_dart"

const VALID_PHASES: Array[String] = ["shop", "aim", "round_over", "match_over"]

## Exact field table per event type, section 10 (every event also has "type" and "tick").
const EVENT_FIELDS: Dictionary = {
	"fire": {"tank": TYPE_INT, "angle": TYPE_INT, "power": TYPE_INT, "weapon": TYPE_STRING},
	"projectile": {"id": TYPE_INT, "weapon": TYPE_STRING, "path": TYPE_PACKED_INT32_ARRAY},
	"projectile_end": {"id": TYPE_INT, "reason": TYPE_STRING, "x": TYPE_INT, "y": TYPE_INT},
	"explosion": {"x": TYPE_INT, "y": TYPE_INT, "radius": TYPE_INT, "weapon": TYPE_STRING},
	"terrain_carve": {"x": TYPE_INT, "y": TYPE_INT, "radius": TYPE_INT},
	"terrain_settle": {"x0": TYPE_INT, "x1": TYPE_INT, "falls": TYPE_ARRAY},
	"damage": {"tank": TYPE_INT, "amount": TYPE_INT, "health": TYPE_INT, "cause": TYPE_STRING},
	"tank_fall": {"tank": TYPE_INT, "from_y": TYPE_INT, "to_y": TYPE_INT},
	"tank_destroyed": {"tank": TYPE_INT},
	"wind": {"wind": TYPE_INT},
	"turn": {"tank": TYPE_INT},
	"round_end": {"winner": TYPE_INT},
	# M3 (sections 18-20)
	"money": {"tank": TYPE_INT, "delta": TYPE_INT, "money": TYPE_INT, "reason": TYPE_STRING},
	"shield_hit": {"tank": TYPE_INT, "absorbed": TYPE_INT, "hp": TYPE_INT},
	"shield_down": {"tank": TYPE_INT},
	"shield_on": {"tank": TYPE_INT, "item": TYPE_STRING, "hp": TYPE_INT},
	"repulsor_on": {"tank": TYPE_INT, "charge": TYPE_INT},
	"repulsor_down": {"tank": TYPE_INT},
	"chute": {"tank": TYPE_INT},
	"repair": {"tank": TYPE_INT, "amount": TYPE_INT, "health": TYPE_INT},
	"tank_move": {"tank": TYPE_INT, "from_x": TYPE_INT, "to_x": TYPE_INT, "fuel": TYPE_INT},
	"ready": {"tank": TYPE_INT},
	"well_off": {"owner": TYPE_INT},
	# M3-C2 weapon behaviours (section 21)
	"tunnel": {"x0": TYPE_INT, "y0": TYPE_INT, "x1": TYPE_INT, "y1": TYPE_INT, "radius": TYPE_INT},
	"terrain_add": {"x": TYPE_INT, "y": TYPE_INT, "radius": TYPE_INT, "material": TYPE_INT,
			"skip": TYPE_PACKED_INT32_ARRAY},
	"terrain_pour": {"x": TYPE_INT, "cells": TYPE_PACKED_INT32_ARRAY, "material": TYPE_INT},
	"flames": {"points": TYPE_PACKED_INT32_ARRAY},
	"beam": {"x0": TYPE_INT, "y0": TYPE_INT, "x1": TYPE_INT, "y1": TYPE_INT},
	"well_on": {"owner": TYPE_INT, "x": TYPE_INT, "y": TYPE_INT, "expires_turn": TYPE_INT},
	"tank_drag": {"tank": TYPE_INT, "from_x": TYPE_INT, "to_x": TYPE_INT},
	# Not in the section 10 table: only emitted by Simulation.start_round().
	"round_start": {"round": TYPE_INT},
}


static func settings(seed_value: int, tanks: int, rounds: int = 1, wind_max: int = SimConstants.WIND_MAX) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = tanks
	s.rounds = rounds
	s.wind_max = wind_max
	return s


static func fire(tank: int, angle: int, power: int) -> Dictionary:
	return {"kind": "fire", "tank": tank, "angle": angle, "power": power, "weapon": WEAPON}


## Like fire(), but with the Spark Dart when the tank has no Pulse Missile left (every fire
## action needs stock except the Spark Dart, section 19).
static func fire_for(state: MatchState, tank: int, angle: int, power: int) -> Dictionary:
	var a: Dictionary = fire(tank, angle, power)
	if state.tanks[tank].stock_of(WEAPON) <= 0:
		a["weapon"] = FALLBACK_WEAPON
	return a


## Shop phase for the bots: every tank buys as many Pulse Missile bundles as it can afford
## (capped by the inventory limit) through real `buy` actions, then submits `ready`.
## Returns all events.
static func shop_and_ready(state: MatchState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var def: Dictionary = WeaponDefs.get_def(WEAPON)
	var price: int = def["price"]
	var bundle: int = def["bundle"]
	for t: TankState in state.tanks:
		var qty: int = mini(t.money / price, (SimConstants.INVENTORY_CAP - t.stock_of(WEAPON)) / bundle)
		if qty >= 1:
			events.append_array(Simulation.apply_action(state, {"kind": "buy", "tank": t.id, "item": WEAPON, "qty": qty}))
		events.append_array(Simulation.apply_action(state, {"kind": "ready", "tank": t.id}))
	return events


## Shop (buy Pulse Missiles, ready) then start_round. Returns the start_round events.
static func enter_round(state: MatchState) -> Array[Dictionary]:
	shop_and_ready(state)
	return Simulation.start_round(state)


## new_match plus the first round started (what the M2 new_match used to return).
static func started_match(s: MatchSettings) -> MatchState:
	var state: MatchState = Simulation.new_match(s)
	enter_round(state)
	return state


## Flat terrain, solid from `ground_y` down (same materials as Terrain.flatten, built with
## bulk appends because per-cell GDScript loops over 1.4M cells are slow).
static func flat_terrain(ground_y: int) -> Terrain:
	var t := Terrain.new(0, SimConstants.WORLD_H)
	t.width = SimConstants.WORLD_W
	var col: PackedByteArray = PackedByteArray()
	col.resize(SimConstants.WORLD_H)
	for y: int in range(ground_y, SimConstants.WORLD_H):
		col[y] = Terrain.material_at_depth(y - ground_y)
	for x: int in range(SimConstants.WORLD_W):
		t.cells.append_array(col)
	return t


## Hand-built flat-ground match (solid from `ground_y` down), tanks at the given x positions.
static func flat_state(xs: Array[int], ground_y: int = 600, rounds: int = 3) -> MatchState:
	var s := MatchState.new()
	s.settings.seed = 1
	s.settings.num_tanks = xs.size()
	s.settings.rounds = rounds
	s.seed = 1
	s.round_index = 0
	s.terrain = flat_terrain(ground_y)
	for i: int in range(xs.size()):
		var t := TankState.new()
		t.id = i
		t.team = i
		t.color_index = i
		t.x = xs[i]
		t.y = ground_y
		t.set_stock(WEAPON, 50)
		s.tanks.append(t)
	s.wind = 0
	s.wind_rng_state = Rng.derive(1, SimConstants.TAG_WIND).get_state()
	s.current_tank = 0
	s.phase = SimConstants.PHASE_AIM
	return s


# --- seeded bot ---------------------------------------------------------------

## Valid action for the current tank (fires Pulse Missiles while in stock, else Spark Darts).
## Mostly aimed at a random living enemy (coarse power
## search through the pure Ballistics.trace), sometimes a wild shot. Uses only `rng`.
static func bot_action(state: MatchState, rng: Rng) -> Dictionary:
	var me: TankState = state.tanks[state.current_tank]
	var weapon: String = WEAPON if me.stock_of(WEAPON) > 0 else FALLBACK_WEAPON
	var targets: Array[TankState] = []
	for t: TankState in state.tanks:
		if t.alive and t.id != me.id:
			targets.append(t)
	if targets.is_empty() or rng.range_int(0, 7) == 0:
		return fire_for(state, me.id, rng.range_int(0, SimConstants.MAX_ANGLE), rng.range_int(1, SimConstants.MAX_POWER))
	var tgt: TankState = targets[rng.range_int(0, targets.size() - 1)]
	var angle: int = rng.range_int(300, 700) if tgt.x >= me.x else rng.range_int(1100, 1500)
	# Flat-ground range formula as a first guess (p^2 ~ 519 * range / sin(2a)), then 2 refinement traces.
	var dist: int = maxi(1, absi(tgt.x - me.x))
	var sin2: int = absi(FixedMath.sin10(2 * angle))
	var power: int = clampi(FixedMath.isqrt(519 * dist * FixedMath.ONE / maxi(1, sin2)), 10, SimConstants.MAX_POWER)
	for _i: int in range(2):
		var tr: Dictionary = Ballistics.trace(state, me.id, angle, power, weapon, SimConstants.WIND_USE_STATE,
				SimConstants.MAX_FLIGHT_TICKS)
		var hit: int = maxi(1, absi((tr["end_x"] as int) - me.x))
		power = clampi(FixedMath.isqrt(power * power * dist / hit), 10, SimConstants.MAX_POWER)
	power = clampi(power + rng.range_int(-15, 15), SimConstants.MIN_POWER, SimConstants.MAX_POWER)
	return fire_for(state, me.id, angle, power)


# --- event helpers ------------------------------------------------------------

static func types(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["type"])
	return out


static func find(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			out.append(e)
	return out


static func _stringify(v: Variant) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			keys.sort()
			var parts: PackedStringArray = PackedStringArray()
			for k: Variant in keys:
				parts.append("%s:%s" % [str(k), _stringify(d[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var a: Array = v
			var parts: PackedStringArray = PackedStringArray()
			for item: Variant in a:
				parts.append(_stringify(item))
			return "[" + ",".join(parts) + "]"
		TYPE_PACKED_INT32_ARRAY:
			var pa: PackedInt32Array = v
			return "p" + str(pa.size()) + _sha_hex(pa.to_byte_array(), 16)
		_:
			return str(v)


static func _sha_hex(bytes: PackedByteArray, n: int) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode().substr(0, n)


## Order- and content-sensitive digest of a whole timeline (paths included).
static func events_digest(events: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for e: Dictionary in events:
		parts.append(_stringify(e))
	return _sha_hex("\n".join(parts).to_utf8_buffer(), 16)


# --- scenarios & golden records -------------------------------------------------

static func scenarios() -> Array[Dictionary]:
	return [
		{"name": "duel_2_tanks", "seed": 1, "tanks": 2, "rounds": 1, "wind_max": 100, "bot_seed": 11, "max_actions": 80},
		{"name": "trio_3_tanks", "seed": 20241, "tanks": 3, "rounds": 1, "wind_max": 100, "bot_seed": 22, "max_actions": 80},
		{"name": "five_tanks", "seed": 777, "tanks": 5, "rounds": 1, "wind_max": 100, "bot_seed": 33, "max_actions": 120},
		{"name": "eight_tanks", "seed": 31337, "tanks": 8, "rounds": 1, "wind_max": 100, "bot_seed": 44, "max_actions": 160},
		# Seed 107 opens with wind = +100 (= wind_max); the drift keeps it near the limit.
		{"name": "max_wind_4_tanks", "seed": 107, "tanks": 4, "rounds": 1, "wind_max": 100, "bot_seed": 55, "max_actions": 100},
		{"name": "multi_round_3_tanks", "seed": 4242, "tanks": 3, "rounds": 4, "wind_max": 100, "bot_seed": 66, "max_actions": 400},
	]


static func make_settings(sc: Dictionary) -> MatchSettings:
	return settings(sc["seed"], sc["tanks"], sc["rounds"], sc["wind_max"])


## Plays one bot-chosen step and returns the step record {op, tank, angle, power, fp, ev,
## evh}. In the shop the bot buys Pulse Missiles, readies every tank and starts the round
## (op "start_round", events = the start_round timeline). Returns {} if the match is over.
static func play_bot_step(state: MatchState, rng: Rng) -> Dictionary:
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		return {}
	if state.phase == SimConstants.PHASE_SHOP:
		var ev: Array[Dictionary] = enter_round(state)
		return _record("start_round", {}, ev, state)
	var action: Dictionary = bot_action(state, rng)
	var events: Array[Dictionary] = Simulation.apply_action(state, action)
	return _record("fire", action, events, state)


static func _record(op: String, action: Dictionary, events: Array[Dictionary], state: MatchState) -> Dictionary:
	var rec: Dictionary = {"op": op}
	if op == "fire":
		rec["tank"] = action["tank"]
		rec["angle"] = action["angle"]
		rec["power"] = action["power"]
		rec["weapon"] = action["weapon"]
	rec["fp"] = Simulation.fingerprint(state)
	rec["ev"] = ",".join(types(events))
	rec["evh"] = events_digest(events)
	return rec


## Generates the golden record for a scenario by running the bot against the live simulation.
static func generate_record(sc: Dictionary) -> Dictionary:
	var state: MatchState = Simulation.new_match(make_settings(sc))
	var initial_fp: String = Simulation.fingerprint(state)
	var rng := Rng.new(sc["bot_seed"])
	var steps: Array[Dictionary] = []
	var fires: int = 0
	while fires < (sc["max_actions"] as int):
		var rec: Dictionary = play_bot_step(state, rng)
		if rec.is_empty():
			break
		if rec["op"] == "fire":
			fires += 1
		steps.append(rec)
	return {
		"scenario": sc,
		"initial_fp": initial_fp,
		"steps": steps,
		"final_phase": state.phase,
		"final_round": state.round_index,
		"final_fp": Simulation.fingerprint(state),
	}


static func fixture_path(name: String) -> String:
	return FIXTURE_DIR + name + ".json"


static func regen_enabled() -> bool:
	return OS.get_environment(REGEN_ENV) == "1"


static func save_fixture(name: String, record: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(fixture_path(name), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(record, "\t", false) + "\n")
	return true


## Returns the parsed fixture, or {} if it is missing or corrupt.
static func load_fixture(name: String) -> Dictionary:
	if not FileAccess.file_exists(fixture_path(name)):
		return {}
	var f: FileAccess = FileAccess.open(fixture_path(name), FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


## Replays a fixture's recorded actions (the bot is NOT consulted). Returns mismatch
## descriptions; an empty array means a perfect replay.
static func replay_record(record: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var sc: Dictionary = record["scenario"]
	var state: MatchState = Simulation.new_match(settings(int(sc["seed"]), int(sc["tanks"]), int(sc["rounds"]),
			int(sc["wind_max"])))
	if Simulation.fingerprint(state) != record["initial_fp"]:
		problems.append("initial fingerprint (new_match) %s != golden %s" % [Simulation.fingerprint(state), record["initial_fp"]])
		return problems
	var steps: Array = record["steps"]
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		var events: Array[Dictionary] = []
		if step["op"] == "start_round":
			events = enter_round(state)
		else:
			var action: Dictionary = fire(int(step["tank"]), int(step["angle"]), int(step["power"]))
			action["weapon"] = str(step["weapon"])
			var verr: String = Simulation.validate_action(state, action)
			if verr != "":
				problems.append("step %d: recorded action rejected with '%s'" % [i, verr])
				return problems
			events = Simulation.apply_action(state, action)
		var fp: String = Simulation.fingerprint(state)
		if fp != step["fp"]:
			problems.append("step %d (%s): fingerprint %s != golden %s" % [i, step["op"], fp, step["fp"]])
			return problems
		var ev_types: String = ",".join(types(events))
		if ev_types != step["ev"]:
			problems.append("step %d: event types differ\n  got:    %s\n  golden: %s" % [i, ev_types, step["ev"]])
			return problems
		if events_digest(events) != step["evh"]:
			problems.append("step %d: event payload digest differs (same types, different values)" % i)
			return problems
	if state.phase != record["final_phase"]:
		problems.append("final phase %s != golden %s" % [state.phase, record["final_phase"]])
	if Simulation.fingerprint(state) != record["final_fp"]:
		problems.append("final fingerprint differs")
	return problems


# --- contract checks ----------------------------------------------------------

## Field names/types of every event versus EVENT_FIELDS. Returns violations.
static func check_event_fields(events: Array[Dictionary]) -> Array[String]:
	var errs: Array[String] = []
	for e: Dictionary in events:
		if not e.has("type") or typeof(e["type"]) != TYPE_STRING:
			errs.append("event without String type: %s" % str(e))
			continue
		var type: String = e["type"]
		if not e.has("tick") or typeof(e["tick"]) != TYPE_INT:
			errs.append("%s: missing/non-int tick" % type)
		if not EVENT_FIELDS.has(type):
			errs.append("unknown event type '%s'" % type)
			continue
		var spec: Dictionary = EVENT_FIELDS[type]
		for k: String in spec:
			if not e.has(k):
				errs.append("%s: missing field '%s'" % [type, k])
			elif typeof(e[k]) != (spec[k] as int):
				errs.append("%s.%s has type %d, expected %d" % [type, k, typeof(e[k]), spec[k]])
		for k: Variant in e.keys():
			if str(k) != "type" and str(k) != "tick" and not spec.has(str(k)):
				errs.append("%s: undocumented extra field '%s'" % [type, str(k)])
	return errs


## Per-tick structure of the section 10 order; relaxed = allows tank_fall / fall-damage
## interleaving (the literal reading is checked by a dedicated test).
static func check_order(events: Array[Dictionary], literal: bool) -> Array[String]:
	var errs: Array[String] = []
	var last_rank: int = -1
	var last_tick: int = 0
	for e: Dictionary in events:
		var type: String = e["type"]
		var rank: int = -1
		match type:
			"fire": rank = 0
			"projectile": rank = 1
			"repulsor_down": rank = 1  # emitted at the tick the charge ran out, before projectile_end
			"projectile_end": rank = 2
			"explosion": rank = 3
			"terrain_carve": rank = 4
			"damage": rank = 5 if e["cause"] == "explosion" else 8
			"terrain_settle": rank = 6
			"tank_fall": rank = 7
			"chute": rank = 7
			"shield_hit": rank = 5
			"shield_down": rank = 5
			"tank_destroyed": rank = 9
			"round_end": rank = 10
			"wind": rank = 11
			"turn": rank = 12
		if type == "tank_fall" or (type == "damage" and e["cause"] == "fall"):
			rank = 7  # one combined phase: (tank_fall, damage(fall)?) pairs per tank (ARCHITECTURE §10)
		if type == "money":
			rank = maxi(last_rank, 0)  # money is emitted right after the event it pays for (section 18)
		if rank < last_rank:
			errs.append("%s (rank %d) after rank %d" % [type, rank, last_rank])
		last_rank = maxi(last_rank, rank)
		var tick: int = e["tick"]
		if tick < last_tick:
			errs.append("tick decreased at %s: %d < %d" % [type, tick, last_tick])
		last_tick = maxi(last_tick, tick)
	var ts: Array[String] = types(events)
	if ts.is_empty() or ts[0] != "fire":
		errs.append("timeline does not start with fire")
		return errs
	while ts[ts.size() - 1] == "money":
		ts.pop_back()  # round pay follows round_end
	var n: int = ts.size()
	var ends_round: bool = ts[n - 1] == "round_end"
	var ends_turn: bool = n >= 2 and ts[n - 2] == "wind" and ts[n - 1] == "turn"
	if ends_round == ends_turn:
		errs.append("timeline must end with exactly one of round_end / (wind, turn): %s" % ",".join(ts.slice(maxi(0, n - 3))))
	if ts.count("round_end") + ts.count("wind") + ts.count("turn") != (1 if ends_round else 2):
		errs.append("stray round_end/wind/turn in the middle of the timeline")
	return errs


## State invariants that must hold after every action. Returns violations.
static func check_invariants(state: MatchState, check_rest: bool = true, check_box: bool = true) -> Array[String]:
	var errs: Array[String] = []
	if not VALID_PHASES.has(state.phase):
		errs.append("invalid phase '%s'" % state.phase)
	var half: int = SimConstants.TANK_W / 2
	var placed: bool = state.terrain != null  # no terrain before the first round (shop)
	check_rest = check_rest and placed
	check_box = check_box and placed
	for t: TankState in state.tanks:
		if t.money < 0:
			errs.append("tank %d money %d below 0" % [t.id, t.money])
		if t.fuel < 0:
			errs.append("tank %d fuel %d below 0" % [t.id, t.fuel])
		if t.inventory.size() != Catalog.count():
			errs.append("tank %d inventory size %d" % [t.id, t.inventory.size()])
		for n: int in t.inventory:
			if n < 0 or n > SimConstants.INVENTORY_CAP:
				errs.append("tank %d inventory entry %d outside 0..%d" % [t.id, n, SimConstants.INVENTORY_CAP])
		if t.shield_hp < 0 or (t.shield_hp > 0) != (t.shield_type >= 0):
			errs.append("tank %d shield type %d with hp %d" % [t.id, t.shield_type, t.shield_hp])
		if t.repulsor_charge < 0:
			errs.append("tank %d repulsor charge %d" % [t.id, t.repulsor_charge])
		if t.health < 0 or t.health > SimConstants.MAX_HEALTH:
			errs.append("tank %d health %d out of [0,100]" % [t.id, t.health])
		if t.alive != (t.health > 0):
			errs.append("tank %d alive=%s but health=%d" % [t.id, str(t.alive), t.health])
		if placed and (t.x < 0 or t.x >= SimConstants.WORLD_W):
			errs.append("tank %d x=%d outside map" % [t.id, t.x])
		if check_box and (t.x - half < 0 or t.x + half > SimConstants.WORLD_W):
			errs.append("tank %d hit box [%d,%d) leaves the map" % [t.id, t.x - half, t.x + half])
		if placed and (t.y < 0 or t.y > SimConstants.WORLD_H):
			errs.append("tank %d y=%d outside map" % [t.id, t.y])
		if t.angle < 0 or t.angle > SimConstants.MAX_ANGLE:
			errs.append("tank %d angle %d" % [t.id, t.angle])
		if t.power < SimConstants.MIN_POWER or t.power > SimConstants.MAX_POWER:
			errs.append("tank %d power %d" % [t.id, t.power])
		if check_rest and t.alive and t.y != TankState.rest_y(state.terrain, t.x):
			errs.append("tank %d y=%d but rest_y=%d" % [t.id, t.y, TankState.rest_y(state.terrain, t.x)])
	if state.phase == SimConstants.PHASE_AIM:
		if state.current_tank < 0 or state.current_tank >= state.tanks.size():
			errs.append("current_tank %d out of range" % state.current_tank)
		elif not state.tanks[state.current_tank].alive:
			errs.append("current_tank %d is dead during aim" % state.current_tank)
	if absi(state.wind) > state.settings.wind_max:
		errs.append("wind %d exceeds wind_max %d" % [state.wind, state.settings.wind_max])
	return errs


static func alive_count(state: MatchState) -> int:
	var n: int = 0
	for t: TankState in state.tanks:
		if t.alive:
			n += 1
	return n


## Cheap whole-state signature for "nothing changed" checks (not a stable fingerprint:
## uses hash(), only valid within one process).
static func quick_sig(state: MatchState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d|%d|%d|%d|%s|%s|%d" % [state.round_index, state.wind, state.current_tank, state.turn_number,
			state.phase, str(state.wind_rng_state), 0 if state.terrain == null else hash(state.terrain.cells)])
	for t: TankState in state.tanks:
		parts.append("%d,%d,%d,%d,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%s" % [t.id, t.x, t.y, t.health, t.angle, t.power,
				str(t.alive), t.money, t.kills, t.damage_dealt, t.round_wins, t.fuel, t.shield_hp, t.repulsor_charge,
				str(t.ready)])
		parts.append(str(t.inventory))
	parts.append(str(state.wells))
	return ";".join(parts)


## True if any solid terrain cell lies inside the tank's hit box.
static func tank_embedded(state: MatchState, t: TankState) -> bool:
	for cx: int in range(t.x - SimConstants.TANK_W / 2, t.x + SimConstants.TANK_W / 2):
		for cy: int in range(t.y - SimConstants.TANK_H, t.y):
			if cy < SimConstants.WORLD_H and state.terrain.is_solid(cx, cy):
				return true
	return false
