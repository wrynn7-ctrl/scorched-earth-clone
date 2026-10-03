@warning_ignore_start("integer_division")
extends RefCounted
## M4 QA helpers for the computer opponents (not a test file). Load with
## `const QA_AI = preload("res://tests/qa/qa_ai.gd")`.
##
## Holds: the whole-match AI driver used by the validity/determinism fuzz (every action is
## validated, every timeline is audited with the M3 helpers, determinism probes run on a
## stride), scenario builders for hand-made adversarial states, and small statistics helpers.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")

## A round that lasts longer than this many turn-ending actions counts as a stalemate.
## The whole-state signature (about 1 ms with 8 tanks) is taken on every n-th decision.
const SIG_STRIDE: int = 3
const STALL_TURNS: int = 400
## Rounds this long are snapshotted for the report (near-stalemates).
const LONG_ROUND: int = 100
## Hard stop for one match (shop actions and AI calls included).
const MAX_STEPS: int = 6000
const CATEGORIES: Array[String] = ["invalid", "calls", "audit", "timeline", "state", "mutation",
		"det_copy", "det_save", "fallback", "shop", "flow"]


# --- settings --------------------------------------------------------------------------------

## Random match settings number `m` of a batch: 2-8 tanks, every controller level (some
## all-CPU matches, some with human slots that the harness hands to the AI), random money,
## wind and rounds, and about one match in five with the free version only.
static func random_settings(m: int, root_seed: int) -> MatchSettings:
	var r: Rng = Rng.derive(root_seed, 700 + m)
	var s := MatchSettings.new()
	s.seed = r.next_u32() + (m % 7) * 1000003
	s.num_tanks = r.range_int(2, 8) if m % 3 != 0 else r.range_int(2, 4)
	s.rounds = 1 + (m % 2) if s.num_tanks <= 4 else 1
	if m % 10 == 0:
		s.rounds = 3  # a few longer matches: more shop visits and carried-over stock
	s.wind_max = [100, 100, 0, 1, 37, 100][m % 6]
	s.start_money = [10000, 25000, 3000, 500, 0, 1_000_000, 10000][m % 7]
	s.full_unlocked = m % 5 != 2
	var ctrl := PackedInt32Array()
	var mode: int = m % 4  # 0 all CPU levels random, 1 mixed with humans, 2 one level for all, 3 random
	var level: int = r.range_int(1, 4)
	for _i: int in range(s.num_tanks):
		match mode:
			0:
				ctrl.append(r.range_int(1, 4))
			1:
				ctrl.append(r.range_int(0, 4))
			2:
				ctrl.append(level)
			_:
				ctrl.append(r.range_int(1, 4) if r.range_int(0, 5) != 0 else 0)
	s.controllers = ctrl
	return s


# --- fingerprint helpers -----------------------------------------------------------------------

## Full fingerprint that also works before the first round (no terrain yet). About 8 ms.
static func fp(state: MatchState) -> String:
	return Simulation.fingerprint(state)


static var _props: Dictionary = {}


## Names of the script variables of an object (its whole data, whatever fields get added later).
static func _vars(o: Object) -> PackedStringArray:
	var key: String = (o.get_script() as Script).resource_path
	if not _props.has(key):
		var names := PackedStringArray()
		for p: Dictionary in o.get_property_list():
			if (p["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				names.append(p["name"] as String)
		_props[key] = names
	return _props[key]


static func _dump(o: Object) -> String:
	var out: String = ""
	for n: String in _vars(o):
		var v: Variant = o.get(n)
		if v is Object:
			continue
		if v is PackedInt32Array or v is PackedInt64Array or v is PackedByteArray:
			out += "%s#%d;" % [n, hash(v)]
		else:
			out += "%s=%s;" % [n, str(v)]
	return out


## Cheap whole-state signature (about 0.3 ms): every script variable of the state, the settings and
## every tank, plus a hash of the terrain bytes. Unlike the fingerprint it also covers whatever the
## fingerprint might forget. Only valid inside one process.
static func sig(state: MatchState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(_dump(state))
	parts.append(_dump(state.settings))
	parts.append("terrain=%d" % (0 if state.terrain == null else hash(state.terrain.cells)))
	for t: TankState in state.tanks:
		parts.append(_dump(t))
	return "|".join(parts)


static func level_of(state: MatchState, id: int) -> int:
	return AiProfile.level_of(state, id)


# --- the match driver ---------------------------------------------------------------------------

## Plays one whole match with AiPlayer for every tank (a human slot plays as Normal, which is
## what AiProfile does for it). Returns a Dictionary:
##  fails: category -> Array[String]       (all must be empty)
##  settings, seed, turns, rounds_played, stalled (bool), stall_info (Dictionary),
##  max_calls, us_by_level: level -> Array[int] (µs per next_action call),
##  shop_us: Array[int], pass_count, fallback_count, self_hit / self_kill / fire_turns per level,
##  weapons: weapon id -> count, nonending: kind -> count, turns_per_round: Array[int],
##  final_state, log: Array[Dictionary] (every applied action, shop included).
## `det_stride`: every n-th decision also runs the determinism probes (deep copy, SaveCodec round trip,
## _decide vs next_action fallback probe); 0 = never. `mut_stride` likewise for fingerprint-before/after.
static func play_match(settings: MatchSettings, det_stride: int, mut_stride: int, save_stride: int) -> Dictionary:
	var fails: Dictionary = {}
	for c: String in CATEGORIES:
		fails[c] = [] as Array[String]
	var res: Dictionary = {"fails": fails, "settings": settings, "stalled": false, "stall_info": {},
			"turns": 0, "max_calls": 0, "us_by_level": {1: [] as Array[int], 2: [] as Array[int], 3: [] as Array[int], 4: [] as Array[int]},
			"shop_us": [] as Array[int], "pass_count": 0, "fallback_count": 0,
			"self_hit": {1: 0, 2: 0, 3: 0, 4: 0}, "self_kill": {1: 0, 2: 0, 3: 0, 4: 0}, "fire_turns": {1: 0, 2: 0, 3: 0, 4: 0},
			"weapons": {}, "nonending": {}, "turns_per_round": [] as Array[int], "rounds_played": 0, "log": [] as Array[Dictionary],
			"det_checks": 0, "save_checks": 0, "mut_checks": 0, "traces_max": 0, "steps": 0}
	var tag: String = "seed %d (%d tanks, ctrl %s, rounds %d, money %d, wind_max %d, full %s)" % [
			settings.seed, settings.num_tanks, str(settings.controllers), settings.rounds, settings.start_money,
			settings.wind_max, str(settings.full_unlocked)]
	res["tag"] = tag
	var state: MatchState = Simulation.new_match(settings)
	res["final_state"] = state
	var log: Array[Dictionary] = res["log"]
	var guard: int = 0
	var decisions: int = 0
	var round_turns: int = 0
	var last_key: int = -1
	var calls: int = 0
	var rounds_seen: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and guard < MAX_STEPS:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			_shop_phase(state, res, log, decisions, det_stride, mut_stride, tag)
			if Simulation.all_ready(state):
				var snap: Dictionary = M3.snapshot(state)
				var tr: int = Time.get_ticks_usec()
				var ev: Array[Dictionary] = Simulation.start_round(state)
				res["us_start_round"] = (res.get("us_start_round", 0) as int) + Time.get_ticks_usec() - tr
				if ev.is_empty():
					_fail(res, "flow", "%s: start_round returned no events" % tag)
					break
				_audit(res, snap, state, {"kind": M3.START_ROUND}, ev, tag)
				round_turns = 0
				last_key = -1
				rounds_seen += 1
			else:
				_fail(res, "flow", "%s: shop finished but not all tanks are ready" % tag)
				break
			continue
		if state.phase != SimConstants.PHASE_AIM:
			_fail(res, "flow", "%s: unexpected phase %s" % [tag, state.phase])
			break
		var tank: int = state.current_tank
		var key: int = state.round_index * 100000 + state.turn_number
		calls = calls + 1 if key == last_key else 1
		last_key = key
		res["max_calls"] = maxi(res["max_calls"], calls)
		if calls > 3:
			_fail(res, "calls", "%s: call %d in the same turn (round %d turn %d tank %d)" % [tag, calls, state.round_index, state.turn_number, tank])
		decisions += 1
		var level: int = level_of(state, tank)
		var tp: int = Time.get_ticks_usec()
		var action: Dictionary = _decide_checked(state, tank, level, res, decisions, det_stride, mut_stride, save_stride, log, tag)
		res["us_decide_all"] = (res.get("us_decide_all", 0) as int) + Time.get_ticks_usec() - tp
		var verr: String = Simulation.validate_action(state, action)
		if verr != "":
			_fail(res, "invalid", "%s: round %d turn %d tank %d action %s -> %s" % [tag, state.round_index, state.turn_number, tank, str(action), verr])
			break
		if action["kind"] == "pass":
			res["pass_count"] = (res["pass_count"] as int) + 1
		var snap2: Dictionary = M3.snapshot(state)
		var ta: int = Time.get_ticks_usec()
		var events: Array[Dictionary] = Simulation.apply_action(state, action)
		res["us_apply"] = (res.get("us_apply", 0) as int) + Time.get_ticks_usec() - ta
		log.append(action)
		_audit(res, snap2, state, action, events, tag)
		var kind: String = action["kind"]
		var ends: bool = kind == "fire" or kind == "pass" or (kind == "use_item" and action["item"] == "nanorepair_kit")
		if not ends:
			var nk: Dictionary = res["nonending"]
			var label: String = kind if kind != "use_item" else "use_item:%s" % action["item"]
			nk[label] = (nk.get(label, 0) as int) + 1
		else:
			res["turns"] = (res["turns"] as int) + 1
			round_turns += 1
			if round_turns == LONG_ROUND and state.phase == SimConstants.PHASE_AIM:
				var long_list: Array = res.get("long", []) as Array
				var info: Dictionary = _stall_info(state, log, round_turns)
				info["tag"] = tag
				long_list.append(info)
				res["long"] = long_list
			if state.phase != SimConstants.PHASE_AIM:
				# A record exists only if the round was still running at LONG_ROUND turns.
				if round_turns > LONG_ROUND and res.has("long"):
					((res["long"] as Array).back() as Dictionary)["final_turns"] = round_turns
				(res["turns_per_round"] as Array[int]).append(round_turns)
				res["rounds_played"] = (res["rounds_played"] as int) + 1
		if kind == "fire":
			var w: Dictionary = res["weapons"]
			w[action["weapon"]] = (w.get(action["weapon"], 0) as int) + 1
			(res["fire_turns"] as Dictionary)[level] = ((res["fire_turns"] as Dictionary)[level] as int) + 1
			_note_self_harm(res, events, tank, level, action, state)
		if round_turns > STALL_TURNS and state.phase == SimConstants.PHASE_AIM:
			res["stalled"] = true
			res["stall_info"] = _stall_info(state, log, round_turns)
			(res["turns_per_round"] as Array[int]).append(round_turns)
			break
	if guard >= MAX_STEPS:
		res["stalled"] = true
		res["stall_info"] = {"reason": "step limit"}
	res["steps"] = guard
	res["final_state"] = state
	return res


static func _fail(res: Dictionary, category: String, msg: String) -> void:
	var list: Array[String] = (res["fails"] as Dictionary)[category]
	if list.size() < 12:
		list.append(msg)
	else:
		res["more_" + category] = (res.get("more_" + category, 0) as int) + 1


static func _audit(res: Dictionary, snap: Dictionary, state: MatchState, action: Dictionary,
		events: Array[Dictionary], tag: String) -> void:
	var t0: int = Time.get_ticks_usec()
	for e: String in M3.audit(snap, state, action, events):
		_fail(res, "audit", "%s: %s: %s" % [tag, str(action), e])
	if action["kind"] != M3.START_ROUND:
		for e: String in M3.check_timeline(action, events):
			_fail(res, "timeline", "%s: %s: %s" % [tag, str(action), e])
	for e: String in M3.check_state(state):
		_fail(res, "state", "%s: after %s: %s" % [tag, str(action), e])
	res["us_audit"] = (res.get("us_audit", 0) as int) + Time.get_ticks_usec() - t0


static func _note_self_harm(res: Dictionary, events: Array[Dictionary], tank: int, level: int,
		action: Dictionary, state: MatchState) -> void:
	var hit: bool = false
	var killed: bool = false
	var amount: int = 0
	for e: Dictionary in events:
		if e["type"] == "damage" and (e["tank"] as int) == tank and e["cause"] != "fall":
			hit = true
			amount += e["amount"] as int
		if e["type"] == "tank_destroyed" and (e["tank"] as int) == tank:
			killed = true
	if hit:
		var cases: Array = res.get("self_cases", []) as Array
		var near: int = 99999
		for t: TankState in state.tanks:
			if t.id != tank:
				near = mini(near, absi(t.x - state.tanks[tank].x))
		cases.append("%s level %d %s angle %d power %d wind %d: %d dmg, nearest tank %d cells, destroyed=%s" % [
				res["tag"], level, action["weapon"], action["angle"], action["power"], state.wind, amount, near, str(killed)])
		res["self_cases"] = cases
		(res["self_hit"] as Dictionary)[level] = ((res["self_hit"] as Dictionary)[level] as int) + 1
	if killed:
		(res["self_kill"] as Dictionary)[level] = ((res["self_kill"] as Dictionary)[level] as int) + 1


static func _stall_info(state: MatchState, log: Array[Dictionary], round_turns: int) -> Dictionary:
	var alive: Array[Dictionary] = []
	for t: TankState in state.tanks:
		if t.alive:
			alive.append({"id": t.id, "level": level_of(state, t.id), "x": t.x, "y": t.y, "hp": t.health,
					"shield": t.shield_hp, "fuel": t.fuel})
	var hist: Dictionary = {}
	for i: int in range(maxi(0, log.size() - 40), log.size()):
		var a: Dictionary = log[i]
		var k: String = a["kind"] if a["kind"] != "fire" else "fire:%s" % a["weapon"]
		hist[k] = (hist.get(k, 0) as int) + 1
	return {"round": state.round_index, "round_turns": round_turns, "wind": state.wind, "alive": alive, "last40": hist,
			"wells": state.wells.size()}


## One AI decision with every probe applied: timing, "did not mutate the state", deep-copy
## determinism, SaveCodec round-trip determinism and the fallback probe.
static func _decide_checked(state: MatchState, tank: int, level: int, res: Dictionary, n: int, det_stride: int,
		mut_stride: int, save_stride: int, log: Array[Dictionary], tag: String) -> Dictionary:
	var do_sig: bool = n % SIG_STRIDE == 0
	var before: String = sig(state) if do_sig else ""
	var before_fp: String = ""
	var do_fp: bool = mut_stride > 0 and n % mut_stride == 0
	if do_fp:
		before_fp = fp(state)
	var t0: int = Time.get_ticks_usec()
	var action: Dictionary = AiPlayer.next_action(state, tank)
	var us: int = Time.get_ticks_usec() - t0
	(((res["us_by_level"] as Dictionary)[level]) as Array[int]).append(us)
	res["traces_max"] = maxi(res["traces_max"], AimSolver.trace_count)
	if do_sig or do_fp:
		res["mut_checks"] = (res["mut_checks"] as int) + 1
	if (do_sig and sig(state) != before) or (do_fp and fp(state) != before_fp):
		_fail(res, "mutation", "%s: next_action mutated the state (round %d turn %d tank %d)" % [tag, state.round_index, state.turn_number, tank])
	if det_stride > 0 and n % det_stride == 0:
		res["det_checks"] = (res["det_checks"] as int) + 1
		var copy: MatchState = state.duplicate_state()
		var again: Dictionary = AiPlayer.next_action(copy, tank)
		if again != action:
			_fail(res, "det_copy", "%s: deep copy decided differently (round %d turn %d tank %d): %s vs %s" % [tag, state.round_index, state.turn_number, tank, str(action), str(again)])
		var same: Dictionary = AiPlayer.next_action(state, tank)
		if same != action:
			_fail(res, "det_copy", "%s: second call on the same state differs: %s vs %s" % [tag, str(action), str(same)])
		# Fallback probe: the raw decision must itself be legal. next_action silently replaces an
		# illegal or empty decision with a Spark Dart shot.
		AimSolver.reset_budget()
		var raw: Dictionary = AiPlayer._decide(state, state.tanks[tank])
		var rerr: String = "empty" if raw.is_empty() else Simulation.validate_action(state, raw)
		if rerr != "":
			res["fallback_count"] = (res["fallback_count"] as int) + 1
			_fail(res, "fallback", "%s: round %d turn %d tank %d: _decide returned %s (%s), next_action fell back to %s" % [tag, state.round_index, state.turn_number, tank, str(raw), rerr, str(action)])
	if save_stride > 0 and n % save_stride == 0:
		res["save_checks"] = (res["save_checks"] as int) + 1
		var bytes: PackedByteArray = SaveCodec.encode(state, log)
		var dec: Dictionary = SaveCodec.decode(bytes)
		if not dec["ok"]:
			_fail(res, "det_save", "%s: save round trip failed: %s" % [tag, str(dec["error"])])
		else:
			var loaded: MatchState = dec["state"]
			var lfp: String = fp(loaded)
			if lfp != fp(state):
				_fail(res, "det_save", "%s: loaded state fingerprint differs" % tag)
			var after: Dictionary = AiPlayer.next_action(loaded, tank)
			if after != action:
				_fail(res, "det_save", "%s: after save/load the AI decided %s instead of %s" % [tag, str(after), str(action)])
	return action


## All the shop actions of one phase for every tank in id order, each validated, applied, audited.
static func _shop_phase(state: MatchState, res: Dictionary, log: Array[Dictionary], decisions: int,
		det_stride: int, mut_stride: int, tag: String) -> void:
	for t: TankState in state.tanks:
		res["shop_visits"] = (res.get("shop_visits", 0) as int) + 1
		var before: String = sig(state)
		var do_fp: bool = mut_stride > 0 and (res["shop_visits"] as int) % mut_stride == 0
		var before_fp: String = fp(state) if do_fp else ""
		var t0: int = Time.get_ticks_usec()
		var acts: Array[Dictionary] = AiPlayer.shop_actions(state, t.id)
		(res["shop_us"] as Array[int]).append(Time.get_ticks_usec() - t0)
		res["mut_checks"] = (res["mut_checks"] as int) + 1
		if sig(state) != before or (do_fp and fp(state) != before_fp):
			_fail(res, "mutation", "%s: shop_actions mutated the state (tank %d)" % [tag, t.id])
		if det_stride > 0 and (res["shop_visits"] as int) % det_stride == 0:
			var copy: MatchState = state.duplicate_state()
			var again: Array[Dictionary] = AiPlayer.shop_actions(copy, t.id)
			if again != acts:
				_fail(res, "det_copy", "%s: shop_actions of tank %d differ on a deep copy" % [tag, t.id])
		if t.ready:
			if not acts.is_empty():
				_fail(res, "shop", "%s: tank %d is ready but shop_actions returned %d actions" % [tag, t.id, acts.size()])
			continue
		if acts.is_empty() or acts[acts.size() - 1]["kind"] != "ready":
			_fail(res, "shop", "%s: tank %d shop list does not end with ready: %s" % [tag, t.id, str(acts)])
		for i: int in range(acts.size()):
			var a: Dictionary = acts[i]
			if a["kind"] == "ready" and i != acts.size() - 1:
				_fail(res, "shop", "%s: tank %d ready in the middle of the list" % [tag, t.id])
			if a["kind"] != "buy" and a["kind"] != "sell" and a["kind"] != "ready":
				_fail(res, "shop", "%s: tank %d shop list contains %s" % [tag, t.id, str(a)])
			if (a["tank"] as int) != t.id:
				_fail(res, "shop", "%s: tank %d shop list acts for tank %s" % [tag, t.id, str(a["tank"])])
			var err: String = Simulation.validate_action(state, a)
			if err != "":
				_fail(res, "invalid", "%s: shop action %s -> %s" % [tag, str(a), err])
				return
			if a["kind"] == "buy" and not state.settings.full_unlocked and Catalog.get_def(a["item"])["tier"] == "full":
				_fail(res, "shop", "%s: free version but tank %d buys full-tier %s" % [tag, t.id, a["item"]])
			var snap: Dictionary = M3.snapshot(state)
			var ev: Array[Dictionary] = Simulation.apply_action(state, a)
			log.append(a)
			_audit(res, snap, state, a, ev, tag)


# --- statistics -------------------------------------------------------------------------------

static func percentile(values: Array[int], p: int) -> int:
	if values.is_empty():
		return 0
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, (sorted.size() * p + 99) / 100 - 1)]


static func mean(values: Array[int]) -> int:
	if values.is_empty():
		return 0
	var s: int = 0
	for v: int in values:
		s += v
	return s / values.size()


# --- scenario builders (flat ground unless stated) -----------------------------------------------

## Flat ground, tanks at the given x positions, each CPU at the given level. Tank 0 is to act.
## Every tank gets `pulse` Pulse Missiles.
static var _flat_base: MatchState = null


static func flat(xs: Array[int], levels: Array[int], pulse: int = 20) -> MatchState:
	# Building the flat terrain column by column is slow; copy a cached 8-tank base instead.
	if _flat_base == null:
		_flat_base = SimTestUtil.flat_state(8)
	var s: MatchState = _flat_base.duplicate_state()
	while s.tanks.size() > xs.size():
		s.tanks.pop_back()
	s.settings.num_tanks = xs.size()
	var ctrl := PackedInt32Array()
	for i: int in range(xs.size()):
		s.tanks[i].x = xs[i]
		s.tanks[i].set_stock("pulse_missile", pulse)
		ctrl.append(levels[i])
	s.settings.controllers = ctrl
	s.current_tank = 0
	return s


## Calls the AI for tank `id` until the turn ends, applying each action to `state` itself.
## Returns {actions: Array[Dictionary], events: Array[Dictionary] (of the ending action), calls,
## errors: Array[String]}.
static func play_turn(state: MatchState, id: int) -> Dictionary:
	var actions: Array[Dictionary] = []
	var errors: Array[String] = []
	var events: Array[Dictionary] = []
	for call: int in range(1, 6):
		var a: Dictionary = AiPlayer.next_action(state, id)
		var err: String = Simulation.validate_action(state, a)
		if err != "":
			errors.append("call %d: %s -> %s" % [call, str(a), err])
			return {"actions": actions, "events": events, "calls": call, "errors": errors}
		actions.append(a)
		events = Simulation.apply_action(state, a)
		var kind: String = a["kind"]
		if kind == "fire" or kind == "pass" or (kind == "use_item" and a["item"] == "nanorepair_kit"):
			return {"actions": actions, "events": events, "calls": call, "errors": errors}
	errors.append("turn did not end within 5 calls")
	return {"actions": actions, "events": events, "calls": 5, "errors": errors}


## Damage the tank `id` took from explosion/burn/beam events (not falls) in a timeline.
static func damage_to(events: Array[Dictionary], id: int) -> int:
	var total: int = 0
	for e: Dictionary in events:
		if e["type"] == "damage" and (e["tank"] as int) == id and e["cause"] != "fall":
			total += e["amount"] as int
	return total


static func destroyed(events: Array[Dictionary], id: int) -> bool:
	for e: Dictionary in events:
		if e["type"] == "tank_destroyed" and (e["tank"] as int) == id:
			return true
	return false


## Fills every terrain cell of the rectangle x in [x0, x1], y in [y0, y1) with dirt (material 1).
static func fill_rect(terrain: Terrain, x0: int, x1: int, y0: int, y1: int) -> void:
	for x: int in range(maxi(0, x0), mini(terrain.width - 1, x1) + 1):
		for y: int in range(maxi(0, y0), mini(terrain.height, y1)):
			terrain.cells[x * terrain.height + y] = 1


## Clears a rectangle (x in [x0, x1], y in [y0, y1)).
static func clear_rect(terrain: Terrain, x0: int, x1: int, y0: int, y1: int) -> void:
	for x: int in range(maxi(0, x0), mini(terrain.width - 1, x1) + 1):
		for y: int in range(maxi(0, y0), mini(terrain.height, y1)):
			terrain.cells[x * terrain.height + y] = 0


## Gives a tank 99 of every catalog entry (the unlimited Spark Dart is never stored).
static func give_everything(t: TankState, units: int = SimConstants.INVENTORY_CAP) -> void:
	for id: String in Catalog.IDS:
		if id != Catalog.SPARK_DART:
			t.set_stock(id, units)


static func clear_stock(t: TankState) -> void:
	for id: String in Catalog.IDS:
		if id != Catalog.SPARK_DART:
			t.set_stock(id, 0)
