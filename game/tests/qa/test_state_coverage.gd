@warning_ignore_start("integer_division")
extends GutTest
## Serialization coverage (docs/ARCHITECTURE.md sections 14, 22, 24). The tests enumerate the
## script variables of TankState / MatchState / MatchSettings with get_property_list(), so a
## field added later without being hashed or saved fails here without anyone editing this file:
##  - every field changes the fingerprint when mutated (it is hashed),
##  - every field survives SaveCodec encode -> decode with extreme values,
##  - a match replays from settings + action log alone (the save/online contract).

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")


## Names of the script variables of `obj`.
func _fields(obj: Object) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in obj.get_property_list():
		if (p["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			out.append(p["name"])
	return out


func _rich_state() -> MatchState:
	var s := MatchSettings.new()
	s.seed = 424242
	s.num_tanks = 3
	s.rounds = 3
	s.start_money = 90000
	var state: MatchState = Simulation.new_match(s)
	var bot := Rng.new(9)
	for _i: int in range(60):
		var a: Dictionary = M3.next_action(state, bot)
		if a.is_empty():
			break
		M3.apply(state, a)
		if state.phase == SimConstants.PHASE_AIM and state.turn_number >= 4:
			break
	assert_not_null(state.terrain, "a round is under way")
	return state


## Returns true if `field` of `obj` could be mutated (the mutation is applied in place).
func _mutate(obj: Object, field: String) -> bool:
	var v: Variant = obj.get(field)
	match typeof(v):
		TYPE_INT:
			obj.set(field, (v as int) + 1)
		TYPE_BOOL:
			obj.set(field, not (v as bool))
		TYPE_STRING:
			obj.set(field, SimConstants.PHASE_SHOP if v != SimConstants.PHASE_SHOP else SimConstants.PHASE_AIM)
		TYPE_PACKED_INT32_ARRAY:
			var a: PackedInt32Array = (v as PackedInt32Array).duplicate()
			a[0] += 1
			obj.set(field, a)
		TYPE_PACKED_INT64_ARRAY:
			var b: PackedInt64Array = (v as PackedInt64Array).duplicate()
			b[0] += 1
			obj.set(field, b)
		_:
			return false
	return true


func test_every_field_changes_the_fingerprint() -> void:
	var base: MatchState = _rich_state()
	var fp: String = Simulation.fingerprint(base)
	var covered: Array[String] = []
	var unknown: Array[String] = []
	# MatchState scalars and arrays.
	for f: String in _fields(base):
		var s: MatchState = base.duplicate_state()
		if _mutate(s, f):
			covered.append("MatchState." + f)
			assert_ne(Simulation.fingerprint(s), fp, "MatchState.%s is not part of the fingerprint" % f)
			continue
		match f:
			"settings", "tanks":
				pass  # covered below
			"terrain":
				covered.append("MatchState.terrain")
				s.terrain.cells[12345] = (s.terrain.cells[12345] + 1) % 16
				assert_ne(Simulation.fingerprint(s), fp, "terrain cells are not fingerprinted")
				var s2: MatchState = base.duplicate_state()
				s2.terrain = null
				assert_ne(Simulation.fingerprint(s2), fp, "a missing terrain is fingerprinted")
			"wells":
				covered.append("MatchState.wells")
				s.wells.append({"owner": 2, "x": 100, "y": 200, "expires_turn": 9})
				var with_well: String = Simulation.fingerprint(s)
				assert_ne(with_well, fp, "wells are not fingerprinted")
				for key: String in ["owner", "x", "y", "expires_turn"]:
					var s3: MatchState = s.duplicate_state()
					s3.wells[0][key] = (s3.wells[0][key] as int) + 1
					assert_ne(Simulation.fingerprint(s3), with_well, "well.%s is not fingerprinted" % key)
			_:
				unknown.append("MatchState." + f)
	# Settings.
	for f: String in _fields(base.settings):
		var s4: MatchState = base.duplicate_state()
		if _mutate(s4.settings, f):
			covered.append("MatchSettings." + f)
			assert_ne(Simulation.fingerprint(s4), fp, "MatchSettings.%s is not part of the fingerprint" % f)
		else:
			unknown.append("MatchSettings." + f)
	# Every tank, every field.
	for ti: int in range(base.tanks.size()):
		for f: String in _fields(base.tanks[ti]):
			var s5: MatchState = base.duplicate_state()
			if _mutate(s5.tanks[ti], f):
				if ti == 0:
					covered.append("TankState." + f)
				assert_ne(Simulation.fingerprint(s5), fp, "TankState.%s of tank %d is not part of the fingerprint" % [f, ti])
			else:
				unknown.append("TankState." + f)
	assert_eq(unknown, [] as Array[String], "fields of a type this test cannot mutate: extend _mutate()")
	gut.p("fingerprint covers %d fields" % covered.size())
	assert_gt(covered.size(), 30)
	# Per-entry inventory sensitivity (every catalog slot, not just slot 0).
	for i: int in range(Catalog.count()):
		var s6: MatchState = base.duplicate_state()
		s6.tanks[1].inventory[i] += 1
		assert_ne(Simulation.fingerprint(s6), fp, "inventory slot %d (%s) is not fingerprinted" % [i, Catalog.id_at(i)])


func _same_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	return a == b


## Every field survives encode -> decode, with values at the edge of what the format stores.
func test_every_field_survives_save_load_with_extreme_values() -> void:
	var state: MatchState = _rich_state()
	state.settings.seed = -(1 << 62)
	state.settings.start_money = 1_000_000
	state.settings.wind_max = 100
	state.settings.full_unlocked = false
	state.settings.controllers = PackedInt32Array([4, 0, 3])
	state.seed = 9223372036854775807
	state.round_index = 2
	state.wind = -100
	state.wind_rng_state = PackedInt64Array([4294967295, 0, 1, 2147483648])
	state.turn_number = 2000000000
	state.current_tank = 2
	state.wells = [{"owner": 0, "x": 0, "y": -300, "expires_turn": 2000000001},
			{"owner": 2, "x": 1599, "y": 899, "expires_turn": 7}] as Array[Dictionary]
	for t: TankState in state.tanks:
		t.team = 7 - t.id
		t.color_index = 5 + t.id
		t.x = 12 + 700 * t.id
		t.y = 300 + 100 * t.id
		t.health = [100, 1, 57][t.id]
		t.alive = t.id != 1
		t.angle = [0, 1800, 901][t.id]
		t.power = [1, 1000, 333][t.id]
		t.money = 1 << 40
		t.kills = 100000
		t.damage_dealt = 1 << 35
		t.round_wins = 19
		t.ready = t.id == 2
		t.fuel = 2000000000
		t.shield_type = [-1, 27, 22][t.id]
		t.shield_hp = [0, 100, 1][t.id]
		t.repulsor_charge = 100 * t.id
		t.last_fire_angle = [1800, 0, 901][t.id]
		t.last_fire_power = [1000, 1, 333][t.id]
		t.last_fire_weapon = [Catalog.count() - 1, 0, 7][t.id]
		t.last_fire_x = [1599, -1, 800][t.id]
		t.last_fire_y = [899, 0, -1][t.id]
		t.last_fire_wind = [-100, 100, 0][t.id]
		t.last_fire_turn = [2000000000, 0, 17][t.id]
		for i: int in range(Catalog.count()):
			t.inventory[i] = (i * 7 + t.id * 11) % 100
	# These values fill the binary format to its limits, which is more than the simulation can ever produce
	# (a shield_type that is not a shield, fuel 2e9, ...): SaveCodec.decode now refuses such a state, so the
	# format round trip is exercised on StateSerial directly.
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))
	assert_false(res["ok"], "decode refuses a state the simulation cannot produce")
	assert_eq(res["error"], "invalid_state")
	var buf := StreamPeerBuffer.new()
	StateSerial.write(buf, state)
	buf.seek(0)
	var got: MatchState = StateSerial.read(buf)
	assert_not_null(got, "the snapshot format itself holds the extreme values")
	if got == null:
		return
	for f: String in _fields(state):
		match f:
			"settings":
				for sf: String in _fields(state.settings):
					assert_true(_same_value(got.settings.get(sf), state.settings.get(sf)), "settings.%s: %s vs %s" % [sf, str(got.settings.get(sf)), str(state.settings.get(sf))])
			"tanks":
				assert_eq(got.tanks.size(), state.tanks.size())
				for i: int in range(state.tanks.size()):
					for tf: String in _fields(state.tanks[i]):
						assert_true(_same_value(got.tanks[i].get(tf), state.tanks[i].get(tf)), "tank %d.%s: %s vs %s" % [i, tf, str(got.tanks[i].get(tf)), str(state.tanks[i].get(tf))])
			"terrain":
				assert_eq(got.terrain.width, state.terrain.width)
				assert_eq(got.terrain.height, state.terrain.height)
				assert_true(got.terrain.cells == state.terrain.cells, "terrain bytes")
			"wells":
				assert_eq(str(got.wells), str(state.wells))
			_:
				assert_true(_same_value(got.get(f), state.get(f)), "%s: %s vs %s" % [f, str(got.get(f)), str(state.get(f))])
	assert_eq(Simulation.fingerprint(got), Simulation.fingerprint(state))


## A state without terrain (the first shop) and a finished match also round-trip field by field.
func test_shop_and_match_over_states_round_trip() -> void:
	var shop: MatchState = Simulation.new_match(QaUtil.settings(5, 4, 2))
	shop.tanks[2].money = 123
	shop.tanks[1].ready = true
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(shop, [] as Array[Dictionary]))
	assert_true(res["ok"])
	var got: MatchState = res["state"]
	assert_null(got.terrain, "no terrain in the first shop")
	assert_eq(got.phase, SimConstants.PHASE_SHOP)
	assert_eq(got.round_index, -1)
	assert_eq(got.tanks[2].money, 123)
	assert_true(got.tanks[1].ready)
	var s := MatchSettings.new()
	s.seed = 3
	s.num_tanks = 2
	s.rounds = 1
	var over: MatchState = Simulation.new_match(s)
	var bot := Rng.new(3)
	for _i: int in range(600):
		var a: Dictionary = M3.next_action(over, bot)
		if a.is_empty():
			break
		M3.apply(over, a)
	assert_eq(over.phase, SimConstants.PHASE_MATCH_OVER)
	var res2: Dictionary = SaveCodec.decode(SaveCodec.encode(over, [] as Array[Dictionary]))
	assert_true(res2["ok"])
	assert_eq(Simulation.fingerprint(res2["state"] as MatchState), Simulation.fingerprint(over))
	assert_eq((res2["state"] as MatchState).phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(Simulation.standings(res2["state"] as MatchState), Simulation.standings(over))


## Saves = settings + seed + action list: replaying the decoded log through a fresh new_match (calling
## start_round whenever everyone is ready) reproduces the final state, and every prefix of it.
func test_a_match_replays_from_settings_and_action_log_alone() -> void:
	var t0: int = Time.get_ticks_msec()
	var checked: int = 0
	for m: int in range(5):
		var s := MatchSettings.new()
		s.seed = 700 + m * 31
		s.num_tanks = 2 + m % 4
		s.rounds = 1 + m % 2
		s.start_money = [10000, 25000, 4000][m % 3]
		var state: MatchState = Simulation.new_match(s)
		var bot := Rng.new(m)
		var log: Array[Dictionary] = []
		var mid_fp: String = ""
		var mid_len: int = -1
		for step: int in range(1200):
			var a: Dictionary = M3.next_action(state, bot)
			if a.is_empty():
				break
			M3.apply(state, a)
			if a["kind"] != M3.START_ROUND:
				log.append(a)
			if step == 40 and not Simulation.all_ready(state):
				mid_fp = Simulation.fingerprint(state)
				mid_len = log.size()
		var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, log))
		assert_true(res["ok"], "match %d saves" % m)
		if not res["ok"]:
			continue
		var decoded: MatchState = res["state"]
		var replay: MatchState = Simulation.new_match(decoded.settings)
		var actions: Array[Dictionary] = res["actions"]
		var mid_ok: bool = mid_len < 0
		for i: int in range(actions.size()):
			if i == mid_len and mid_len >= 0:
				assert_eq(Simulation.fingerprint(replay), mid_fp, "match %d: replay matches the live state after %d actions" % [m, mid_len])
				mid_ok = true
			var ev: Array[Dictionary] = Simulation.apply_action(replay, actions[i])
			if ev.is_empty():
				fail_test("match %d: logged action %d (%s) was refused on replay (%s)" % [m, i, str(actions[i]), Simulation.validate_action(replay, actions[i])])
				return
			if Simulation.all_ready(replay):
				Simulation.start_round(replay)
		assert_true(mid_ok)
		assert_eq(Simulation.fingerprint(replay), Simulation.fingerprint(state), "match %d: replaying the action log reproduces the final state" % m)
		assert_eq(replay.phase, state.phase)
		checked += 1
	assert_eq(checked, 5)
	gut.p("REPLAY FROM LOG: %d matches in %d ms" % [checked, Time.get_ticks_msec() - t0])
