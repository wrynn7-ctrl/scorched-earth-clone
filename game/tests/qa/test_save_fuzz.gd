@warning_ignore_start("integer_division")
extends GutTest
## Save/load fuzz (docs/ARCHITECTURE.md section 22). 60 seeded matches played by the shopping
## bot. At random points the live state is saved, decoded and the DECODED state continues in
## parallel with the original: fingerprints and timeline digests must match at every later
## step, with every action round-tripped through JSON + normalize_action first. Then
## corruption fuzz: flipped bytes and truncations must make decode return ok=false, never crash.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const MATCHES: int = 60
const STEPS_AFTER_SPLIT: int = 10  # compared steps per match once the first save point is passed
const ROOT_SEED: int = 0x5A7E0000
const KNOWN_ERRORS: Array[String] = ["too_short", "bad_magic", "bad_version", "corrupt", "fingerprint", "invalid_state"]


func _settings(m: int) -> MatchSettings:
	var rng := Rng.new(ROOT_SEED ^ (m * 7919))
	var s := MatchSettings.new()
	s.seed = rng.next_u32() if m % 5 != 0 else -int(rng.next_u32())
	s.num_tanks = rng.range_int(2, 5) if m % 9 != 0 else 8
	s.rounds = rng.range_int(1, 3)
	s.wind_max = [100, 100, 50, 0, 100][m % 5]
	s.start_money = [10000, 25000, 3000, 60000, 0, 12000][m % 6]
	s.full_unlocked = m % 11 != 5
	return s


func _json_roundtrip(action: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(action))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return Simulation.normalize_action(parsed as Dictionary)


func _decode_copy(state: MatchState, log: Array[Dictionary], tag: String, reencode: bool = true) -> MatchState:
	var bytes: PackedByteArray = SaveCodec.encode(state, log)
	var res: Dictionary = SaveCodec.decode(bytes)
	if not res["ok"]:
		fail_test("%s: decode of a fresh encode failed: %s" % [tag, res["error"]])
		return null
	var copy: MatchState = res["state"]
	if Simulation.fingerprint(copy) != Simulation.fingerprint(state):
		fail_test("%s: decoded fingerprint differs from the saved state" % tag)
		return null
	if JSON.stringify(res["actions"]) != JSON.stringify(log):
		fail_test("%s: decoded action log differs" % tag)
		return null
	if reencode and SaveCodec.encode(copy, res["actions"] as Array[Dictionary]) != bytes:
		fail_test("%s: re-encoding the decoded save is not byte-identical" % tag)
		return null
	return copy


func test_decoded_state_continues_identically_60_matches() -> void:
	var t0: int = Time.get_ticks_msec()
	var splits: int = 0
	var compared: int = 0
	var failures: Array[String] = []
	var overs: int = 0
	for m: int in range(MATCHES):
		var settings: MatchSettings = _settings(m)
		var tag: String = "match %d (seed %d, %d tanks, %d rounds, money %d)" % [m, settings.seed, settings.num_tanks,
				settings.rounds, settings.start_money]
		var state: MatchState = Simulation.new_match(settings)
		var bot := Rng.new(ROOT_SEED + m)
		var split_rng := Rng.new((ROOT_SEED + m) * 31)
		var log: Array[Dictionary] = []
		var copy: MatchState = null
		var next_split: int = split_rng.range_int(0, 40)
		var after: int = 0  # steps played since the first save point
		for step: int in range(400):
			if after >= STEPS_AFTER_SPLIT:
				break
			if step == next_split:
				copy = _decode_copy(state, log, "%s step %d" % [tag, step], splits % 3 == 0)
				if copy == null:
					return
				splits += 1
				next_split = step + split_rng.range_int(8, 16)
			var action: Dictionary = M3.next_action(state, bot)
			if action.is_empty():
				overs += 1
				break
			var ev_a: Array[Dictionary] = M3.apply(state, action)
			if action["kind"] != M3.START_ROUND:
				log.append(action)
			if copy == null:
				continue
			var ev_b: Array[Dictionary] = M3.apply(copy, _json_roundtrip(action) if action["kind"] != M3.START_ROUND else action)
			compared += 1
			after += 1
			if QaUtil.events_digest(ev_a) != QaUtil.events_digest(ev_b):
				failures.append("%s step %d (%s): timelines differ" % [tag, step, str(action)])
				break
			var fa: String = Simulation.fingerprint(state)
			var fb: String = Simulation.fingerprint(copy)
			if fa != fb:
				failures.append("%s step %d (%s): fingerprints diverge %s vs %s" % [tag, step, str(action), fa, fb])
				break
		if failures.size() > 5:
			break
		if true:
			# The copy that ran alongside (or the original, if no save point came up) also survives a final save/load.
			var fin: MatchState = _decode_copy(copy if copy != null else state, log, "%s final" % tag)
			if fin == null:
				return
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("SAVE FUZZ: %d matches, %d splits, %d compared steps, %d played to match_over in %d ms" % [MATCHES, splits, compared, overs, ms])
	assert_eq(failures.size(), 0, "save/load divergences:\n%s" % "\n".join(failures))
	assert_gt(splits, 60, "plenty of save points")
	assert_gt(compared, 500, "plenty of compared steps")
	assert_lt(ms, SimTestUtil.perf_budget(90000), "stays within its time budget")


## A mid-round save of a bot match: returns {state, log}.
func _midround(seed_value: int, tanks: int, steps: int) -> Dictionary:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = tanks
	s.rounds = 3
	s.start_money = 30000
	var state: MatchState = Simulation.new_match(s)
	var bot := Rng.new(seed_value + 1)
	var log: Array[Dictionary] = []
	for _i: int in range(steps):
		var action: Dictionary = M3.next_action(state, bot)
		if action.is_empty():
			break
		M3.apply(state, action)
		if action["kind"] != M3.START_ROUND:
			log.append(action)
	return {"state": state, "log": log}


## A deterministic mid-round (aim phase) state with a few turns played.
func _aim_state(seed_value: int) -> MatchState:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = 3
	s.rounds = 3
	s.start_money = 30000
	var state: MatchState = Simulation.new_match(s)
	var bot := Rng.new(seed_value + 1)
	for _i: int in range(300):
		var action: Dictionary = M3.next_action(state, bot)
		if action.is_empty():
			break
		M3.apply(state, action)
		if state.phase == SimConstants.PHASE_AIM and state.turn_number >= 2:
			break
	return state


func _seal(body: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if body.size() > 0:
		ctx.update(body)
	var out: PackedByteArray = body.duplicate()
	out.append_array(ctx.finish())
	return out


func _assert_rejected(bytes: PackedByteArray, what: String, failures: Array[String]) -> void:
	var res: Dictionary = SaveCodec.decode(bytes)
	if res["ok"]:
		failures.append("%s: decode accepted it" % what)
	elif not KNOWN_ERRORS.has(res["error"]):
		failures.append("%s: unknown error key '%s'" % [what, res["error"]])
	elif res["state"] != null:
		failures.append("%s: failed decode still returned a state" % what)


func test_corruption_fuzz_flips_and_truncations_never_decode() -> void:
	var t0: int = Time.get_ticks_msec()
	var rng := Rng.new(0xC0221)
	var failures: Array[String] = []
	var decodes: int = 0
	var cases: Array[Dictionary] = [
		{"state": Simulation.new_match(QaUtil.settings(5, 3, 2)), "log": [] as Array[Dictionary], "n": 400},
		_midround(77, 3, 40),
		_midround(78, 6, 90),
	]
	for ci: int in range(cases.size()):
		var state: MatchState = cases[ci]["state"]
		var log: Array[Dictionary] = []
		log.assign(cases[ci]["log"])
		var bytes: PackedByteArray = SaveCodec.encode(state, log)
		var fp: String = Simulation.fingerprint(state)
		var big: bool = state.terrain != null
		var rounds: int = 28 if big else 300
		# Unsealed: any change breaks the SHA-256 trailer.
		for _i: int in range(rounds):
			var b: PackedByteArray = bytes.duplicate()
			b[rng.range_int(0, b.size() - 1)] ^= rng.range_int(1, 255)
			_assert_rejected(b, "case %d flipped byte" % ci, failures)
			decodes += 1
		for _i: int in range(rounds):
			_assert_rejected(bytes.slice(0, rng.range_int(0, bytes.size() - 1)), "case %d truncated" % ci, failures)
			decodes += 1
		for n: int in [1, 2, 31, 32, 33, 1000]:
			var padded: PackedByteArray = bytes.duplicate()
			padded.resize(bytes.size() + n)
			_assert_rejected(padded, "case %d padded by %d" % [ci, n], failures)
			decodes += 1
		# Re-sealed (valid SHA-256): flips inside the state snapshot must be caught by the
		# structure checks or the fingerprint, unless the decoded state is identical anyway
		# (e.g. a boolean stored as 1 -> 3).
		var snap_len: int = StateSerial.serialize(state).size()
		var body: PackedByteArray = bytes.slice(0, bytes.size() - SaveCodec.SUM_LEN)
		for _i: int in range(rounds):
			var b2: PackedByteArray = body.duplicate()
			var pos: int = rng.range_int(8, 8 + snap_len - 1)
			b2[pos] ^= rng.range_int(1, 255)
			var res: Dictionary = SaveCodec.decode(_seal(b2))
			decodes += 1
			if res["ok"] and Simulation.fingerprint(res["state"] as MatchState) != fp:
				failures.append("case %d: re-sealed flip at %d produced a DIFFERENT accepted state" % [ci, pos])
			elif not res["ok"] and not KNOWN_ERRORS.has(res["error"]):
				failures.append("case %d: unknown error key '%s'" % [ci, res["error"]])
		# Re-sealed flips in the JSON / fingerprint tail: only "no crash, sane result" is required.
		for _i: int in range(rounds):
			var b3: PackedByteArray = body.duplicate()
			b3[rng.range_int(8 + snap_len, b3.size() - 1)] ^= rng.range_int(1, 255)
			var res3: Dictionary = SaveCodec.decode(_seal(b3))
			decodes += 1
			if res3["ok"] and Simulation.fingerprint(res3["state"] as MatchState) != fp:
				failures.append("case %d: tail flip changed the state" % ci)
		# Re-sealed truncations of the body.
		for _i: int in range(rounds):
			var cut: int = rng.range_int(0, body.size() - 1)
			_assert_rejected(_seal(body.slice(0, cut)), "case %d re-sealed truncation at %d" % [ci, cut], failures)
			decodes += 1
	var ms: int = Time.get_ticks_msec() - t0
	# Invalid JSON in a re-sealed action log makes JSON.parse_string print an engine error. decode() still
	# returns ok=false; those lines are acknowledged (and counted) here so GUT does not fail on log noise.
	var noise: int = 0
	for e: GutTrackedError in get_errors():
		if e.code.contains("error != Error::OK"):
			e.handled = true
			noise += 1
	gut.p("CORRUPTION FUZZ: %d decodes in %d ms (%d engine error lines from corrupt JSON)" % [decodes, ms, noise])
	assert_eq(failures.size(), 0, "corruption fuzz failures:\n%s" % "\n".join(failures.slice(0, 20)))
	assert_lt(ms, SimTestUtil.perf_budget(60000), "stays within its time budget")


func test_decode_of_garbage_inputs() -> void:
	var rng := Rng.new(99)
	var failures: Array[String] = []
	var sizes: Array[int] = [0, 1, 3, 4, 8, 15, 52, 56, 57, 100, 5000]
	for n: int in sizes:
		var b: PackedByteArray = PackedByteArray()
		b.resize(n)
		_assert_rejected(b, "zeros(%d)" % n, failures)
		for i: int in range(n):
			b[i] = rng.range_int(0, 255)
		_assert_rejected(b, "random(%d)" % n, failures)
		# Right magic and version, garbage after: still a clean failure.
		if n >= 8:
			var c: PackedByteArray = b.duplicate()
			c.encode_u8(0, 0x43)
			c.encode_u8(1, 0x52)
			c.encode_u8(2, 0x54)
			c.encode_u8(3, 0x4C)
			c.encode_u32(4, SaveCodec.SAVE_VERSION)
			_assert_rejected(c, "magic+version+random(%d)" % n, failures)
			_assert_rejected(_seal(c), "sealed magic+version+random(%d)" % n, failures)
	assert_eq(failures.size(), 0, "garbage decode failures:\n%s" % "\n".join(failures))
	assert_eq(SaveCodec.decode(PackedByteArray())["error"], "too_short")
	var good: PackedByteArray = SaveCodec.encode(Simulation.new_match(QaUtil.settings(1, 2)), [] as Array[Dictionary])
	var wrong_magic: PackedByteArray = good.duplicate()
	wrong_magic[0] = 0x58
	assert_eq(SaveCodec.decode(wrong_magic)["error"], "bad_magic")
	var wrong_ver: PackedByteArray = good.duplicate()
	wrong_ver.encode_u32(4, SaveCodec.SAVE_VERSION + 1)
	assert_eq(SaveCodec.decode(wrong_ver)["error"], "bad_version")


## The action log is the JSON of the actions: floats from JSON come back as ints, strings and
## unusual-but-legal keys survive, and an empty log works.
func test_action_log_roundtrip_types() -> void:
	var state: MatchState = Simulation.new_match(QaUtil.settings(3, 2))
	var log: Array[Dictionary] = [
		{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 2},
		{"kind": "fire", "tank": 1, "angle": 1800, "power": 1000, "weapon": "supernova"},
		{"kind": "move", "tank": 0, "dx": -200},
		{"kind": "use_item", "tank": 1, "item": "glow_shield"},
	]
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
	assert_true(res["ok"])
	var actions: Array[Dictionary] = res["actions"]
	assert_eq(actions.size(), 4)
	for i: int in range(4):
		for k: String in log[i]:
			assert_eq(typeof(actions[i][k]), typeof(log[i][k]), "action %d key %s keeps its type" % [i, k])
			assert_eq(actions[i][k], log[i][k])
	var empty: Dictionary = SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))
	assert_true(empty["ok"])
	assert_eq((empty["actions"] as Array).size(), 0)


## SHA-256 only detects accidental corruption (anyone can re-seal), but a save that decodes ok=true into a
## state the simulation can never produce is a soft-lock waiting to happen (e.g. current_tank 99: every action
## answers not_your_turn). decode() validates structure, the fingerprint and (StateSerial.validate) the ranges.
func test_decode_validates_the_ranges_of_the_state_it_returns() -> void:
	var base: MatchState = _aim_state(1234)
	assert_eq(base.phase, SimConstants.PHASE_AIM, "a mid-round state")
	var cases: Dictionary = {
		"current_tank 99 during aim": func(st: MatchState) -> void: st.current_tank = 99,
		"current_tank -1 during aim": func(st: MatchState) -> void: st.current_tank = -1,
		"shield_type 999": func(st: MatchState) -> void:
			st.tanks[0].shield_type = 999
			st.tanks[0].shield_hp = 5,
		"health 5000": func(st: MatchState) -> void: st.tanks[1].health = 5000,
		"negative inventory": func(st: MatchState) -> void: st.tanks[0].inventory[3] = -7,
		"inventory above the 99 cap": func(st: MatchState) -> void: st.tanks[0].inventory[3] = 5000,
		"spark_dart stored": func(st: MatchState) -> void: st.tanks[0].inventory[0] = 4,
		"settings.num_tanks does not match the tanks": func(st: MatchState) -> void: st.settings.num_tanks = 7,
		"terrain 10 columns wide": func(st: MatchState) -> void:
			st.terrain.width = 10
			st.terrain.cells.resize(10 * 900),
		"well of a non-existent owner": func(st: MatchState) -> void: st.wells = [{"owner": 40, "x": 5, "y": 5, "expires_turn": 3}] as Array[Dictionary],
		"tank hit box outside the map": func(st: MatchState) -> void: st.tanks[2].x = -500,
		"round_index beyond the rounds": func(st: MatchState) -> void: st.round_index = 77,
	}
	var accepted: Array[String] = []
	for name: String in cases:
		var st: MatchState = base.duplicate_state()
		(cases[name] as Callable).call(st)
		var res: Dictionary = SaveCodec.decode(SaveCodec.encode(st, [] as Array[Dictionary]))
		if res["ok"]:
			accepted.append(name)
	assert_eq(accepted, [] as Array[String], "decode must refuse states the simulation can never produce")
	var res0: Dictionary = SaveCodec.decode(SaveCodec.encode(base, [] as Array[Dictionary]))
	assert_true(res0["ok"], "the untampered state still decodes")


## A re-sealed save whose action log is not valid JSON is rejected with "corrupt". (JSON.parse_string prints an
## engine ERROR line for it: log noise only, acknowledged here because GUT counts engine errors as failures.)
func test_invalid_json_in_the_action_log_is_rejected_as_corrupt() -> void:
	var st: MatchState = _aim_state(1234)
	var log: Array[Dictionary] = [{"kind": "pass", "tank": 0}]
	var bytes: PackedByteArray = SaveCodec.encode(st, log)
	var body: PackedByteArray = bytes.slice(0, bytes.size() - SaveCodec.SUM_LEN)
	var json_at: int = body.size() - SaveCodec.FP_LEN - JSON.stringify(log).length()
	for junk: String in ["{\"kind\":", "[1,2,3", "nonsense!!!!", "{\"a\":1}  ", "[[]]    "]:
		var b: PackedByteArray = body.slice(0, json_at)
		var j: PackedByteArray = junk.to_ascii_buffer()
		# Keep the length field consistent so the failure is the JSON itself.
		b.encode_u32(json_at - 4, j.size())
		b.append_array(j)
		b.append_array(body.slice(body.size() - SaveCodec.FP_LEN))
		var res: Dictionary = SaveCodec.decode(_seal(b))
		assert_false(res["ok"], "'%s' is not a valid action log" % junk)
		assert_eq(res["error"], "corrupt", "'%s'" % junk)
	var noise: int = 0
	for e: GutTrackedError in get_errors():
		if e.code.contains("error != Error::OK"):
			e.handled = true
			noise += 1
	gut.p("invalid JSON decodes logged %d engine error line(s)" % noise)
