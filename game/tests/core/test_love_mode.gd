@warning_ignore_start("integer_division")
extends GutTest
## Love Edition (docs/ARCHITECTURE.md section 37): settings, flow, the heart weapon, validation,
## serialization and determinism.

const SHOOTER: int = 0
const TARGET: int = 1
const ALLOWED_EVENTS: Array[String] = ["fire", "projectile", "projectile_end", "heart_burst", "love", "round_end",
		"wind", "turn"]


func _love_settings(seed_value: int = 7) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.mode = SimConstants.MODE_LOVE
	s.wind_max = 20
	return s


## A love duel on flat ground with no wind: tank 0 at x = 300, tank 1 at x = 500.
func _flat_love() -> MatchState:
	var s: MatchState = SimTestUtil.flat_state(2)
	s.settings.mode = SimConstants.MODE_LOVE
	s.settings.rounds = 1
	s.settings.wind_max = 0
	s.settings.start_money = 0
	s.tanks[TARGET].x = 500
	for t: TankState in s.tanks:
		t.inventory = Catalog.new_inventory()
	return s


func _heart(tank: int, angle: int, power: int) -> Dictionary:
	return {"kind": "fire", "tank": tank, "angle": angle, "power": power, "weapon": "heart"}


## Searches the power at 45 degrees (135 for a shooter on the right) for a shell that ends in
## `want_reason` within [d_lo, d_hi] cells of the target box. Returns the heart action.
func _find_shot(s: MatchState, want_reason: String, d_lo: int, d_hi: int) -> Dictionary:
	var shooter: TankState = s.tanks[s.current_tank]
	var target: TankState = s.tanks[1 - s.current_tank]
	var angle: int = 450 if target.x > shooter.x else 1350
	for p: int in range(1, SimConstants.MAX_POWER + 1):
		var tr: Dictionary = Ballistics.trace(s, shooter.id, angle, p, "heart", 0, SimConstants.MAX_FLIGHT_TICKS)
		if tr["end_reason"] != want_reason:
			continue
		var d: int = Damage.distance_to_tank(tr["end_x"], tr["end_y"], target)
		if d >= d_lo and d <= d_hi:
			return _heart(shooter.id, angle, p)
	return {}


func _types(events: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in events:
		out.append(e["type"])
	return out


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e["type"] == type:
			out.append(e)
	return out


# --- constants, defs, catalog -----------------------------------------------------------------

func test_mode_constants() -> void:
	assert_eq(SimConstants.MODE_STANDARD, 0)
	assert_eq(SimConstants.MODE_LOVE, 1)
	assert_eq(MatchSettings.new().mode, SimConstants.MODE_STANDARD, "standard by default")


func test_heart_def_lives_outside_the_catalog() -> void:
	assert_true(WeaponDefs.has("heart"))
	var def: Dictionary = WeaponDefs.get_def("heart")
	assert_eq(def["behavior"], "love")
	assert_eq(def["r"], 30)
	assert_eq(def["amount"], 34)
	assert_true(def["unlimited"])
	assert_eq(WeaponDefs.DEFS.size(), 21, "the shop weapons are unchanged")
	assert_false(Catalog.IDS.has("heart"))
	assert_false(Catalog.has("heart"))
	assert_eq(Catalog.index_of("heart"), -1)
	assert_eq(Catalog.HEART_INDEX, -2)
	assert_eq(Catalog.fire_index("heart"), -2)
	assert_eq(Catalog.fire_index("pulse_missile"), 1)
	assert_eq(Catalog.fire_index("nope"), -1)
	assert_eq(Catalog.count(), 28, "inventories keep their size")


func test_save_version_bumped() -> void:
	assert_gte(SaveCodec.SAVE_VERSION, 3)


# --- settings -------------------------------------------------------------------------------------

func test_clamp_forces_love_settings() -> void:
	var s := MatchSettings.new()
	s.mode = SimConstants.MODE_LOVE
	s.num_tanks = 6
	s.rounds = 9
	s.wind_max = 90
	s.start_money = 5000
	var c: MatchSettings = s.clamped()
	assert_eq(c.mode, SimConstants.MODE_LOVE)
	assert_eq(c.num_tanks, 2)
	assert_eq(c.rounds, 1)
	assert_eq(c.wind_max, SimConstants.LOVE_WIND_MAX)
	assert_eq(c.start_money, 0)
	assert_eq(c.controllers.size(), 2, "controllers follow the forced tank count")


func test_clamp_keeps_a_small_wind_and_the_other_fields() -> void:
	var s := MatchSettings.new()
	s.mode = SimConstants.MODE_LOVE
	s.wind_max = 12
	s.seed = -99
	s.full_unlocked = false
	s.controllers = PackedInt32Array([4, 3, 2, 1])
	var c: MatchSettings = s.clamped()
	assert_eq(c.wind_max, 12)
	assert_eq(c.seed, -99)
	assert_false(c.full_unlocked)
	assert_eq(c.controllers, PackedInt32Array([2, 2]), "free version caps CPU levels at Normal")
	s.wind_max = -5
	assert_eq(s.clamped().wind_max, 0)


func test_clamp_mode_range_and_standard_untouched() -> void:
	var s := MatchSettings.new()
	s.num_tanks = 5
	s.rounds = 7
	s.wind_max = 90
	s.start_money = 5000
	s.mode = 99
	assert_eq(s.clamped().mode, SimConstants.MODE_LOVE, "an out-of-range mode clamps into 0..1")
	s.mode = -4
	var c: MatchSettings = s.clamped()
	assert_eq(c.mode, SimConstants.MODE_STANDARD)
	assert_eq([c.num_tanks, c.rounds, c.wind_max, c.start_money], [5, 7, 90, 5000])


func test_duplicate_settings_copies_mode() -> void:
	var s := MatchSettings.new()
	s.mode = SimConstants.MODE_LOVE
	assert_eq(s.duplicate_settings().mode, SimConstants.MODE_LOVE)
	var m: MatchState = Simulation.new_match(_love_settings())
	assert_eq(m.duplicate_state().settings.mode, SimConstants.MODE_LOVE)


# --- flow -----------------------------------------------------------------------------------------

func test_new_match_skips_the_shop() -> void:
	var st := MatchSettings.new()
	st.seed = 3
	st.mode = SimConstants.MODE_LOVE
	st.num_tanks = 5
	st.start_money = 9000
	var m: MatchState = Simulation.new_match(st)
	assert_eq(m.phase, SimConstants.PHASE_AIM)
	assert_eq(m.round_index, 0)
	assert_not_null(m.terrain)
	assert_eq(m.tanks.size(), 2)
	assert_eq(m.current_tank, 0)
	assert_eq(m.turn_number, 0)
	for t: TankState in m.tanks:
		assert_eq(t.love, 0)
		assert_eq(t.money, 0)
		assert_true(t.alive)
		assert_eq(t.health, SimConstants.MAX_HEALTH)
	assert_lte(absi(m.wind), SimConstants.LOVE_WIND_MAX)
	assert_eq(Simulation.validate_action(m, {"kind": "pass", "tank": 0}), "")
	assert_eq(StateSerial.validate(m), "")


func test_standard_new_match_still_opens_the_shop() -> void:
	var st := MatchSettings.new()
	var m: MatchState = Simulation.new_match(st)
	assert_eq(m.phase, SimConstants.PHASE_SHOP)
	assert_null(m.terrain)
	for t: TankState in m.tanks:
		assert_eq(t.love, 0)


func test_start_round_does_nothing_in_love_mode() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	assert_false(Simulation.all_ready(m))
	assert_eq(Simulation.start_round(m).size(), 0)
	assert_eq(m.round_index, 0)


func test_same_seed_same_start() -> void:
	var a: MatchState = Simulation.new_match(_love_settings(11))
	var b: MatchState = Simulation.new_match(_love_settings(11))
	assert_eq(Simulation.fingerprint(a), Simulation.fingerprint(b))
	assert_ne(Simulation.fingerprint(a), Simulation.fingerprint(Simulation.new_match(_love_settings(12))))


# --- the heart ------------------------------------------------------------------------------------

func test_direct_hit_gives_full_amount_and_event_order() -> void:
	var s: MatchState = _flat_love()
	var act: Dictionary = _find_shot(s, "tank", 0, 0)
	assert_false(act.is_empty(), "a direct-hit shot exists")
	assert_eq(Simulation.validate_action(s, act), "")
	var ev: Array[Dictionary] = Simulation.apply_action(s, act)
	assert_eq(_types(ev), ["fire", "projectile", "projectile_end", "heart_burst", "love", "wind", "turn"])
	var burst: Dictionary = _of(ev, "heart_burst")[0]
	assert_eq(burst["radius"], 30)
	var love: Dictionary = _of(ev, "love")[0]
	assert_eq(love["tank"], TARGET)
	assert_eq(love["from"], SHOOTER)
	assert_eq(love["amount"], 34)
	assert_eq(love["love"], 34)
	assert_eq(s.tanks[TARGET].love, 34)
	assert_eq(s.tanks[SHOOTER].love, 0)
	assert_eq(s.current_tank, TARGET, "the turn passes")
	assert_eq(s.turn_number, 1)
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	assert_eq(s.tanks[SHOOTER].last_fire_weapon, Catalog.HEART_INDEX)
	assert_eq(s.tanks[SHOOTER].last_fire_power, act["power"])
	var pe: Dictionary = _of(ev, "projectile_end")[0]
	assert_eq(s.tanks[SHOOTER].last_fire_x, pe["x"])
	assert_eq(StateSerial.validate(s), "", "a love state with a heart in last_fire is valid")


func test_falloff_matches_the_damage_curve() -> void:
	var s: MatchState = _flat_love()
	var act: Dictionary = _find_shot(s, "terrain", 5, 25)
	assert_false(act.is_empty(), "a near-miss shot exists")
	var ev: Array[Dictionary] = Simulation.apply_action(s, act)
	var burst: Dictionary = _of(ev, "heart_burst")[0]
	var d: int = Damage.distance_to_tank(burst["x"], burst["y"], s.tanks[TARGET])
	assert_between(d, 5, 25)
	var loves: Array[Dictionary] = _of(ev, "love")
	assert_eq(loves.size(), 1)
	var want: int = maxi(1, 34 * (30 - d) / 30)
	assert_eq(loves[0]["amount"], want)
	assert_lt(want, 34)


func test_edge_of_the_radius_gives_the_minimum_and_outside_nothing() -> void:
	var s: MatchState = _flat_love()
	# Distance 29 gives max(1, 34 * 1 / 30) = 1.
	var act: Dictionary = _find_shot(s, "terrain", 29, 29)
	if act.is_empty():
		# A power step can skip an exact distance: fall back to the largest distance inside.
		act = _find_shot(s, "terrain", 27, 29)
	assert_false(act.is_empty())
	var ev: Array[Dictionary] = Simulation.apply_action(s, act)
	assert_eq(_of(ev, "love").size(), 1)
	assert_lte(_of(ev, "love")[0]["amount"], 3)
	assert_gte(_of(ev, "love")[0]["amount"], 1)
	# Beyond r: a burst but no love.
	var s2: MatchState = _flat_love()
	var far: Dictionary = _find_shot(s2, "terrain", 31, 80)
	assert_false(far.is_empty())
	var ev2: Array[Dictionary] = Simulation.apply_action(s2, far)
	assert_eq(_of(ev2, "heart_burst").size(), 1)
	assert_eq(_of(ev2, "love").size(), 0)
	assert_eq(s2.tanks[TARGET].love, 0)


func test_self_hit_gives_nothing() -> void:
	var s: MatchState = _flat_love()
	s.tanks[TARGET].x = 1400
	# Straight up, the shell lands back on the shooter.
	var ev: Array[Dictionary] = Simulation.apply_action(s, _heart(SHOOTER, 900, 300))
	assert_eq(_of(ev, "heart_burst").size(), 1, "it still bursts")
	assert_eq(_of(ev, "love").size(), 0)
	assert_eq(s.tanks[SHOOTER].love, 0)
	assert_eq(s.tanks[TARGET].love, 0)
	assert_eq(s.current_tank, TARGET)
	assert_eq(s.phase, SimConstants.PHASE_AIM)


func test_self_hit_next_to_the_opponent_only_loves_the_opponent() -> void:
	var s: MatchState = _flat_love()
	s.tanks[TARGET].x = 330
	var ev: Array[Dictionary] = Simulation.apply_action(s, _heart(SHOOTER, 900, 300))
	var loves: Array[Dictionary] = _of(ev, "love")
	assert_eq(loves.size(), 1)
	assert_eq(loves[0]["tank"], TARGET)
	assert_eq(s.tanks[SHOOTER].love, 0)



func test_lost_shell_only_passes_the_turn() -> void:
	var s: MatchState = _flat_love()
	var ev: Array[Dictionary] = Simulation.apply_action(s, _heart(SHOOTER, 1200, 1000))
	assert_eq(_of(ev, "projectile_end")[0]["reason"], "lost")
	assert_eq(_types(ev), ["fire", "projectile", "projectile_end", "wind", "turn"])
	assert_eq(s.current_tank, TARGET)
	assert_eq(s.tanks[TARGET].love, 0)
	assert_eq(s.tanks[SHOOTER].last_fire_x, -1)


func test_pass_just_passes_the_turn() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	var ev: Array[Dictionary] = Simulation.apply_action(m, {"kind": "pass", "tank": 0})
	assert_eq(_types(ev), ["wind", "turn"])
	assert_eq(m.current_tank, 1)
	assert_eq(m.phase, SimConstants.PHASE_AIM)


func test_hearts_never_change_terrain_bytes() -> void:
	var s: MatchState = _flat_love()
	var before: PackedByteArray = s.terrain.cells.duplicate()
	var shots: Array[Dictionary] = [
		_find_shot(s, "tank", 0, 0), _find_shot(s, "terrain", 1, 25), _heart(SHOOTER, 1200, 1000),
		_heart(SHOOTER, 900, 300), _heart(SHOOTER, 450, 1000)]
	for shot: Dictionary in shots:
		assert_false(shot.is_empty())
		s.current_tank = SHOOTER
		for e: Dictionary in Simulation.apply_action(s, shot):
			assert_true(ALLOWED_EVENTS.has(e["type"]), "unexpected event %s" % e["type"])
		assert_eq(s.terrain.cells, before, "terrain bytes after %s" % str(shot))
		s.tanks[TARGET].love = 0
		s.phase = SimConstants.PHASE_AIM


func test_real_terrain_hearts_leave_terrain_alone() -> void:
	var m: MatchState = Simulation.new_match(_love_settings(21))
	var before: PackedByteArray = m.terrain.cells.duplicate()
	var rng := Rng.new(5)
	for _i: int in range(12):
		if m.phase != SimConstants.PHASE_AIM:
			break
		var act: Dictionary = _heart(m.current_tank, rng.range_int(0, 1800), rng.range_int(100, 1000))
		assert_eq(Simulation.validate_action(m, act), "")
		Simulation.apply_action(m, act)
		assert_eq(m.terrain.cells, before)
	assert_eq(StateSerial.validate(m), "")


func test_show_replay_invariant() -> void:
	# The show layer re-applies terrain_* events to its own copy and compares fingerprints.
	# Hearts emit none, so a replica that applies nothing must still match the authority.
	var m: MatchState = Simulation.new_match(_love_settings(33))
	var replica: Terrain = m.terrain.duplicate_terrain()
	var rng := Rng.new(8)
	for _i: int in range(10):
		if m.phase != SimConstants.PHASE_AIM:
			break
		var act: Dictionary = _heart(m.current_tank, rng.range_int(0, 1800), rng.range_int(100, 1000))
		for e: Dictionary in Simulation.apply_action(m, act):
			assert_false(String(e["type"]).begins_with("terrain"), "no terrain events")
			assert_ne(e["type"], "tunnel")
			assert_ne(e["type"], "explosion")
	var after := StreamPeerBuffer.new()
	m.terrain.write_bytes(after)
	var before := StreamPeerBuffer.new()
	replica.write_bytes(before)
	assert_eq(after.data_array, before.data_array)


func test_third_hit_caps_at_100_and_the_shooter_wins() -> void:
	var s: MatchState = _flat_love()
	var act: Dictionary = _find_shot(s, "tank", 0, 0)
	var amounts: Array[int] = []
	var last: Array[Dictionary] = []
	for round_i: int in range(3):
		s.current_tank = SHOOTER
		last = Simulation.apply_action(s, act)
		for e: Dictionary in _of(last, "love"):
			amounts.append(e["amount"])
		if round_i < 2:
			assert_eq(s.phase, SimConstants.PHASE_AIM)
			assert_eq(_of(last, "round_end").size(), 0)
	assert_eq(amounts, [34, 34, 32], "the last gain is capped at 100")
	assert_eq(s.tanks[TARGET].love, 100)
	assert_eq(_types(last), ["fire", "projectile", "projectile_end", "heart_burst", "love", "round_end"])
	assert_eq(_of(last, "round_end")[0]["winner"], SHOOTER)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	assert_eq(Simulation.standings(s)[0], SHOOTER)


func test_the_winner_is_the_shooter_even_when_shooting_from_the_right() -> void:
	var s: MatchState = _flat_love()
	s.current_tank = TARGET
	s.tanks[SHOOTER].love = 90
	var act: Dictionary = _find_shot(s, "tank", 0, 0)
	assert_false(act.is_empty())
	var ev: Array[Dictionary] = Simulation.apply_action(s, act)
	assert_eq(_of(ev, "love")[0]["amount"], 10)
	assert_eq(_of(ev, "round_end")[0]["winner"], TARGET)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)


func test_match_over_accepts_nothing() -> void:
	var s: MatchState = _flat_love()
	s.tanks[TARGET].love = 99
	var act: Dictionary = _find_shot(s, "tank", 0, 0)
	Simulation.apply_action(s, act)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	var fp: String = Simulation.fingerprint(s)
	for a: Dictionary in [act, {"kind": "pass", "tank": 0}, {"kind": "pass", "tank": 1}]:
		assert_eq(Simulation.validate_action(s, a), "bad_phase")
		assert_eq(Simulation.apply_action(s, a).size(), 0)
	assert_eq(Simulation.fingerprint(s), fp)


# --- validation -----------------------------------------------------------------------------------

func test_love_mode_rejects_everything_but_heart_and_pass() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	var actions: Array[Dictionary] = [
		{"kind": "move", "tank": 0, "dx": 5},
		{"kind": "use_item", "tank": 0, "item": "glow_shield"},
		{"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1},
		{"kind": "sell", "tank": 0, "item": "pulse_missile", "qty": 1},
		{"kind": "ready", "tank": 0},
		{"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "spark_dart"},
		{"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "pulse_missile"},
	]
	var fp: String = Simulation.fingerprint(m)
	for a: Dictionary in actions:
		assert_eq(Simulation.validate_action(m, a), "bad_mode", str(a))
		assert_eq(Simulation.apply_action(m, a).size(), 0)
	assert_eq(Simulation.fingerprint(m), fp, "nothing changed")
	assert_eq(Simulation.validate_action(m, _heart(0, 450, 500)), "")
	assert_eq(Simulation.validate_action(m, {"kind": "pass", "tank": 0}), "")


func test_love_mode_other_validation_still_applies() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	assert_eq(Simulation.validate_action(m, _heart(1, 450, 500)), "not_your_turn")
	assert_eq(Simulation.validate_action(m, _heart(0, 1801, 500)), "bad_angle")
	assert_eq(Simulation.validate_action(m, _heart(0, -1, 500)), "bad_angle")
	assert_eq(Simulation.validate_action(m, _heart(0, 450, 0)), "bad_power")
	assert_eq(Simulation.validate_action(m, _heart(0, 450, 1001)), "bad_power")
	assert_eq(Simulation.validate_action(m, _heart(5, 450, 500)), "bad_tank")
	assert_eq(Simulation.validate_action(m, {"kind": "fire", "tank": 0, "angle": 450, "power": 500, "weapon": "nope"}),
			"unknown_weapon")
	assert_eq(Simulation.validate_action(m, {"kind": "dance", "tank": 0}), "unknown_kind")
	assert_eq(Simulation.validate_action(m, {"kind": "fire", "tank": 0, "angle": 450, "power": 500}), "bad_field")


func test_heart_is_invalid_in_standard_mode() -> void:
	var st := MatchSettings.new()
	st.seed = 4
	var m: MatchState = Simulation.new_match(st)
	for t: TankState in m.tanks:
		Simulation.apply_action(m, {"kind": "ready", "tank": t.id})
	Simulation.start_round(m)
	assert_eq(m.phase, SimConstants.PHASE_AIM)
	assert_eq(Simulation.validate_action(m, _heart(0, 450, 500)), "unknown_weapon")
	assert_eq(Simulation.apply_action(m, _heart(0, 450, 500)).size(), 0)
	assert_eq(m.turn_number, 0)
	assert_eq(Simulation.validate_action(m, {"kind": "fire", "tank": 0, "angle": 450, "power": 500,
			"weapon": "spark_dart"}), "")


func test_heart_cannot_be_bought_sold_or_used_in_standard_mode() -> void:
	var st := MatchSettings.new()
	var m: MatchState = Simulation.new_match(st)
	assert_eq(Simulation.validate_action(m, {"kind": "buy", "tank": 0, "item": "heart", "qty": 1}), "unknown_item")
	assert_eq(Simulation.validate_action(m, {"kind": "sell", "tank": 0, "item": "heart", "qty": 1}), "unknown_item")
	for t: TankState in m.tanks:
		Simulation.apply_action(m, {"kind": "ready", "tank": t.id})
	Simulation.start_round(m)
	assert_eq(Simulation.validate_action(m, {"kind": "use_item", "tank": 0, "item": "heart"}), "unknown_item")


# --- state serialization --------------------------------------------------------------------------

func _played_love_match(seed_value: int) -> MatchState:
	var m: MatchState = Simulation.new_match(_love_settings(seed_value))
	var rng := Rng.new(seed_value)
	var guard: int = 0
	while m.phase == SimConstants.PHASE_AIM and guard < 12:
		guard += 1
		Simulation.apply_action(m, _heart(m.current_tank, rng.range_int(300, 1500), rng.range_int(200, 1000)))
	return m


func test_fingerprint_covers_mode_and_love() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	var fp: String = Simulation.fingerprint(m)
	var a: MatchState = m.duplicate_state()
	a.tanks[1].love = 1
	assert_ne(Simulation.fingerprint(a), fp)
	var b: MatchState = m.duplicate_state()
	b.settings.mode = SimConstants.MODE_STANDARD
	assert_ne(Simulation.fingerprint(b), fp)
	assert_eq(Simulation.fingerprint(m.duplicate_state()), fp)


func test_save_round_trip_with_love_values() -> void:
	var m: MatchState = Simulation.new_match(_love_settings(5))
	m.tanks[0].love = 41
	m.tanks[1].love = 99
	var actions: Array[Dictionary] = [_heart(0, 450, 500)]
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(m, actions))
	assert_true(res["ok"], str(res["error"]))
	var got: MatchState = res["state"]
	assert_eq(got.settings.mode, SimConstants.MODE_LOVE)
	assert_eq(got.tanks[0].love, 41)
	assert_eq(got.tanks[1].love, 99)
	assert_eq(Simulation.fingerprint(got), Simulation.fingerprint(m))
	assert_eq((res["actions"] as Array[Dictionary])[0]["weapon"], "heart")


func test_save_round_trip_after_a_played_match() -> void:
	for seed_value: int in [1, 2, 3, 4, 5, 6]:
		var m: MatchState = _played_love_match(seed_value)
		var res: Dictionary = SaveCodec.decode(SaveCodec.encode(m, [] as Array[Dictionary]))
		assert_true(res["ok"], "seed %d: %s" % [seed_value, str(res["error"])])
		var got: MatchState = res["state"]
		assert_eq(Simulation.fingerprint(got), Simulation.fingerprint(m))
		assert_eq(got.tanks[0].last_fire_weapon, m.tanks[0].last_fire_weapon)


func test_save_round_trip_of_a_finished_match() -> void:
	var s: MatchState = _flat_love()
	s.tanks[TARGET].love = 99
	Simulation.apply_action(s, _find_shot(s, "tank", 0, 0))
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
	var bytes: PackedByteArray = SaveCodec.encode(s, [] as Array[Dictionary])
	var res: Dictionary = SaveCodec.decode(bytes)
	# flat_state has no Simulation-seeded wind stream, so only check the format-level outcome.
	if res["ok"]:
		assert_eq(res["state"].tanks[TARGET].love, 100)
	else:
		assert_eq(res["error"], "invalid_state")
	var buf := StreamPeerBuffer.new()
	StateSerial.write(buf, s)
	buf.seek(0)
	var back: MatchState = StateSerial.read(buf)
	assert_not_null(back)
	assert_eq(back.tanks[TARGET].love, 100)
	assert_eq(back.tanks[SHOOTER].last_fire_weapon, Catalog.HEART_INDEX)


func test_old_save_versions_are_rejected() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	var bytes: PackedByteArray = SaveCodec.encode(m, [] as Array[Dictionary])
	bytes.encode_u32(4, 2)
	assert_eq(SaveCodec.decode(bytes)["error"], "bad_version")


func test_validate_accepts_fresh_states() -> void:
	assert_eq(StateSerial.validate(Simulation.new_match(_love_settings())), "")
	for seed_value: int in [1, 2, 3]:
		assert_eq(StateSerial.validate(_played_love_match(seed_value)), "", "seed %d" % seed_value)


func test_validate_rejects_bad_love_meters() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	for bad: int in [101, 1000, -1, -100]:
		var s: MatchState = m.duplicate_state()
		s.tanks[1].love = bad
		assert_ne(StateSerial.validate(s), "", "love %d" % bad)
		assert_eq(SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))["error"], "invalid_state")
	var full: MatchState = m.duplicate_state()
	full.tanks[0].love = 100
	assert_ne(StateSerial.validate(full), "", "a full meter means the match is over")
	full.phase = SimConstants.PHASE_MATCH_OVER
	assert_eq(StateSerial.validate(full), "")
	var empty_over: MatchState = m.duplicate_state()
	empty_over.phase = SimConstants.PHASE_MATCH_OVER
	assert_ne(StateSerial.validate(empty_over), "", "match_over needs a full meter in love mode")


func test_validate_rejects_love_in_a_standard_match() -> void:
	var st := MatchSettings.new()
	st.seed = 9
	var m: MatchState = Simulation.new_match(st)
	for t: TankState in m.tanks:
		Simulation.apply_action(m, {"kind": "ready", "tank": t.id})
	Simulation.start_round(m)
	assert_eq(StateSerial.validate(m), "")
	for v: int in [1, 50, 100]:
		var s: MatchState = m.duplicate_state()
		s.tanks[0].love = v
		assert_ne(StateSerial.validate(s), "", "love %d in standard mode" % v)
		assert_eq(SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))["error"], "invalid_state")
	var heart: MatchState = m.duplicate_state()
	heart.tanks[0].last_fire_weapon = Catalog.HEART_INDEX
	heart.tanks[0].last_fire_angle = 450
	heart.tanks[0].last_fire_power = 500
	heart.tanks[0].last_fire_turn = 0
	assert_ne(StateSerial.validate(heart), "", "a heart was never fired in a standard match")


func test_validate_rejects_bad_mode_settings() -> void:
	var m: MatchState = Simulation.new_match(_love_settings())
	var bad_mode: MatchState = m.duplicate_state()
	bad_mode.settings.mode = 2
	assert_ne(StateSerial.validate(bad_mode), "")
	bad_mode.settings.mode = -1
	assert_ne(StateSerial.validate(bad_mode), "")
	var wind: MatchState = m.duplicate_state()
	wind.settings.wind_max = 31
	wind.wind = 0
	assert_ne(StateSerial.validate(wind), "", "love wind_max over 30")
	var money: MatchState = m.duplicate_state()
	money.settings.start_money = 1
	assert_ne(StateSerial.validate(money), "", "love start_money")
	var rounds: MatchState = m.duplicate_state()
	rounds.settings.rounds = 2
	assert_ne(StateSerial.validate(rounds), "", "love rounds")
	var shop: MatchState = m.duplicate_state()
	shop.phase = SimConstants.PHASE_SHOP
	shop.round_index = -1
	shop.terrain = null
	assert_ne(StateSerial.validate(shop), "", "love has no shop")
	var catalog_weapon: MatchState = m.duplicate_state()
	catalog_weapon.tanks[0].last_fire_weapon = 1
	catalog_weapon.tanks[0].last_fire_angle = 450
	catalog_weapon.tanks[0].last_fire_power = 500
	catalog_weapon.tanks[0].last_fire_turn = 0
	assert_ne(StateSerial.validate(catalog_weapon), "", "only the heart is fired in love mode")


# --- determinism ----------------------------------------------------------------------------------

func _script(seed_value: int) -> Array[String]:
	var m: MatchState = Simulation.new_match(_love_settings(seed_value))
	var prints: Array[String] = [Simulation.fingerprint(m)]
	var rng := Rng.new(seed_value * 31 + 1)
	var guard: int = 0
	while m.phase == SimConstants.PHASE_AIM and guard < 40:
		guard += 1
		var act: Dictionary
		if rng.chance(1, 8):
			act = {"kind": "pass", "tank": m.current_tank}
		else:
			act = _heart(m.current_tank, rng.range_int(300, 1500), rng.range_int(150, 1000))
		Simulation.apply_action(m, act)
		prints.append(Simulation.fingerprint(m))
	return prints


func test_same_seed_and_actions_give_identical_fingerprints() -> void:
	for seed_value: int in [1, 7, 42]:
		var a: Array[String] = _script(seed_value)
		var b: Array[String] = _script(seed_value)
		assert_gt(a.size(), 3)
		assert_eq(a, b, "seed %d" % seed_value)
	assert_ne(_script(1), _script(2))


## The power (step 8) whose shell ends closest to the opponent, at 45 degrees toward it.
func _best_shot(m: MatchState) -> Dictionary:
	var shooter: TankState = m.tanks[m.current_tank]
	var other: TankState = m.tanks[1 - m.current_tank]
	var angle: int = 450 if other.x > shooter.x else 1350
	var best: Dictionary = _heart(shooter.id, angle, 500)
	var best_d: int = 1 << 40
	for p: int in range(100, 1001, 8):
		var tr: Dictionary = Ballistics.trace(m, shooter.id, angle, p, "heart", SimConstants.WIND_USE_STATE,
				SimConstants.MAX_FLIGHT_TICKS)
		if not WeaponResolver.is_impact(tr["end_reason"]):
			continue
		var d: int = Damage.distance_to_tank(tr["end_x"], tr["end_y"], other)
		if d < best_d:
			best_d = d
			best = _heart(shooter.id, angle, p)
	return best


func test_an_aimed_duel_reaches_a_winner() -> void:
	var m: MatchState = Simulation.new_match(_love_settings(3))
	var winner: int = -1
	for _i: int in range(40):
		if m.phase != SimConstants.PHASE_AIM:
			break
		var shooter: int = m.current_tank
		var ev: Array[Dictionary] = Simulation.apply_action(m, _best_shot(m))
		if m.phase == SimConstants.PHASE_MATCH_OVER:
			winner = _of(ev, "round_end")[0]["winner"]
			assert_eq(winner, shooter)
	assert_eq(m.phase, SimConstants.PHASE_MATCH_OVER, "a duel of aimed hearts ends")
	assert_eq(maxi(m.tanks[0].love, m.tanks[1].love), 100)
	assert_eq(m.tanks[winner].love < 100, true, "the winner is not the one who filled up")
	assert_eq(StateSerial.validate(m), "")
	assert_eq(Simulation.standings(m)[0], winner)
