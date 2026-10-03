@warning_ignore_start("integer_division")
extends RefCounted
## M5 QA helpers (not a test file). Load with `const M5 = preload("res://tests/qa/qa_m5.gd")`.
##
## Holds the Love Edition match driver (scripted "human" hearts or CPU turns, with the per-action
## audit), hand-built flat love duels, and small helpers shared by the M5 test files.

const QaUtil = preload("res://tests/qa/qa_util.gd")

const LOVE_ALLOWED_TYPES: Array[String] = ["fire", "projectile", "projectile_end", "heart_burst", "love",
		"round_end", "wind", "turn"]
const MAX_ACTIONS: int = 500
const WIND_TURN: Array[String] = ["wind", "turn"]
const ROUND_END: Array[String] = ["round_end"]

## Environment knob for the long fuzz: QA_M5_SCALE=3 runs three times as many matches.
static func scale() -> int:
	var v: String = OS.get_environment("QA_M5_SCALE")
	return maxi(1, int(v)) if v.is_valid_int() else 1


## Fingerprint of everything except the terrain bytes (0.2 ms instead of 7.5 ms). Together with a
## byte-for-byte terrain comparison it carries the same information as Simulation.fingerprint.
static func lite_fp(state: MatchState) -> String:
	var b: PackedByteArray = StateSerial.serialize(state)
	var tail: int = 0 if state.terrain == null else state.terrain.cells.size()
	return StateSerial.hash_hex(b.slice(0, b.size() - tail))


# --- settings and states ------------------------------------------------------------------------

static func love_settings(seed_value: int, ctrl0: int, ctrl1: int, wind_max: int = 100) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.mode = SimConstants.MODE_LOVE
	s.wind_max = wind_max
	s.controllers = PackedInt32Array([ctrl0, ctrl1])
	return s


## A love duel on flat ground (solid from y = 600), tanks at `xs`, wind `wind`, one round, no money.
static func flat_love(xs: Array[int], wind: int = 0) -> MatchState:
	var s: MatchState = QaUtil.flat_state(xs, 600, 1)
	s.settings.mode = SimConstants.MODE_LOVE
	s.settings.wind_max = SimConstants.LOVE_WIND_MAX
	s.settings.start_money = 0
	s.wind = wind
	for t: TankState in s.tanks:
		t.inventory = Catalog.new_inventory()
	return s


static func heart(tank: int, angle: int, power: int) -> Dictionary:
	return {"kind": "fire", "tank": tank, "angle": angle, "power": power, "weapon": "heart"}


## Fresh aim phase for the next adversarial shot on a reused flat love state.
static func reset_duel(s: MatchState, shooter: int, wind: int) -> void:
	s.phase = SimConstants.PHASE_AIM
	s.current_tank = shooter
	s.wind = wind
	s.turn_number = 0
	for t: TankState in s.tanks:
		t.love = 0
		t.round_wins = 0
		t.reset_last_fire()


## A scripted human: a heart aimed at the opponent with the flat-ground range formula and two
## refinement traces, with some wild shots and the odd pass. Uses only `rng`.
static func scripted_action(state: MatchState, rng: Rng) -> Dictionary:
	var me: TankState = state.tanks[state.current_tank]
	var foe: TankState = state.tanks[1 - me.id]
	var roll: int = rng.range_int(0, 15)
	if roll == 0:
		return {"kind": "pass", "tank": me.id}
	if roll <= 2:
		return heart(me.id, rng.range_int(0, SimConstants.MAX_ANGLE), rng.range_int(1, SimConstants.MAX_POWER))
	var angle: int = rng.range_int(300, 700) if foe.x >= me.x else rng.range_int(1100, 1500)
	var dist: int = maxi(1, absi(foe.x - me.x))
	var sin2: int = maxi(1, absi(FixedMath.sin10(2 * angle)))
	var power: int = clampi(FixedMath.isqrt(519 * dist * FixedMath.ONE / sin2), 10, SimConstants.MAX_POWER)
	for _i: int in range(2):
		var tr: Dictionary = Ballistics.trace(state, me.id, angle, power, "heart", SimConstants.WIND_USE_STATE,
				SimConstants.MAX_FLIGHT_TICKS)
		var hit: int = maxi(1, absi((tr["end_x"] as int) - me.x))
		power = clampi(FixedMath.isqrt(power * power * dist / hit), 10, SimConstants.MAX_POWER)
	power = clampi(power + rng.range_int(-15, 15), SimConstants.MIN_POWER, SimConstants.MAX_POWER)
	return heart(me.id, angle, power)


# --- the per-action audit -----------------------------------------------------------------------

## Checks one resolved love action against section 37 and section 10. `love_before` is the meters
## before the action. Returns violations (empty = fine).
static func audit_love_action(state: MatchState, action: Dictionary, events: Array[Dictionary],
		love_before: Array[int], terrain_ref: PackedByteArray) -> Array[String]:
	var errs: Array[String] = []
	var ts: Array[String] = QaUtil.types(events)
	var shooter: int = action["tank"]
	var other: int = 1 - shooter
	for t: String in ts:
		if not LOVE_ALLOWED_TYPES.has(t):
			errs.append("forbidden event type '%s' in love mode" % t)
	errs.append_array(QaUtil.check_event_fields(events))
	for e: Dictionary in events:
		if e.has("cause") or e["type"] == "damage" or e["type"] == "money":
			errs.append("damage/money event in love mode: %s" % str(e["type"]))
	# Structure.
	if action["kind"] == "pass":
		if ts != WIND_TURN:
			errs.append("pass timeline %s" % str(ts))
	else:
		if ts.size() < 3 or ts[0] != "fire" or ts[1] != "projectile" or ts[2] != "projectile_end":
			errs.append("fire timeline starts %s" % str(ts.slice(0, 3)))
		else:
			var end: Dictionary = events[2]
			var impact: bool = ["terrain", "tank", "shield"].has(end["reason"])
			var bursts: int = ts.count("heart_burst")
			if bursts != (1 if impact else 0):
				errs.append("%d heart_burst(s) for end reason %s" % [bursts, end["reason"]])
			if impact and bursts == 1:
				var b: Dictionary = events[3]
				if b["type"] != "heart_burst" or b["x"] != end["x"] or b["y"] != end["y"] or b["radius"] != 30:
					errs.append("heart_burst %s does not match the end %s" % [str(b), str(end)])
			var tail: Array[String] = ts.slice(3 if not impact else 4)
			while not tail.is_empty() and tail[0] == "love":
				tail.pop_front()
			var won: bool = tail == ROUND_END
			var went_on: bool = tail == WIND_TURN
			if not won and not went_on:
				errs.append("timeline tail %s" % str(tail))
			if won != (state.phase == SimConstants.PHASE_MATCH_OVER):
				errs.append("round_end %s but phase %s" % [str(won), state.phase])
	# Love events and meters.
	var expect: Array[int] = [love_before[0], love_before[1]]
	var last_tank: int = -1
	for e: Dictionary in QaUtil.find(events, "love"):
		var t: int = e["tank"]
		if t == shooter:
			errs.append("the shooter gained love")
		if e["from"] != shooter:
			errs.append("love.from %d != shooter %d" % [e["from"], shooter])
		if t <= last_tank:
			errs.append("love events out of id order")
		last_tank = t
		var amt: int = e["amount"]
		if amt < 1 or amt > 34:
			errs.append("love amount %d" % amt)
		expect[t] += amt
		if e["love"] != expect[t]:
			errs.append("love.love %d != running total %d" % [e["love"], expect[t]])
	for i: int in range(2):
		var t: TankState = state.tanks[i]
		if t.love != expect[i]:
			errs.append("tank %d love %d != expected %d" % [i, t.love, expect[i]])
		if t.love < 0 or t.love > SimConstants.LOVE_MAX:
			errs.append("tank %d love %d out of 0..100" % [i, t.love])
		if t.health != SimConstants.MAX_HEALTH or not t.alive or t.money != 0 or t.kills != 0 or t.damage_dealt != 0:
			errs.append("tank %d changed health/money/kills in love mode" % i)
	if state.terrain.cells != terrain_ref:
		errs.append("terrain bytes changed")
	# Outcome.
	var rend: Array[Dictionary] = QaUtil.find(events, "round_end")
	if rend.size() == 1:
		if rend[0]["winner"] != shooter:
			errs.append("round_end.winner %d is not the shooter %d" % [rend[0]["winner"], shooter])
		if state.tanks[other].love != SimConstants.LOVE_MAX or state.tanks[shooter].love >= SimConstants.LOVE_MAX:
			errs.append("winner %d did not fill the other meter (%d / %d)" % [shooter, state.tanks[shooter].love,
					state.tanks[other].love])
		if state.phase != SimConstants.PHASE_MATCH_OVER:
			errs.append("phase %s after the win" % state.phase)
		if Simulation.standings(state)[0] != shooter:
			errs.append("standings do not put the winner first")
	elif rend.size() == 0:
		if state.tanks[0].love >= SimConstants.LOVE_MAX or state.tanks[1].love >= SimConstants.LOVE_MAX:
			errs.append("a meter is full but no round_end")
		if state.phase != SimConstants.PHASE_AIM or state.current_tank != other:
			errs.append("no win: phase %s current %d (expected aim, %d)" % [state.phase, state.current_tank, other])
	else:
		errs.append("%d round_end events" % rend.size())
	if action["kind"] == "fire" and state.tanks[shooter].last_fire_weapon != Catalog.HEART_INDEX:
		errs.append("last_fire_weapon %d" % state.tanks[shooter].last_fire_weapon)
	if absi(state.wind) > SimConstants.LOVE_WIND_MAX:
		errs.append("wind %d beyond the love cap" % state.wind)
	errs.append_array(QaUtil.check_invariants(state))
	return errs


## Every action kind love mode must refuse, with the expected error, for the current tank.
static func illegal_probes(state: MatchState) -> Array[String]:
	var errs: Array[String] = []
	var me: int = state.current_tank
	var probes: Array[Dictionary] = [
		{"kind": "move", "tank": me, "dx": 5},
		{"kind": "use_item", "tank": me, "item": "glow_shield"},
		{"kind": "buy", "tank": me, "item": "pulse_missile", "qty": 1},
		{"kind": "sell", "tank": me, "item": "pulse_missile", "qty": 1},
		{"kind": "ready", "tank": me},
	]
	for p: Dictionary in probes:
		var e: String = Simulation.validate_action(state, p)
		if e != "bad_mode":
			errs.append("%s -> '%s' (expected bad_mode)" % [p["kind"], e])
	for w: String in ["spark_dart", "pulse_missile", "nova_core", "supernova", "nope"]:
		var e: String = Simulation.validate_action(state, {"kind": "fire", "tank": me, "angle": 450, "power": 500,
				"weapon": w})
		var want: String = "unknown_weapon" if w == "nope" else "bad_mode"
		if e != want:
			errs.append("fire %s -> '%s' (expected %s)" % [w, e, want])
	var other: String = Simulation.validate_action(state, heart(1 - me, 450, 500))
	if other != "not_your_turn":
		errs.append("heart by the other tank -> '%s'" % other)
	return errs
