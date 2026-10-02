@warning_ignore_start("integer_division")
extends RefCounted
## M3 QA helpers (not a test file). Load with
## `const M3 = preload("res://tests/qa/qa_m3.gd")`.
##
## Holds: the seeded SHOPPING BOT (buys across the whole catalog, then plays rounds with every
## weapon and item), golden-fixture recording/replay for the v2 scenarios, an independent
## economy auditor (docs/ARCHITECTURE.md section 18) and the M3 state invariants.

const QaUtil = preload("res://tests/qa/qa_util.gd")

## Pseudo action kind: the caller invokes Simulation.start_round().
const START_ROUND: String = "start_round"
const MAX_BUYS: int = 14
const AIM_KINDS: Array[String] = ["fire", "move", "use_item", "pass"]
const SHIELDS: Array[String] = ["glow_shield", "ion_shield", "fortress_field"]


# --- scenarios -------------------------------------------------------------------------------

static func scenarios() -> Array[Dictionary]:
	return [
		{"name": "m3_trio_3x3_normal", "seed": 90210, "tanks": 3, "rounds": 3, "wind_max": 100,
				"start_money": 10000, "bot_seed": 20, "max_actions": 300},
		{"name": "m3_hexa_6x2_rich", "seed": 555, "tanks": 6, "rounds": 2, "wind_max": 100,
				"start_money": 25000, "bot_seed": 36, "max_actions": 300},
		# Seed 107 opens with wind +100 (= wind_max) in round 0.
		{"name": "m3_duel_2x5_wind100", "seed": 107, "tanks": 2, "rounds": 5, "wind_max": 100,
				"start_money": 10000, "bot_seed": 53, "max_actions": 400},
		{"name": "m3_octo_8x1_poor", "seed": 8888, "tanks": 8, "rounds": 1, "wind_max": 100,
				"start_money": 3000, "bot_seed": 39, "max_actions": 300},
	]


static func make_settings(sc: Dictionary) -> MatchSettings:
	var s: MatchSettings = QaUtil.settings(sc["seed"], sc["tanks"], sc["rounds"], sc["wind_max"])
	s.start_money = sc["start_money"]
	return s


# --- shopping bot ------------------------------------------------------------------------------

## The next action for the current phase (uses only `rng`): START_ROUND when the shop is
## ready, {} when the match is over.
static func next_action(state: MatchState, rng: Rng) -> Dictionary:
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		return {}
	if state.phase == SimConstants.PHASE_SHOP:
		if Simulation.all_ready(state):
			return {"kind": START_ROUND}
		return _shop_action(state, rng)
	return _round_action(state, rng)


## Applies a bot action (including the START_ROUND pseudo action) and returns its events.
static func apply(state: MatchState, action: Dictionary) -> Array[Dictionary]:
	if action["kind"] == START_ROUND:
		return Simulation.start_round(state)
	return Simulation.apply_action(state, action)


## Catalog ids the tank can legally buy right now (one bundle).
static func affordable(state: MatchState, t: TankState) -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		var def: Dictionary = Catalog.get_def(id)
		if def.get("unlimited", false):
			continue
		if def["tier"] == "full" and not state.settings.full_unlocked:
			continue
		if (def["price"] as int) > t.money:
			continue
		if t.stock_of(id) + (def["bundle"] as int) > SimConstants.INVENTORY_CAP:
			continue
		out.append(id)
	return out


static func _shop_action(state: MatchState, rng: Rng) -> Dictionary:
	var t: TankState = null
	for c: TankState in state.tanks:
		if not c.ready:
			t = c
			break
	var buys: int = 0
	for n: int in t.inventory:
		buys += n
	var options: Array[String] = affordable(state, t)
	var roll: int = rng.range_int(0, 13)
	if roll == 0 or options.is_empty() or buys > MAX_BUYS * 5:
		return {"kind": "ready", "tank": t.id}
	if roll == 1 and buys > 0:
		var owned: Array[String] = []
		for id: String in Catalog.IDS:
			if t.stock_of(id) > 0:
				owned.append(id)
		var sid: String = owned[rng.range_int(0, owned.size() - 1)]
		return {"kind": "sell", "tank": t.id, "item": sid, "qty": rng.range_int(1, t.stock_of(sid))}
	var id: String = options[rng.range_int(0, options.size() - 1)]
	var def: Dictionary = Catalog.get_def(id)
	var qty: int = 1
	if (def["price"] as int) * 2 <= t.money and rng.range_int(0, 3) == 0:
		qty = 2
	if t.stock_of(id) + (def["bundle"] as int) * qty > SimConstants.INVENTORY_CAP:
		qty = 1
	return {"kind": "buy", "tank": t.id, "item": id, "qty": qty}


static func _round_action(state: MatchState, rng: Rng) -> Dictionary:
	var me: TankState = state.tanks[state.current_tank]
	var roll: int = rng.range_int(0, 99)
	if roll < 5:
		return {"kind": "pass", "tank": me.id}
	if roll < 30 and not me.has_shield():
		var shields: Array[String] = []
		for id: String in SHIELDS:
			if me.stock_of(id) > 0:
				shields.append(id)
		if not shields.is_empty():
			return {"kind": "use_item", "tank": me.id, "item": shields[rng.range_int(0, shields.size() - 1)]}
	if roll < 42 and me.repulsor_charge == 0 and me.stock_of("repulsor_field") > 0:
		return {"kind": "use_item", "tank": me.id, "item": "repulsor_field"}
	if roll < 52 and me.stock_of("nanorepair_kit") > 0 and (me.health < 70 or rng.range_int(0, 3) == 0):
		return {"kind": "use_item", "tank": me.id, "item": "nanorepair_kit"}
	if roll < 70 and (me.fuel > 0 or me.stock_of("fuel_cell") > 0):
		var dx: int = rng.range_int(1, 90)
		if rng.range_int(0, 5) == 0:
			dx = SimConstants.MOVE_MAX_DX
		return {"kind": "move", "tank": me.id, "dx": dx if rng.range_int(0, 1) == 0 else -dx}
	return _fire_action(state, me, rng)


## A fire action with a random owned weapon (Spark Dart if nothing is owned or occasionally).
static func _fire_action(state: MatchState, me: TankState, rng: Rng) -> Dictionary:
	var owned: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.is_weapon(id) and id != Catalog.SPARK_DART and me.stock_of(id) > 0:
			owned.append(id)
	var weapon: String = Catalog.SPARK_DART
	if not owned.is_empty() and rng.range_int(0, 9) != 0:
		weapon = owned[rng.range_int(0, owned.size() - 1)]
	var targets: Array[TankState] = []
	for t: TankState in state.tanks:
		if t.alive and t.team != me.team:
			targets.append(t)
	if targets.is_empty() or rng.range_int(0, 7) == 0:
		return {"kind": "fire", "tank": me.id, "angle": rng.range_int(0, SimConstants.MAX_ANGLE),
				"power": rng.range_int(1, SimConstants.MAX_POWER), "weapon": weapon}
	var tgt: TankState = targets[rng.range_int(0, targets.size() - 1)]
	var angle: int = rng.range_int(300, 700) if tgt.x >= me.x else rng.range_int(1100, 1500)
	var power: int = _plain_power(state, me, tgt, angle)
	if Catalog.get_def(weapon)["behavior"] == "beam":
		angle = _beam_angle(me, tgt, rng)
	power = clampi(power + rng.range_int(-15, 15), SimConstants.MIN_POWER, SimConstants.MAX_POWER)
	return {"kind": "fire", "tank": me.id, "angle": angle, "power": power, "weapon": weapon}


## Power at which a plain shell fired at `angle` lands near the target (flat-ground formula,
## then two refinement traces).
static func _plain_power(state: MatchState, me: TankState, tgt: TankState, angle: int) -> int:
	var dist: int = maxi(1, absi(tgt.x - me.x))
	var sin2: int = absi(FixedMath.sin10(2 * angle))
	var power: int = clampi(FixedMath.isqrt(519 * dist * FixedMath.ONE / maxi(1, sin2)), 10, SimConstants.MAX_POWER)
	for _i: int in range(2):
		var tr: Dictionary = Ballistics.trace(state, me.id, angle, power, "pulse_missile",
				SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
		var hit: int = maxi(1, absi((tr["end_x"] as int) - me.x))
		power = clampi(FixedMath.isqrt(power * power * dist / hit), 10, SimConstants.MAX_POWER)
	return power


## The launch angle (0..1800) whose direction points closest at the target's centre.
static func _beam_angle(me: TankState, tgt: TankState, rng: Rng) -> int:
	var dx: int = tgt.x - me.x
	var dy: int = (me.y - SimConstants.TANK_H) - (tgt.y - SimConstants.TANK_H / 2)  # up is positive
	var best: int = 450
	var best_score: int = -(1 << 60)
	for a: int in range(0, SimConstants.MAX_ANGLE + 1, 10):
		var score: int = FixedMath.cos10(a) * dx + FixedMath.sin10(a) * dy
		if score > best_score:
			best_score = score
			best = a
	return clampi(best + rng.range_int(-8, 8), 0, SimConstants.MAX_ANGLE)


# --- recording and replay -----------------------------------------------------------------------

static func _record_step(action: Dictionary, events: Array[Dictionary], state: MatchState) -> Dictionary:
	var rec: Dictionary = {"op": action["kind"]}
	if action["kind"] != START_ROUND:
		rec["a"] = action
	rec["fp"] = Simulation.fingerprint(state)
	rec["ev"] = ",".join(QaUtil.types(events))
	rec["evh"] = QaUtil.events_digest(events)
	return rec


## Runs the shopping bot on a scenario and records every step.
static func generate_record(sc: Dictionary) -> Dictionary:
	var state: MatchState = Simulation.new_match(make_settings(sc))
	var initial_fp: String = Simulation.fingerprint(state)
	var rng := Rng.new(sc["bot_seed"])
	var steps: Array[Dictionary] = []
	var aim_actions: int = 0
	while steps.size() < 4000 and aim_actions < (sc["max_actions"] as int):
		var action: Dictionary = next_action(state, rng)
		if action.is_empty():
			break
		var events: Array[Dictionary] = apply(state, action)
		if AIM_KINDS.has(action["kind"]):
			aim_actions += 1
		steps.append(_record_step(action, events, state))
	return {
		"scenario": sc,
		"initial_fp": initial_fp,
		"steps": steps,
		"final_phase": state.phase,
		"final_round": state.round_index,
		"final_fp": Simulation.fingerprint(state),
	}


static func fixture_path(name: String) -> String:
	return QaUtil.fixture_path(name)


## One line per step so diffs stay readable.
static func save_fixture(name: String, record: Dictionary) -> bool:
	var f: FileAccess = FileAccess.open(fixture_path(name), FileAccess.WRITE)
	if f == null:
		return false
	var head: Dictionary = record.duplicate()
	head.erase("steps")
	var lines: PackedStringArray = PackedStringArray()
	for s: Dictionary in (record["steps"] as Array):
		lines.append(JSON.stringify(s, "", true))
	f.store_string("{\"head\": " + JSON.stringify(head, "", true) + ",\n\"steps\": [\n" + ",\n".join(lines) + "\n]}\n")
	return true


## The parsed fixture (head fields plus "steps"), or {} if missing or corrupt.
static func load_fixture(name: String) -> Dictionary:
	var parsed: Dictionary = QaUtil.load_fixture(name)
	if parsed.is_empty() or not parsed.has("head") or not parsed.has("steps"):
		return {}
	var rec: Dictionary = parsed["head"]
	rec["steps"] = parsed["steps"]
	return rec


static func inventories(state: MatchState) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for t: TankState in state.tanks:
		out.append(t.inventory.duplicate())
	return out


## Replays a fixture's recorded actions through JSON-normalised dictionaries (the bot is NOT
## consulted). `hook` is called as hook(state, action, events, inventories_before) after every step.
## Returns mismatch descriptions; empty = perfect replay.
static func replay_record(record: Dictionary, hook: Callable = Callable()) -> Array[String]:
	var problems: Array[String] = []
	var sc: Dictionary = record["scenario"]
	var settings := MatchSettings.new()
	settings.seed = int(sc["seed"])
	settings.num_tanks = int(sc["tanks"])
	settings.rounds = int(sc["rounds"])
	settings.wind_max = int(sc["wind_max"])
	settings.start_money = int(sc["start_money"])
	var state: MatchState = Simulation.new_match(settings)
	if Simulation.fingerprint(state) != record["initial_fp"]:
		problems.append("initial fingerprint %s != golden %s" % [Simulation.fingerprint(state), record["initial_fp"]])
		return problems
	var steps: Array = record["steps"]
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]
		var action: Dictionary = {"kind": START_ROUND}
		if step["op"] != START_ROUND:
			action = Simulation.normalize_action(step["a"] as Dictionary)
			var verr: String = Simulation.validate_action(state, action)
			if verr != "":
				problems.append("step %d: recorded action %s rejected with '%s'" % [i, str(action), verr])
				return problems
		var inv_before: Array[PackedInt32Array] = inventories(state)
		var events: Array[Dictionary] = apply(state, action)
		if events.is_empty():
			problems.append("step %d (%s): no events" % [i, step["op"]])
			return problems
		if hook.is_valid():
			hook.call(state, action, events, inv_before)
		var fp: String = Simulation.fingerprint(state)
		if fp != step["fp"]:
			problems.append("step %d (%s): fingerprint %s != golden %s" % [i, step["op"], fp, step["fp"]])
			return problems
		var ev_types: String = ",".join(QaUtil.types(events))
		if ev_types != step["ev"]:
			problems.append("step %d: event types differ\n  got:    %s\n  golden: %s" % [i, ev_types, step["ev"]])
			return problems
		if QaUtil.events_digest(events) != step["evh"]:
			problems.append("step %d: event payload digest differs (same types, different values)" % i)
			return problems
	if state.phase != record["final_phase"]:
		problems.append("final phase %s != golden %s" % [state.phase, record["final_phase"]])
	if Simulation.fingerprint(state) != record["final_fp"]:
		problems.append("final fingerprint differs")
	return problems


# --- coverage ledger ---------------------------------------------------------------------------

## Adds to `ledger` (catalog id -> count) every catalog entry this step used in play: a weapon
## fired, or an item consumed during the aim phase (shield/repulsor/repair used, Fuel Cell
## drawn by a move, Drift Chute spent on a fall). `inv_before` is the inventories before it.
static func note_usage(ledger: Dictionary, state: MatchState, action: Dictionary, inv_before: Array[PackedInt32Array]) -> void:
	if not AIM_KINDS.has(action["kind"]):
		return
	if action["kind"] == "fire" and action["weapon"] == Catalog.SPARK_DART:
		ledger[Catalog.SPARK_DART] = (ledger.get(Catalog.SPARK_DART, 0) as int) + 1
	for t: TankState in state.tanks:
		for i: int in range(Catalog.count()):
			if t.inventory[i] < inv_before[t.id][i]:
				var id: String = Catalog.id_at(i)
				ledger[id] = (ledger.get(id, 0) as int) + (inv_before[t.id][i] - t.inventory[i])


# --- M3 invariants -----------------------------------------------------------------------------

## QaUtil.check_invariants plus the M3 rules: Spark Dart never stored, resting position
## (a tank buried by dirt is allowed to sit below the surface, never above it), wells sorted,
## standings valid.
static func check_state(state: MatchState) -> Array[String]:
	var errs: Array[String] = QaUtil.check_invariants(state, false, true)
	for t: TankState in state.tanks:
		if t.inventory[Catalog.index_of(Catalog.SPARK_DART)] != 0:
			errs.append("tank %d stores the unlimited spark_dart" % t.id)
		if state.terrain != null and t.alive:
			var rest: int = TankState.rest_y(state.terrain, t.x)
			if t.y < rest:
				errs.append("tank %d floats: y=%d above rest_y=%d" % [t.id, t.y, rest])
			elif t.y > rest and not QaUtil.tank_embedded(state, t):
				errs.append("tank %d y=%d below rest_y=%d but not buried" % [t.id, t.y, rest])
	var last_owner: int = -1
	for w: Dictionary in state.wells:
		var owner: int = w["owner"]
		if owner <= last_owner or owner >= state.tanks.size():
			errs.append("wells not strictly sorted by valid owner: %s" % str(state.wells))
		last_owner = owner
		if state.phase == SimConstants.PHASE_AIM and (w["expires_turn"] as int) <= state.turn_number:
			errs.append("expired well still active: %s at turn %d" % [str(w), state.turn_number])
	errs.append_array(check_standings(state))
	return errs


## Standings must be a permutation ordered by (round_wins desc, damage_dealt desc, kills desc, id asc).
static func check_standings(state: MatchState) -> Array[String]:
	var errs: Array[String] = []
	var st: Array[int] = Simulation.standings(state)
	var seen: Dictionary = {}
	for id: int in st:
		seen[id] = true
	if st.size() != state.tanks.size() or seen.size() != state.tanks.size():
		errs.append("standings is not a permutation of the tank ids: %s" % str(st))
		return errs
	for i: int in range(st.size() - 1):
		var a: TankState = state.tanks[st[i]]
		var b: TankState = state.tanks[st[i + 1]]
		var ka: Array[int] = [-a.round_wins, -a.damage_dealt, -a.kills, a.id]
		var kb: Array[int] = [-b.round_wins, -b.damage_dealt, -b.kills, b.id]
		if not _key_less(ka, kb):
			errs.append("standings order violated between %d and %d: %s vs %s" % [a.id, b.id, str(ka), str(kb)])
	return errs


static func _key_less(a: Array[int], b: Array[int]) -> bool:
	for i: int in range(a.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false


# --- economy auditor -----------------------------------------------------------------------------

## Pre-action snapshot for audit().
static func snapshot(state: MatchState) -> Dictionary:
	var tanks: Array[Dictionary] = []
	for t: TankState in state.tanks:
		tanks.append({"money": t.money, "health": t.health, "alive": t.alive, "kills": t.kills,
				"dealt": t.damage_dealt, "wins": t.round_wins, "team": t.team, "fuel": t.fuel,
				"shield_type": t.shield_type, "shield_hp": t.shield_hp, "charge": t.repulsor_charge,
				"inv": t.inventory.duplicate()})
	return {"tanks": tanks, "phase": state.phase, "round": state.round_index}


## Independent re-derivation of every credit in a timeline (section 18) against the state
## change. `action` is the action that produced `events` (or the START_ROUND pseudo action).
## Returns violations; empty means the books balance.
static func audit(before: Dictionary, state: MatchState, action: Dictionary, events: Array[Dictionary]) -> Array[String]:
	var errs: Array[String] = []
	var tb: Array = before["tanks"]
	var n: int = tb.size()
	var kind: String = action["kind"]
	var actor: int = action.get("tank", -1) if typeof(action.get("tank", -1)) == TYPE_INT else -1
	var attacker: int = actor if kind == "fire" else -1
	var money: Array[int] = []
	var hp: Array[int] = []
	var delta_sum: Array[int] = []
	var kills: Array[int] = []
	var dealt: Array[int] = []
	for i: int in range(n):
		money.append(tb[i]["money"])
		hp.append(tb[i]["health"])
		delta_sum.append(0)
		kills.append(0)
		dealt.append(0)
	var consumed: Dictionary = {}  # event index -> true (money events explained by a damage/pay/shop rule)
	var round_end_at: int = -1
	var chutes: Array[int] = []
	var draws_dx: Array[int] = []
	for i: int in range(n):
		chutes.append(0)
		draws_dx.append(0)
	for idx: int in range(events.size()):
		var e: Dictionary = events[idx]
		match e["type"]:
			"damage":
				var tgt: int = e["tank"]
				var removed: int = hp[tgt] - (e["health"] as int)
				hp[tgt] = e["health"]
				if removed <= 0:
					errs.append("damage event #%d removes %d HP" % [idx, removed])
				if attacker < 0:
					continue
				var expect: Array[Dictionary] = []
				var team_a: int = tb[attacker]["team"]
				var team_t: int = tb[tgt]["team"]
				if team_a == team_t:
					var pen: int = mini(removed * SimConstants.CREDIT_PER_HP, money[attacker])
					if pen > 0:
						expect.append({"tank": attacker, "delta": -pen, "reason": "self_damage"})
				else:
					expect.append({"tank": attacker, "delta": removed * SimConstants.CREDIT_PER_HP, "reason": "damage"})
					dealt[attacker] += removed
					if (e["health"] as int) == 0:
						expect.append({"tank": attacker, "delta": SimConstants.KILL_BONUS, "reason": "kill"})
						kills[attacker] += 1
				for k: int in range(expect.size()):
					var j: int = idx + 1 + k
					var want: Dictionary = expect[k]
					if j >= events.size() or events[j]["type"] != "money":
						errs.append("damage #%d: expected money %s right after it" % [idx, str(want)])
						continue
					var got: Dictionary = events[j]
					if got["tank"] != want["tank"] or got["delta"] != want["delta"] or got["reason"] != want["reason"]:
						errs.append("damage #%d: money %s expected %s" % [idx, str(got), str(want)])
					money[attacker] += got["delta"]
					delta_sum[attacker] += got["delta"]
					if got["money"] != money[attacker]:
						errs.append("money event #%d reports balance %d, expected %d" % [j, got["money"], money[attacker]])
					consumed[j] = true
			"repair":
				hp[e["tank"]] = e["health"]
			"chute":
				chutes[e["tank"]] += 1
			"round_end":
				round_end_at = idx
	# Money events not tied to a damage hit: shop, round pay.
	var pay_expected: Array[Dictionary] = []
	if round_end_at >= 0:
		var winner: int = events[round_end_at]["winner"]
		var alive_ids: Array[int] = []
		for t: TankState in state.tanks:
			if t.alive:
				alive_ids.append(t.id)
		if alive_ids.size() > 1:
			errs.append("round_end with %d tanks alive" % alive_ids.size())
		if alive_ids.is_empty() and winner != -1:
			errs.append("round_end winner %d with nobody alive" % winner)
		if alive_ids.size() == 1 and winner != alive_ids[0]:
			errs.append("round_end winner %d but only tank %d is alive" % [winner, alive_ids[0]])
		for id: int in alive_ids:
			pay_expected.append({"tank": id, "delta": SimConstants.SURVIVE_PAY, "reason": "survive"})
			if id == winner:
				pay_expected.append({"tank": id, "delta": SimConstants.WIN_PAY, "reason": "win"})
		var pay_events: Array[Dictionary] = []
		for j: int in range(round_end_at + 1, events.size()):
			pay_events.append(events[j])
		if pay_events.size() != pay_expected.size():
			errs.append("round pay: %d events after round_end, expected %d (%s)" % [pay_events.size(), pay_expected.size(), str(pay_expected)])
		for k: int in range(mini(pay_events.size(), pay_expected.size())):
			var got2: Dictionary = pay_events[k]
			var want2: Dictionary = pay_expected[k]
			if got2["type"] != "money" or got2["tank"] != want2["tank"] or got2["delta"] != want2["delta"] or got2["reason"] != want2["reason"]:
				errs.append("round pay #%d: got %s expected %s" % [k, str(got2), str(want2)])
			else:
				money[want2["tank"]] += got2["delta"]
				delta_sum[want2["tank"]] += got2["delta"]
				if got2["money"] != money[want2["tank"]]:
					errs.append("pay event reports balance %d, expected %d" % [got2["money"], money[want2["tank"]]])
			consumed[round_end_at + 1 + k] = true
		if winner >= 0 and state.tanks[winner].round_wins != (tb[winner]["wins"] as int) + 1:
			errs.append("winner %d round_wins %d -> %d" % [winner, tb[winner]["wins"], state.tanks[winner].round_wins])
		for t: TankState in state.tanks:
			if t.id != winner and t.round_wins != (tb[t.id]["wins"] as int):
				errs.append("tank %d round_wins changed without winning" % t.id)
	# Shop money.
	for idx: int in range(events.size()):
		var e2: Dictionary = events[idx]
		if e2["type"] != "money" or consumed.has(idx):
			continue
		var tk: int = e2["tank"]
		if kind == "buy" and e2["reason"] == "buy" and tk == actor:
			var def: Dictionary = Catalog.get_def(action["item"])
			if e2["delta"] != -(def["price"] as int) * (action["qty"] as int):
				errs.append("buy delta %d for %s" % [e2["delta"], str(action)])
		elif kind == "sell" and e2["reason"] == "sell" and tk == actor:
			var def2: Dictionary = Catalog.get_def(action["item"])
			var owned: int = (tb[actor]["inv"] as PackedInt32Array)[Catalog.index_of(action["item"])]
			var units: int = mini(action["qty"], owned)
			var refund: int = (def2["price"] as int) * units / (def2["bundle"] as int) / 2
			if e2["delta"] != refund or refund <= 0:
				errs.append("sell delta %d, expected %d for %s" % [e2["delta"], refund, str(action)])
		else:
			errs.append("unexplained money event %s during %s" % [str(e2), kind])
		money[tk] += e2["delta"]
		delta_sum[tk] += e2["delta"]
		if e2["money"] != money[tk]:
			errs.append("money event reports balance %d, expected %d" % [e2["money"], money[tk]])
	# State versus the event books.
	for t: TankState in state.tanks:
		var b: Dictionary = tb[t.id]
		if t.money - (b["money"] as int) != delta_sum[t.id]:
			errs.append("tank %d money changed by %d but its money events sum to %d" % [t.id, t.money - (b["money"] as int), delta_sum[t.id]])
		if t.money != money[t.id]:
			errs.append("tank %d money %d != running balance %d" % [t.id, t.money, money[t.id]])
		if kind != START_ROUND and t.health != hp[t.id]:
			errs.append("tank %d health %d != event chain %d" % [t.id, t.health, hp[t.id]])
		if t.kills - (b["kills"] as int) != kills[t.id]:
			errs.append("tank %d kills +%d, events say +%d" % [t.id, t.kills - (b["kills"] as int), kills[t.id]])
		if t.damage_dealt - (b["dealt"] as int) != dealt[t.id]:
			errs.append("tank %d damage_dealt +%d, events say +%d" % [t.id, t.damage_dealt - (b["dealt"] as int), dealt[t.id]])
		if t.money < 0:
			errs.append("tank %d money %d" % [t.id, t.money])
		# Chutes spent (only the aim phase spends them; the shop buys them).
		var chute_i: int = Catalog.index_of("drift_chute")
		var inv_b: PackedInt32Array = b["inv"]
		var spent: int = inv_b[chute_i] - t.inventory[chute_i]
		if AIM_KINDS.has(kind) and spent != chutes[t.id]:
			errs.append("tank %d spent %d chutes but %d chute events" % [t.id, spent, chutes[t.id]])
	errs.append_array(_audit_action_effects(before, state, action, events))
	return errs


## Inventory / fuel / shield bookkeeping per action kind.
static func _audit_action_effects(before: Dictionary, state: MatchState, action: Dictionary, events: Array[Dictionary]) -> Array[String]:
	var errs: Array[String] = []
	var tb: Array = before["tanks"]
	var kind: String = action["kind"]
	if kind == START_ROUND:
		for t: TankState in state.tanks:
			if t.money != (tb[t.id]["money"] as int):
				errs.append("start_round changed money of tank %d" % t.id)
			if t.inventory != (tb[t.id]["inv"] as PackedInt32Array):
				errs.append("start_round changed the inventory of tank %d" % t.id)
			if t.fuel != (tb[t.id]["fuel"] as int):
				errs.append("start_round changed the fuel of tank %d" % t.id)
		return errs
	var actor: int = action["tank"]
	var t: TankState = state.tanks[actor]
	var inv_b: PackedInt32Array = tb[actor]["inv"]
	# Only the actor's stock may change, except chutes of dragged/dropped tanks (checked in audit()).
	var chute_i: int = Catalog.index_of("drift_chute")
	for o: TankState in state.tanks:
		if o.id == actor:
			continue
		var ob: PackedInt32Array = tb[o.id]["inv"]
		for i: int in range(Catalog.count()):
			if i != chute_i and o.inventory[i] != ob[i]:
				errs.append("%s by tank %d changed %s of tank %d" % [kind, actor, Catalog.id_at(i), o.id])
	match kind:
		"fire":
			var wi: int = Catalog.index_of(action["weapon"])
			var unlimited: bool = Catalog.get_def(action["weapon"]).get("unlimited", false)
			var expect: int = inv_b[wi] - (0 if unlimited else 1)
			if t.inventory[wi] != expect:
				errs.append("fire %s: stock %d -> %d" % [action["weapon"], inv_b[wi], t.inventory[wi]])
			for i: int in range(Catalog.count()):
				if i != wi and i != chute_i and t.inventory[i] != inv_b[i]:
					errs.append("fire changed stock of %s" % Catalog.id_at(i))
		"buy":
			var def: Dictionary = Catalog.get_def(action["item"])
			var bi: int = Catalog.index_of(action["item"])
			if t.inventory[bi] != inv_b[bi] + (def["bundle"] as int) * (action["qty"] as int):
				errs.append("buy: stock %d -> %d" % [inv_b[bi], t.inventory[bi]])
		"sell":
			var si: int = Catalog.index_of(action["item"])
			if t.inventory[si] != inv_b[si] - mini(action["qty"], inv_b[si]):
				errs.append("sell: stock %d -> %d" % [inv_b[si], t.inventory[si]])
		"move":
			var mv: Array[Dictionary] = QaUtil.find(events, "tank_move")
			if mv.size() != 1:
				errs.append("move produced %d tank_move events" % mv.size())
			else:
				var ci: int = Catalog.index_of("fuel_cell")
				var draws: int = inv_b[ci] - t.inventory[ci]
				var steps: int = absi((mv[0]["to_x"] as int) - (mv[0]["from_x"] as int))
				var want_fuel: int = (tb[actor]["fuel"] as int) + 100 * draws - steps
				if t.fuel != want_fuel or mv[0]["fuel"] != t.fuel:
					errs.append("move: fuel %d -> %d with %d draws and %d steps (event says %s)" % [tb[actor]["fuel"], t.fuel, draws, steps, str(mv[0]["fuel"])])
		"use_item":
			var ui: int = Catalog.index_of(action["item"])
			if t.inventory[ui] != inv_b[ui] - 1:
				errs.append("use_item: stock %d -> %d" % [inv_b[ui], t.inventory[ui]])
			var def3: Dictionary = Catalog.get_def(action["item"])
			if def3["behavior"] == "shield":
				if t.shield_type != ui or t.shield_hp != (def3["hp"] as int):
					errs.append("shield %s not applied cleanly: type %d hp %d" % [action["item"], t.shield_type, t.shield_hp])
			elif def3["behavior"] == "repulsor" and t.repulsor_charge != (def3["charge"] as int):
				errs.append("repulsor charge %d" % t.repulsor_charge)
	return errs


## Stricter-than-QaUtil per-timeline ordering for M3 timelines: starts with the action's own
## event, ends in exactly one of round_end(+pay) / (wind, turn) for turn-ending actions, and
## tank_destroyed comes after all damage and before the turn/round event.
static func check_timeline(action: Dictionary, events: Array[Dictionary]) -> Array[String]:
	var errs: Array[String] = QaUtil.check_event_fields(events)
	var ts: Array[String] = QaUtil.types(events)
	if ts.is_empty():
		return ["empty timeline"]
	var kind: String = action["kind"]
	var first: String = {"fire": "fire", "move": "tank_move", "buy": "money", "sell": "money", "ready": "ready",
			"pass": "wind", START_ROUND: "round_start", "use_item": ""}.get(kind, "")
	if first != "" and ts[0] != first and not (kind in ["buy", "sell"] and ts[0] == "money"):
		errs.append("%s timeline starts with %s" % [kind, ts[0]])
	var body: Array[String] = ts.duplicate()
	while not body.is_empty() and body[body.size() - 1] == "money" and body.has("round_end"):
		body.pop_back()
	var ends_round: bool = not body.is_empty() and body[body.size() - 1] == "round_end"
	var ends_turn: bool = body.size() >= 2 and body[body.size() - 2] == "wind" and body[body.size() - 1] == "turn"
	var ending: bool = kind == "fire" or kind == "pass" or (kind == "use_item" and action["item"] == "nanorepair_kit")
	if kind == "move" or kind == "use_item":
		ending = ending or ts.has("round_end") or ts.has("wind")
	if ending and ends_round == ends_turn:
		errs.append("%s must end with exactly one of round_end / (wind, turn): %s" % [kind, ",".join(body.slice(maxi(0, body.size() - 4)))])
	if not ending and (ends_round or ends_turn):
		errs.append("%s must not end the turn" % kind)
	if ts.count("round_end") + ts.count("turn") > 1:
		errs.append("multiple round_end/turn events")
	var last_destroyed: int = -1
	var last_hit: int = -1
	var end_at: int = ts.size()
	for i: int in range(ts.size()):
		match ts[i]:
			"tank_destroyed":
				last_destroyed = i
			"damage", "tank_fall", "chute", "shield_hit", "shield_down", "terrain_settle", "explosion":
				last_hit = i
			"round_end", "wind":
				end_at = mini(end_at, i)
	if last_destroyed >= 0 and (last_hit > last_destroyed or last_destroyed > end_at):
		errs.append("tank_destroyed not after all damage / before the turn event")
	for i: int in range(ts.size()):
		if ts[i] == "tank_fall" and i + 1 < ts.size() and ts[i + 1] == "damage" and events[i + 1]["cause"] != "fall":
			errs.append("tank_fall followed by a non-fall damage")
		if ts[i] == "damage" and events[i]["cause"] == "fall" and (i == 0 or (ts[i - 1] != "tank_fall" and ts[i - 1] != "chute")):
			errs.append("damage(fall) not directly after its tank_fall")
		if ts[i] == "explosion" and (i + 1 >= ts.size() or ts[i + 1] != "terrain_carve"):
			errs.append("explosion not followed by terrain_carve")
	return errs
