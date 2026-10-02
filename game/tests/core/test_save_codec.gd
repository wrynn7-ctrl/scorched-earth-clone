extends GutTest
## SaveCodec (docs/ARCHITECTURE.md section 22): encode / decode, corruption, versions.

const U = preload("res://tests/core/sim_test_util.gd")


func _midgame() -> MatchState:
	var s: MatchState = U.shop_state(3, 4, 4242)
	s.settings.full_unlocked = false
	for t: TankState in s.tanks:
		Simulation.apply_action(s, U.buy(t.id, "pulse_missile", 2))
	Simulation.apply_action(s, U.buy(0, "glow_shield", 1))
	Simulation.apply_action(s, U.buy(1, "fuel_cell", 2))
	Simulation.apply_action(s, U.buy(2, "drift_chute", 2))
	U.begin_round(s)
	Simulation.apply_action(s, U.use_item(0, "glow_shield"))
	Simulation.apply_action(s, U.fire(0, 450, 700))
	s.wells.append({"owner": 1, "x": 700, "y": 300, "expires_turn": 9})
	s.tanks[2].repulsor_charge = 37
	s.tanks[1].fuel = 12
	return s


func _actions() -> Array[Dictionary]:
	return [
		U.buy(0, "pulse_missile", 2), U.sell(1, "fuel_cell", 1), U.ready(2), U.use_item(0, "glow_shield"),
		U.move(1, -14), U.fire(0, 452, 610), U.pass_turn(2),
	]


func test_encode_decode_gives_the_same_fingerprint() -> void:
	var s: MatchState = _midgame()
	var bytes: PackedByteArray = SaveCodec.encode(s, _actions())
	var res: Dictionary = SaveCodec.decode(bytes)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(res["error"], "")
	var back: MatchState = res["state"]
	assert_eq(Simulation.fingerprint(back), Simulation.fingerprint(s))
	assert_eq(back.phase, s.phase)
	assert_eq(back.round_index, s.round_index)
	assert_eq(back.tanks.size(), 3)
	for i: int in range(3):
		assert_eq(back.tanks[i].inventory, s.tanks[i].inventory)
		assert_eq(back.tanks[i].money, s.tanks[i].money)
		assert_eq(back.tanks[i].shield_hp, s.tanks[i].shield_hp)
	assert_eq(back.wells, s.wells)
	assert_eq(back.settings.full_unlocked, false)
	assert_true(back.terrain.cells == s.terrain.cells)
	assert_eq(back.wind_rng_state, s.wind_rng_state)


func test_decoded_state_keeps_playing_identically() -> void:
	var s: MatchState = _midgame()
	var back: MatchState = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))["state"]
	for i: int in range(6):
		var a: Dictionary = U.fire(s.current_tank, 300 + i * 150, 500 + i * 60)
		var ea: Array[Dictionary] = Simulation.apply_action(s, a)
		var eb: Array[Dictionary] = Simulation.apply_action(back, a)
		assert_eq(ea, eb)
		assert_eq(Simulation.fingerprint(s), Simulation.fingerprint(back))


func test_shop_state_without_terrain_roundtrips() -> void:
	var s: MatchState = U.shop_state(4, 2, 99)
	Simulation.apply_action(s, U.buy(1, "nova_core", 1))
	Simulation.apply_action(s, U.ready(3))
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, _actions()))
	assert_true(res["ok"], str(res["error"]))
	var back: MatchState = res["state"]
	assert_null(back.terrain)
	assert_eq(back.round_index, -1)
	assert_eq(back.phase, "shop")
	assert_true(back.tanks[3].ready)
	assert_eq(Simulation.fingerprint(back), Simulation.fingerprint(s))


func test_match_over_state_roundtrips() -> void:
	var s: MatchState = U.flat_state(2)
	s.settings.rounds = 1
	U.kill_all_but(s, 0)
	Simulation.apply_action(s, U.pass_turn(0))
	assert_eq(s.phase, "match_over")
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_true(res["ok"])
	assert_eq((res["state"] as MatchState).phase, "match_over")
	assert_eq(Simulation.fingerprint(res["state"]), Simulation.fingerprint(s))


func test_the_action_log_roundtrips() -> void:
	var actions: Array[Dictionary] = _actions()
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(_midgame(), actions))
	assert_true(res["ok"])
	var got: Array[Dictionary] = res["actions"]
	assert_eq(got.size(), actions.size())
	assert_eq(got, actions)
	for a: Dictionary in got:
		for k: String in ["tank", "angle", "power", "dx", "qty"]:
			if a.has(k):
				assert_eq(typeof(a[k]), TYPE_INT, "%s decodes as an int (normalized)" % k)


func test_empty_action_log() -> void:
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(_midgame(), [] as Array[Dictionary]))
	assert_true(res["ok"])
	assert_eq((res["actions"] as Array[Dictionary]).size(), 0)


func test_action_log_replays_to_the_saved_state() -> void:
	var s: MatchState = U.shop_state(2, 2, 1234)
	var log: Array[Dictionary] = []
	var script: Array[Dictionary] = [
		U.buy(0, "pulse_missile", 3), U.buy(1, "pulse_missile", 3), U.buy(1, "glow_shield", 1), U.ready(0), U.ready(1),
	]
	for a: Dictionary in script:
		assert_gt(Simulation.apply_action(s, a).size(), 0)
		log.append(a)
	Simulation.start_round(s)
	var fire: Dictionary = U.fire(s.current_tank, 500, 650)
	fire["weapon"] = "pulse_missile"
	Simulation.apply_action(s, fire)
	log.append(fire)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, log))
	assert_true(res["ok"])
	# replay the decoded log on a fresh match
	var fresh: MatchState = U.shop_state(2, 2, 1234)
	for a: Dictionary in (res["actions"] as Array[Dictionary]):
		if a["kind"] == "fire":
			Simulation.start_round(fresh)
		assert_eq(Simulation.validate_action(fresh, a), "", str(a))
		Simulation.apply_action(fresh, a)
	assert_eq(Simulation.fingerprint(fresh), Simulation.fingerprint(s))


func test_a_corrupted_byte_is_rejected_everywhere() -> void:
	var bytes: PackedByteArray = SaveCodec.encode(_midgame(), _actions())
	var n: int = bytes.size()
	var positions: Array[int] = [0, 3, 4, 7, 8, 9, 20, 100, 500, 4000, n / 2, n - 32 - 16 - 3, n - 32 - 10, n - 32 - 1,
			n - 32, n - 16, n - 1]
	for pos: int in positions:
		var bad: PackedByteArray = bytes.duplicate()
		bad[pos] = bad[pos] ^ 0x01
		var res: Dictionary = SaveCodec.decode(bad)
		assert_false(res["ok"], "flipping byte %d must fail" % pos)
		assert_ne(res["error"], "", "error text at %d" % pos)
		assert_null(res["state"])


func test_every_terrain_region_byte_flip_is_caught() -> void:
	var bytes: PackedByteArray = SaveCodec.encode(_midgame(), _actions())
	var rng := Rng.new(5)
	for i: int in range(30):
		var bad: PackedByteArray = bytes.duplicate()
		var pos: int = rng.range_int(0, bytes.size() - 1)
		bad[pos] = (bad[pos] + 1 + rng.range_int(0, 254)) & 0xFF
		assert_false(SaveCodec.decode(bad)["ok"], "random corruption at %d" % pos)


func test_corruption_with_a_repaired_checksum_still_fails_the_fingerprint() -> void:
	var s: MatchState = _midgame()
	var bytes: PackedByteArray = SaveCodec.encode(s, [] as Array[Dictionary])
	var bad: PackedByteArray = bytes.duplicate()
	bad[10] = bad[10] ^ 0x40  # inside the snapshot (settings seed)
	var body: PackedByteArray = bad.slice(0, bad.size() - 32)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var fixed: PackedByteArray = body.duplicate()
	fixed.append_array(ctx.finish())
	var res: Dictionary = SaveCodec.decode(fixed)
	assert_false(res["ok"])
	assert_eq(res["error"], "fingerprint")


func test_wrong_magic_is_rejected() -> void:
	var bytes: PackedByteArray = SaveCodec.encode(_midgame(), [] as Array[Dictionary])
	assert_eq(bytes.slice(0, 4).get_string_from_ascii(), "CRTL")
	var bad: PackedByteArray = bytes.duplicate()
	bad[0] = "X".to_ascii_buffer()[0]
	var res: Dictionary = SaveCodec.decode(bad)
	assert_false(res["ok"])
	assert_eq(res["error"], "bad_magic")
	var fake: PackedByteArray = "GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE-GARBAGE".to_ascii_buffer()
	assert_eq(SaveCodec.decode(fake)["error"], "bad_magic")


func test_wrong_version_is_rejected() -> void:
	var bytes: PackedByteArray = SaveCodec.encode(_midgame(), [] as Array[Dictionary])
	var head := StreamPeerBuffer.new()
	head.data_array = bytes.slice(4, 8)
	assert_eq(head.get_32(), SaveCodec.SAVE_VERSION)
	for v: int in [0, SaveCodec.SAVE_VERSION + 1, 99]:
		var bad: PackedByteArray = bytes.duplicate()
		bad[4] = v & 0xFF
		var res: Dictionary = SaveCodec.decode(bad)
		assert_false(res["ok"], "version %d" % v)
		assert_eq(res["error"], "bad_version")


func test_truncated_and_empty_input() -> void:
	var bytes: PackedByteArray = SaveCodec.encode(_midgame(), _actions())
	assert_eq(SaveCodec.decode(PackedByteArray())["error"], "too_short")
	assert_eq(SaveCodec.decode(bytes.slice(0, 10))["error"], "too_short")
	for cut: int in [20, 1000, bytes.size() / 2, bytes.size() - 1, bytes.size() - 33]:
		var res: Dictionary = SaveCodec.decode(bytes.slice(0, cut))
		assert_false(res["ok"], "cut at %d" % cut)
	var extra: PackedByteArray = bytes.duplicate()
	extra.append(0)
	assert_false(SaveCodec.decode(extra)["ok"], "trailing byte")


func test_encoding_is_deterministic_and_does_not_change_the_state() -> void:
	var s: MatchState = _midgame()
	var before: String = Simulation.fingerprint(s)
	var a: PackedByteArray = SaveCodec.encode(s, _actions())
	var b: PackedByteArray = SaveCodec.encode(s, _actions())
	assert_eq(a, b)
	assert_eq(Simulation.fingerprint(s), before)


func test_decode_result_shape_on_failure() -> void:
	var res: Dictionary = SaveCodec.decode(PackedByteArray([1, 2, 3]))
	assert_true(res.has("ok") and res.has("error") and res.has("state") and res.has("actions"))
	assert_false(res["ok"])
	assert_null(res["state"])
	assert_eq((res["actions"] as Array).size(), 0)


func test_encode_performance_and_size() -> void:
	var s: MatchState = _midgame()
	var t0: int = Time.get_ticks_msec()
	var bytes: PackedByteArray = SaveCodec.encode(s, _actions())
	var t1: int = Time.get_ticks_msec()
	var res: Dictionary = SaveCodec.decode(bytes)
	var t2: int = Time.get_ticks_msec()
	print("PERF SaveCodec encode %d ms, decode %d ms, %d bytes" % [t1 - t0, t2 - t1, bytes.size()])
	assert_true(res["ok"])
	assert_lt(t1 - t0, SimTestUtil.perf_budget(100))
	assert_lt(t2 - t1, SimTestUtil.perf_budget(150))
