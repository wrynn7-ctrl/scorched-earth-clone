@warning_ignore_start("integer_division")
extends GutTest
## M3 fuzz: 200 seeded matches over the FULL M3 action space (fire with every weapon, move,
## use_item, pass, buy, sell, ready, start_round) mixed with deliberately invalid actions of
## every error kind, in every phase. After every legal action the independent economy audit,
## the timeline order check and the state invariants must hold; every rejected action must
## return the documented error key, produce no events and change nothing.
## Failures print the match index and seed so a case can be replayed.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const DEFAULT_MATCHES: int = 200
const DEFAULT_ROOT_SEED: int = 0xF0330000
## Deep runs (tools/qa/deep_fuzz.sh): QA_FUZZ_SEED / QA_FUZZ_MATCHES override the fixed defaults.
var MATCHES: int = int(OS.get_environment("QA_FUZZ_MATCHES")) if OS.get_environment("QA_FUZZ_MATCHES") != "" else DEFAULT_MATCHES
var ROOT_SEED: int = int(OS.get_environment("QA_FUZZ_SEED")) if OS.get_environment("QA_FUZZ_SEED") != "" else DEFAULT_ROOT_SEED

## Every error key validate_action may return (docs/ARCHITECTURE.md sections 9, 19, 25).
const ERROR_KEYS: Array[String] = ["bad_action", "unknown_kind", "bad_phase", "bad_field", "bad_tank", "not_your_turn",
		"tank_dead", "bad_angle", "bad_power", "unknown_weapon", "out_of_stock", "no_fuel", "unknown_item", "not_usable",
		"locked_item", "no_money", "inventory_full", "not_buyable", "already_ready"]

var _hits: Dictionary = {}  # error key -> times seen
var _kinds: Dictionary = {}  # action kind -> times applied
var _weapons_fired: Dictionary = {}


func _random_settings(rng: Rng, m: int) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = rng.next_u32()
	match m % 6:
		0:
			s.seed = -s.seed
		1:
			s.seed = (s.seed << 31) | rng.next_u32()
	s.num_tanks = rng.range_int(2, 8) if m % 2 == 1 else rng.range_int(2, 4)
	s.rounds = rng.range_int(1, 4)
	s.wind_max = [100, 100, 0, 1, 37][m % 5]
	s.start_money = [10000, 25000, 3000, 500, 0, 1_000_000][m % 6]
	s.full_unlocked = m % 5 != 2
	return s


func _random_tank(state: MatchState, rng: Rng) -> TankState:
	return state.tanks[rng.range_int(0, state.tanks.size() - 1)]


func _all_weapons() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.is_weapon(id):
			out.append(id)
	return out


func _rejected(state: MatchState, action: Dictionary, expect: String, tag: String, failures: Array[String], check_sig: bool) -> void:
	var sig: String = QaUtil.quick_sig(state) if check_sig else ""
	var got: String = Simulation.validate_action(state, action)
	if expect != "" and got != expect:
		failures.append("%s: validate(%s) = '%s', expected '%s'" % [tag, str(action), got, expect])
	if got == "":
		failures.append("%s: %s was expected to be rejected but is legal" % [tag, str(action)])
		return
	if not ERROR_KEYS.has(got):
		failures.append("%s: undocumented error key '%s' for %s" % [tag, got, str(action)])
	_hits[got] = (_hits.get(got, 0) as int) + 1
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	if not ev.is_empty():
		failures.append("%s: rejected action %s produced %d events" % [tag, str(action), ev.size()])
	if check_sig and QaUtil.quick_sig(state) != sig:
		failures.append("%s: rejected action %s changed the state" % [tag, str(action)])


# --- invalid action generators ------------------------------------------------------------------

## [action, expected error key] for an aim-phase action with exactly one defect.
func _invalid_aim(state: MatchState, rng: Rng) -> Array:
	var n: int = state.tanks.size()
	var me: TankState = state.tanks[state.current_tank]
	var fire: Dictionary = {"kind": "fire", "tank": me.id, "angle": rng.range_int(0, 1800), "power": rng.range_int(1, 1000),
			"weapon": "spark_dart"}
	match rng.range_int(0, 27):
		0:
			var a: Dictionary = fire.duplicate()
			a["tank"] = (me.id + 1 + rng.range_int(0, n - 2)) % n
			return [a, "not_your_turn"]
		1:
			var a: Dictionary = fire.duplicate()
			a["tank"] = -1 - rng.range_int(0, 9)
			return [a, "bad_tank"]
		2:
			var a: Dictionary = fire.duplicate()
			a["tank"] = n + rng.range_int(0, 100000)
			return [a, "bad_tank"]
		3:
			var a: Dictionary = fire.duplicate()
			a["angle"] = [-1, 1801, 3600, -9999, 1 << 40][rng.range_int(0, 4)]
			return [a, "bad_angle"]
		4:
			var a: Dictionary = fire.duplicate()
			a["power"] = [0, -1, 1001, 99999, -(1 << 40)][rng.range_int(0, 4)]
			return [a, "bad_power"]
		5:
			var a: Dictionary = fire.duplicate()
			a["weapon"] = ["", "nope", "Pulse_Missile", "glow_shield", "nanorepair_kit", "fuel_cell"][rng.range_int(0, 5)]
			return [a, "unknown_weapon"]
		6:
			var unowned: Array[String] = []
			for id: String in _all_weapons():
				if id != Catalog.SPARK_DART and me.stock_of(id) <= 0:
					unowned.append(id)
			if unowned.is_empty():
				return [{"kind": "fire", "tank": me.id, "angle": 0, "power": 0, "weapon": "spark_dart"}, "bad_power"]
			var a: Dictionary = fire.duplicate()
			a["weapon"] = unowned[rng.range_int(0, unowned.size() - 1)]
			return [a, "out_of_stock"]
		7:
			var a: Dictionary = fire.duplicate()
			a["angle"] = float(a["angle"]) + 0.5
			return [a, "bad_field"]
		8:
			var a: Dictionary = fire.duplicate()
			a["power"] = str(a["power"])
			return [a, "bad_field"]
		9:
			var a: Dictionary = fire.duplicate()
			a.erase(["tank", "angle", "power", "weapon"][rng.range_int(0, 3)])
			return [a, "bad_field"]
		10:
			var a: Dictionary = fire.duplicate()
			a["tank"] = true
			return [a, "bad_field"]
		11:
			var a: Dictionary = fire.duplicate()
			a["kind"] = ["dance", "shoot", "", "Fire", "PASS", "start_round", "round_end"][rng.range_int(0, 6)]
			return [a, "unknown_kind"]
		12:
			return [{}, "bad_action"]
		13:
			var a: Dictionary = fire.duplicate()
			a["kind"] = 7
			return [a, "bad_action"]
		14:
			return [{"kind": "move", "tank": me.id, "dx": [0, 201, -201, 100000, -(1 << 40)][rng.range_int(0, 4)]}, "bad_field"]
		15:
			return [{"kind": "move", "tank": me.id, "dx": 3.0 + 0.25}, "bad_field"]
		16:
			if me.fuel <= 0 and me.stock_of("fuel_cell") <= 0:
				return [{"kind": "move", "tank": me.id, "dx": rng.range_int(1, 200) * (1 if rng.range_int(0, 1) == 0 else -1)}, "no_fuel"]
			return [{"kind": "move", "tank": me.id}, "bad_field"]
		17:
			return [{"kind": "use_item", "tank": me.id, "item": ["drift_chute", "fuel_cell", "pulse_missile", "spark_dart", "supernova"][rng.range_int(0, 4)]}, "not_usable"]
		18:
			return [{"kind": "use_item", "tank": me.id, "item": ["", "zzz", "Glow_Shield"][rng.range_int(0, 2)]}, "unknown_item"]
		19:
			var missing: Array[String] = []
			for id: String in ["glow_shield", "ion_shield", "fortress_field", "repulsor_field", "nanorepair_kit"]:
				if me.stock_of(id) <= 0:
					missing.append(id)
			if missing.is_empty():
				return [{"kind": "use_item", "tank": me.id, "item": 3}, "bad_field"]
			return [{"kind": "use_item", "tank": me.id, "item": missing[rng.range_int(0, missing.size() - 1)]}, "out_of_stock"]
		20:
			return [{"kind": "use_item", "tank": me.id, "item": null}, "bad_field"]
		21:
			return [{"kind": "pass", "tank": me.id + n}, "bad_tank"]
		22:
			return [{"kind": "pass", "tank": (me.id + 1) % n}, "not_your_turn"]
		23:
			return [{"kind": "pass"}, "bad_field"]
		24:
			return [{"kind": "buy", "tank": me.id, "item": "pulse_missile", "qty": 1}, "bad_phase"]
		25:
			return [{"kind": "sell", "tank": me.id, "item": "pulse_missile", "qty": 1}, "bad_phase"]
		26:
			return [{"kind": "ready", "tank": me.id}, "bad_phase"]
		_:
			var a: Dictionary = fire.duplicate()
			a["tank"] = float(me.id) + 0.5
			return [a, "bad_field"]


## [action, expected error key] for a shop-phase action with exactly one defect.
func _invalid_shop(state: MatchState, rng: Rng) -> Array:
	var t: TankState = _random_tank(state, rng)
	var pick: int = rng.range_int(0, 21)
	if not state.settings.full_unlocked and rng.range_int(0, 2) == 0:
		pick = 5  # locked_item: only possible while the full tier is locked
	match pick:
		0:
			return [{"kind": "buy", "tank": t.id, "item": ["", "zzz", "PULSE_MISSILE"][rng.range_int(0, 2)], "qty": 1}, "unknown_item"]
		1:
			return [{"kind": "buy", "tank": t.id, "item": "spark_dart", "qty": rng.range_int(1, 50)}, "not_buyable"]
		2:
			return [{"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": [0, -1, -(1 << 40)][rng.range_int(0, 2)]}, "bad_field"]
		3:
			return [{"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 2.5}, "bad_field"]
		4:
			return [{"kind": "buy", "tank": t.id, "item": "fuel_cell", "qty": [100, 1000, 1 << 40, 9223372036854775807][rng.range_int(0, 3)]}, "inventory_full"]
		5:
			if state.settings.full_unlocked:
				return [{}, "skip"]  # nothing is locked in this match
			var fulls: Array[String] = ["supernova", "landslide", "fortress_field", "photon_lance"]
			return [{"kind": "buy", "tank": t.id, "item": fulls[rng.range_int(0, 3)], "qty": 1}, "locked_item"]
		6:
			# A purchase the tank cannot pay for (and that fits the cap).
			var dear: Array[String] = []
			for id: String in Catalog.IDS:
				var def: Dictionary = Catalog.get_def(id)
				if def.get("unlimited", false) or (def["tier"] == "full" and not state.settings.full_unlocked):
					continue
				if (def["price"] as int) > t.money and t.stock_of(id) + (def["bundle"] as int) <= SimConstants.INVENTORY_CAP:
					dear.append(id)
			if dear.is_empty():
				return [{"kind": "buy", "tank": t.id, "item": "pulse_missile", "qty": 0}, "bad_field"]
			return [{"kind": "buy", "tank": t.id, "item": dear[rng.range_int(0, dear.size() - 1)], "qty": 1}, "no_money"]
		7:
			var empty: Array[String] = []
			for id: String in Catalog.IDS:
				if t.stock_of(id) <= 0:
					empty.append(id)
			return [{"kind": "sell", "tank": t.id, "item": empty[rng.range_int(0, empty.size() - 1)], "qty": rng.range_int(1, 9)}, "out_of_stock"]
		8:
			return [{"kind": "sell", "tank": t.id, "item": "pulse_missile", "qty": [0, -5][rng.range_int(0, 1)]}, "bad_field"]
		9:
			return [{"kind": "sell", "tank": t.id, "item": "nope", "qty": 1}, "unknown_item"]
		10:
			return [{"kind": "sell", "tank": t.id, "item": Catalog.SPARK_DART, "qty": 1}, "out_of_stock"]
		11:
			t.ready = true
			return [{"kind": "ready", "tank": t.id}, "already_ready"]
		12:
			return [{"kind": "ready", "tank": -1}, "bad_tank"]
		13:
			return [{"kind": "ready", "tank": state.tanks.size()}, "bad_tank"]
		14:
			return [{"kind": "ready"}, "bad_field"]
		15:
			return [{"kind": "fire", "tank": t.id, "angle": 450, "power": 500, "weapon": "spark_dart"}, "bad_phase"]
		16:
			return [{"kind": "move", "tank": t.id, "dx": 5}, "bad_phase"]
		17:
			return [{"kind": "use_item", "tank": t.id, "item": "glow_shield"}, "bad_phase"]
		18:
			return [{"kind": "pass", "tank": t.id}, "bad_phase"]
		19:
			return [{"kind": "buy", "tank": t.id}, "bad_field"]
		20:
			return [{"kind": "buy", "tank": t.id, "qty": 1}, "bad_field"]
		_:
			return [{"kind": "sell", "tank": t.id, "item": 42, "qty": 1}, "bad_field"]


# --- legal action generators ----------------------------------------------------------------------

func _valid_buy(state: MatchState, rng: Rng) -> Dictionary:
	var t: TankState = _random_tank(state, rng)
	var options: Array[String] = M3.affordable(state, t)
	if options.is_empty():
		return {"kind": "ready", "tank": t.id}
	var id: String = options[rng.range_int(0, options.size() - 1)]
	return {"kind": "buy", "tank": t.id, "item": id, "qty": rng.range_int(1, 3)}


func _random_sell(state: MatchState, rng: Rng) -> Dictionary:
	var t: TankState = _random_tank(state, rng)
	var owned: Array[String] = []
	for id: String in Catalog.IDS:
		if t.stock_of(id) > 0:
			owned.append(id)
	if owned.is_empty():
		return {"kind": "sell", "tank": t.id, "item": "pulse_missile", "qty": rng.range_int(1, 4)}
	var id: String = owned[rng.range_int(0, owned.size() - 1)]
	return {"kind": "sell", "tank": t.id, "item": id, "qty": rng.range_int(1, t.stock_of(id) + 2)}


const ANGLES: Array[int] = [0, 1, 450, 899, 900, 901, 1350, 1799, 1800]
const POWERS: Array[int] = [1, 2, 100, 500, 999, 1000]


func _random_aim(state: MatchState, rng: Rng) -> Dictionary:
	var me: TankState = state.tanks[state.current_tank]
	var roll: int = rng.range_int(0, 99)
	if roll < 55:
		var weapon: String = Catalog.SPARK_DART
		var owned: Array[String] = []
		for id: String in _all_weapons():
			if id != Catalog.SPARK_DART and me.stock_of(id) > 0:
				owned.append(id)
		if not owned.is_empty() and rng.range_int(0, 9) != 0:
			weapon = owned[rng.range_int(0, owned.size() - 1)]
		elif rng.range_int(0, 6) == 0:
			var all: Array[String] = _all_weapons()
			weapon = all[rng.range_int(0, all.size() - 1)]  # possibly out of stock -> clean rejection
		var angle: int = ANGLES[rng.range_int(0, ANGLES.size() - 1)] if rng.range_int(0, 2) == 0 else rng.range_int(0, 1800)
		var power: int = POWERS[rng.range_int(0, POWERS.size() - 1)] if rng.range_int(0, 2) == 0 else rng.range_int(1, 1000)
		return {"kind": "fire", "tank": me.id, "angle": angle, "power": power, "weapon": weapon}
	if roll < 72:
		var dx: int = rng.range_int(1, 200)
		if rng.range_int(0, 3) == 0:
			dx = [1, 3, 12, 25, 200][rng.range_int(0, 4)]
		return {"kind": "move", "tank": me.id, "dx": dx if rng.range_int(0, 1) == 0 else -dx}
	if roll < 92:
		var items: Array[String] = ["glow_shield", "ion_shield", "fortress_field", "repulsor_field", "nanorepair_kit"]
		return {"kind": "use_item", "tank": me.id, "item": items[rng.range_int(0, items.size() - 1)]}
	return {"kind": "pass", "tank": me.id}


## Gives every tank a stock of everything (setup shortcut: the shop is exercised by the other matches).
func _stock_up(state: MatchState, units: int) -> void:
	for t: TankState in state.tanks:
		for id: String in Catalog.IDS:
			if not (Catalog.get_def(id).get("unlimited", false) as bool):
				t.set_stock(id, units)
		t.fuel = 150


func _check_floating(state: MatchState, ev: Array[Dictionary], tag: String, failures: Array[String]) -> void:
	for e: Dictionary in QaUtil.find(ev, "terrain_settle"):
		var probe: Terrain = state.terrain.duplicate_terrain()
		if probe.settle(maxi(0, (e["x0"] as int) - 8), mini(SimConstants.WORLD_W - 1, (e["x1"] as int) + 8)).size() != 0:
			failures.append("%s: dirt left floating after the settle %d..%d" % [tag, e["x0"], e["x1"]])
		return  # one probe per action is enough


func test_fuzz_200_matches_over_the_full_m3_action_space() -> void:
	var t0: int = Time.get_ticks_msec()
	var failures: Array[String] = []
	var applied: int = 0
	var rejected: int = 0
	var round_ends: int = 0
	var match_overs: int = 0
	var starts: int = 0
	var probes: int = 0
	for m: int in range(MATCHES):
		var rng := Rng.new(ROOT_SEED + m)
		var settings: MatchSettings = _random_settings(rng, m)
		var tag: String = "match %d (seed %d, %d tanks, %d rounds, wind_max %d, money %d, full %s)" % [m, settings.seed,
				settings.num_tanks, settings.rounds, settings.wind_max, settings.start_money, str(settings.full_unlocked)]
		var state: MatchState = Simulation.new_match(settings)
		var stocked: bool = m % 3 == 0
		var fragile: bool = m % 2 == 0  # 1..12 HP tanks: rounds end quickly (round pay, shop, match_over)
		if stocked:
			_stock_up(state, 3)
		var n_actions: int = rng.range_int(30, 50) if fragile else rng.range_int(18, 34)
		for i: int in range(n_actions):
			var step_tag: String = "%s action %d" % [tag, i]
			if state.phase == SimConstants.PHASE_MATCH_OVER:
				match_overs += 1
				var junk: Array[Dictionary] = [{"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "spark_dart"},
						{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}, {"kind": "pass", "tank": 0},
						{"kind": "ready", "tank": 0}]
				for j: Dictionary in junk:
					_rejected(state, j, "bad_phase", step_tag + " after match_over", failures, j == junk[0])
					rejected += 1
				if not Simulation.start_round(state).is_empty():
					failures.append("%s: start_round after match_over produced events" % step_tag)
				break
			var roll: int = rng.range_int(0, 99)
			var action: Dictionary
			var expect: String = "?"
			if state.phase == SimConstants.PHASE_SHOP:
				if roll < 30:
					# Finish the shop: ready everybody (legal) and start the round.
					for t: TankState in state.tanks:
						if not t.ready:
							var rdy: Dictionary = {"kind": "ready", "tank": t.id}
							var snap0: Dictionary = M3.snapshot(state)
							var ev0: Array[Dictionary] = Simulation.apply_action(state, rdy)
							applied += 1
							var e0: Array[String] = M3.check_timeline(rdy, ev0)
							e0.append_array(M3.audit(snap0, state, rdy, ev0))
							if not e0.is_empty():
								failures.append("%s ready: %s" % [step_tag, "; ".join(e0)])
					var snap1: Dictionary = M3.snapshot(state)
					var sr: Array[Dictionary] = Simulation.start_round(state)
					starts += 1
					var es: Array[String] = M3.audit(snap1, state, {"kind": M3.START_ROUND}, sr)
					es.append_array(QaUtil.check_event_fields(sr))
					es.append_array(M3.check_state(state))
					if sr.size() != 3 or state.phase != SimConstants.PHASE_AIM:
						es.append("start_round returned %s, phase %s" % [str(QaUtil.types(sr)), state.phase])
					if not es.is_empty():
						failures.append("%s start_round: %s" % [step_tag, "; ".join(es.slice(0, 5))])
						break
					if fragile:
						for t: TankState in state.tanks:
							t.health = 1 + rng.range_int(0, 11)
					continue
				if roll < 45:
					var pair: Array = _invalid_shop(state, rng)
					if pair[1] == "skip":
						continue
					_rejected(state, pair[0], pair[1], step_tag, failures, rng.range_int(0, 3) == 0)
					rejected += 1
					continue
				if not Simulation.all_ready(state) and roll < 52:
					var early: Array[Dictionary] = Simulation.start_round(state)
					if not early.is_empty():
						failures.append("%s: start_round with unready tanks produced events" % step_tag)
					continue
				action = _valid_buy(state, rng) if roll < 85 else _random_sell(state, rng)
			else:
				if roll < 22:
					var pair2: Array = _invalid_aim(state, rng)
					_rejected(state, pair2[0], pair2[1], step_tag, failures, rng.range_int(0, 3) == 0)
					rejected += 1
					continue
				action = _random_aim(state, rng)
				if action["kind"] == "fire" and rng.range_int(0, 11) == 0:
					action["junk"] = rng.next_u32()  # unknown keys are ignored
			var verr: String = Simulation.validate_action(state, action)
			if verr != "":
				_rejected(state, action, verr, step_tag, failures, false)
				rejected += 1
				continue
			var snap: Dictionary = M3.snapshot(state)
			var ev: Array[Dictionary] = Simulation.apply_action(state, action)
			applied += 1
			_kinds[action["kind"]] = (_kinds.get(action["kind"], 0) as int) + 1
			if action["kind"] == "fire":
				_weapons_fired[action["weapon"]] = true
			if ev.is_empty():
				failures.append("%s: legal %s produced no events" % [step_tag, str(action)])
				break
			var errs: Array[String] = M3.audit(snap, state, action, ev)
			errs.append_array(M3.check_timeline(action, ev))
			errs.append_array(M3.check_state(state))
			if action["kind"] == "fire" and rng.range_int(0, 3) == 0:
				probes += 1
				_check_floating(state, ev, step_tag, errs)
			if not errs.is_empty():
				failures.append("%s after %s:\n    %s" % [step_tag, str(action), "\n    ".join(errs.slice(0, 5))])
				break
			for e: Dictionary in ev:
				if e["type"] == "round_end":
					round_ends += 1
		if failures.size() > 8:
			break
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("FUZZ M3: %d matches, %d applied (%s), %d rejected, %d start_rounds, %d round_ends, %d match_over, %d floating probes in %d ms" % [
			MATCHES, applied, str(_kinds), rejected, starts, round_ends, match_overs, probes, ms])
	gut.p("error keys hit: %s" % str(_hits))
	gut.p("weapons fired: %d of 21" % _weapons_fired.size())
	assert_eq(failures.size(), 0, "fuzz failures:\n%s" % "\n".join(failures))
	assert_gt(applied, 15 * MATCHES, "plenty of legal actions")
	assert_gt(round_ends, MATCHES / 3, "plenty of round ends")
	for kind: String in ["fire", "move", "use_item", "pass", "buy", "sell", "ready"]:
		assert_gt(_kinds.get(kind, 0) as int, MATCHES / 10, "legal %s actions were exercised" % kind)
	var missing: Array[String] = []
	for key: String in ERROR_KEYS:
		if MATCHES >= 150 and key != "tank_dead" and not _hits.has(key):  # tank_dead needs a dead current tank (unreachable through play)
			missing.append(key)
	assert_eq(missing, [] as Array[String], "error keys never produced by the fuzz")
	assert_gte(_weapons_fired.size(), 20 if MATCHES >= 150 else 10, "(nearly) every weapon was fired")
	assert_lt(ms, 90000 * MATCHES / 200, "fuzz stays within its time budget")
