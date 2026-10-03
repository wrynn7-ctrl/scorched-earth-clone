@warning_ignore_start("integer_division")
extends GutTest
## Controllers and the last_fire_* record (docs/ARCHITECTURE.md section 27).

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")

const LAST_FIRE_FIELDS: Array[String] = ["last_fire_angle", "last_fire_power", "last_fire_weapon",
		"last_fire_x", "last_fire_y", "last_fire_wind", "last_fire_turn"]


func _settings(n: int, ctrl: Array[int], unlocked: bool = true) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = 5
	s.num_tanks = n
	s.rounds = 2
	s.full_unlocked = unlocked
	s.controllers = PackedInt32Array(ctrl)
	return s


func _fired_fields(t: TankState) -> Array[int]:
	return [t.last_fire_angle, t.last_fire_power, t.last_fire_weapon, t.last_fire_x, t.last_fire_y,
			t.last_fire_wind, t.last_fire_turn]


func _assert_reset(t: TankState, what: String) -> void:
	assert_eq(_fired_fields(t), [0, 0, -1, -1, -1, 0, -1] as Array[int], what)


func _end_of(ev: Array[Dictionary], id: int) -> Dictionary:
	for e: Dictionary in U.find(ev, "projectile_end"):
		if e["id"] == id:
			return e
	return {}


# --- controllers ------------------------------------------------------------------------------

func test_constants() -> void:
	assert_eq([SimConstants.CTRL_HUMAN, SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL,
			SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT], [0, 1, 2, 3, 4] as Array[int])


func test_default_controllers_are_all_human() -> void:
	var s := MatchSettings.new()
	assert_gte(s.controllers.size(), SimConstants.MAX_TANKS)
	for c: int in s.controllers:
		assert_eq(c, SimConstants.CTRL_HUMAN)
	var st: MatchState = Simulation.new_match(s)
	assert_eq(st.settings.controllers, PackedInt32Array([0, 0]))


func test_duplicate_settings_copies_controllers_deeply() -> void:
	var s: MatchSettings = _settings(3, [0, 2, 4])
	var d: MatchSettings = s.duplicate_settings()
	assert_eq(d.controllers, PackedInt32Array([0, 2, 4]))
	d.controllers[1] = 1
	assert_eq(s.controllers[1], 2, "the copy does not alias the original")
	var st: MatchState = Simulation.new_match(s)
	var dup: MatchState = st.duplicate_state()
	dup.settings.controllers[0] = 3
	assert_eq(st.settings.controllers[0], 0)


func test_new_match_keeps_valid_controllers() -> void:
	var st: MatchState = Simulation.new_match(_settings(4, [0, 1, 3, 4]))
	assert_eq(st.settings.controllers, PackedInt32Array([0, 1, 3, 4]))


func test_new_match_resizes_to_num_tanks() -> void:
	var longer: MatchState = Simulation.new_match(_settings(2, [2, 1, 4, 4, 4]))
	assert_eq(longer.settings.controllers, PackedInt32Array([2, 1]), "extra entries dropped")
	var shorter: MatchState = Simulation.new_match(_settings(5, [3, 2]))
	assert_eq(shorter.settings.controllers, PackedInt32Array([3, 2, 0, 0, 0]), "padded with human")
	var empty: MatchState = Simulation.new_match(_settings(3, []))
	assert_eq(empty.settings.controllers, PackedInt32Array([0, 0, 0]))


func test_new_match_clamps_values_and_num_tanks_first() -> void:
	var st: MatchState = Simulation.new_match(_settings(3, [-5, 99, 4]))
	assert_eq(st.settings.controllers, PackedInt32Array([0, 4, 4]))
	var many: MatchState = Simulation.new_match(_settings(50, [2, 2, 2, 2, 2, 2, 2, 2, 2, 2]))
	assert_eq(many.settings.num_tanks, SimConstants.MAX_TANKS)
	assert_eq(many.settings.controllers.size(), SimConstants.MAX_TANKS)
	var few: MatchState = Simulation.new_match(_settings(0, [2, 2, 2]))
	assert_eq(few.settings.num_tanks, SimConstants.MIN_TANKS)
	assert_eq(few.settings.controllers, PackedInt32Array([2, 2]))


func test_free_tier_clamps_hard_and_expert_to_normal() -> void:
	var st: MatchState = Simulation.new_match(_settings(5, [0, 1, 2, 3, 4], false))
	assert_eq(st.settings.controllers, PackedInt32Array([0, 1, 2, 2, 2]))
	var unlocked: MatchState = Simulation.new_match(_settings(5, [0, 1, 2, 3, 4], true))
	assert_eq(unlocked.settings.controllers, PackedInt32Array([0, 1, 2, 3, 4]))


func test_new_match_does_not_modify_the_callers_settings() -> void:
	var s: MatchSettings = _settings(3, [4, 9, -1], false)
	Simulation.new_match(s)
	assert_eq(s.controllers, PackedInt32Array([4, 9, -1]))


func test_controllers_are_fingerprinted_and_saved() -> void:
	var a: MatchState = Simulation.new_match(_settings(3, [0, 2, 1]))
	var b: MatchState = Simulation.new_match(_settings(3, [0, 2, 2]))
	assert_ne(Simulation.fingerprint(a), Simulation.fingerprint(b))
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(a, [] as Array[Dictionary]))
	assert_true(res["ok"], str(res["error"]))
	assert_eq((res["state"] as MatchState).settings.controllers, PackedInt32Array([0, 2, 1]))
	assert_eq(Simulation.fingerprint(res["state"]), Simulation.fingerprint(a))


# --- last_fire_* on real shots ------------------------------------------------------------------

func test_new_tanks_start_reset() -> void:
	var s: MatchState = Simulation.new_match(_settings(2, [0, 0]))
	for t: TankState in s.tanks:
		_assert_reset(t, "fresh tank")
	U.begin_round(s)
	for t: TankState in s.tanks:
		_assert_reset(t, "after start_round")


func test_explode_records_the_shot_and_the_impact_cell() -> void:
	var s: MatchState = U.flat_state(2)
	s.wind = 37
	s.turn_number = 5
	var ev: Array[Dictionary] = WU.fire(s, "pulse_missile", 452, 610)
	var end: Dictionary = _end_of(ev, 0)
	assert_eq(end["reason"], "terrain")
	var t: TankState = s.tanks[0]
	assert_eq(_fired_fields(t), [452, 610, Catalog.index_of("pulse_missile"), end["x"], end["y"], 37, 5] as Array[int])
	_assert_reset(s.tanks[1], "the other tank is untouched")


func test_fire_with_the_unlimited_dart_records_its_index() -> void:
	var s: MatchState = U.flat_state(2)
	WU.fire(s, "spark_dart", 450, 500)
	assert_eq(s.tanks[0].last_fire_weapon, Catalog.index_of("spark_dart"))
	assert_gte(s.tanks[0].last_fire_weapon, 0)


func test_a_shot_that_hits_a_tank_records_the_tank_cell() -> void:
	var s: MatchState = U.flat_state(2)
	var power: int = WU.power_for_landing(s, 450, s.tanks[1].x)
	var ev: Array[Dictionary] = WU.fire(s, "pulse_missile", 450, power)
	var end: Dictionary = _end_of(ev, 0)
	assert_true(end["reason"] == "tank" or end["reason"] == "terrain")
	assert_eq([s.tanks[0].last_fire_x, s.tanks[0].last_fire_y], [end["x"], end["y"]])


func test_the_record_reflects_the_wind_and_turn_at_fire_time_not_after() -> void:
	var s: MatchState = U.flat_state(2)
	s.wind = -64
	s.turn_number = 11
	WU.fire(s, "pulse_missile", 450, 600)
	assert_eq(s.turn_number, 12, "the turn advanced")
	assert_eq(s.tanks[0].last_fire_turn, 11)
	assert_eq(s.tanks[0].last_fire_wind, -64)


func test_splitter_uses_the_first_childs_impact() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "prism_splitter", 450, 600)
	assert_eq(_end_of(ev, 0)["reason"], "split")
	var child: Dictionary = _end_of(ev, 1)
	assert_eq(child["reason"], "terrain")
	var t: TankState = s.tanks[0]
	assert_eq([t.last_fire_x, t.last_fire_y], [child["x"], child["y"]])
	assert_eq(t.last_fire_weapon, Catalog.index_of("prism_splitter"))
	var main: Dictionary = _end_of(ev, 0)
	assert_ne([t.last_fire_x, t.last_fire_y], [main["x"], main["y"]], "not the apex")


func test_beam_records_its_end_point() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].x = 600
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 0, 500)
	var b: Dictionary = U.find(ev, "beam")[0]
	assert_eq([b["x1"], b["y1"]], [588, 588])
	var t: TankState = s.tanks[0]
	assert_eq([t.last_fire_x, t.last_fire_y], [588, 588])
	assert_eq(t.last_fire_weapon, Catalog.index_of("photon_lance"))
	assert_eq(t.last_fire_power, 500)
	assert_eq(t.last_fire_angle, 0)


func test_beam_that_leaves_the_map_records_the_edge_cell() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "photon_lance", 900, 500)
	var b: Dictionary = U.find(ev, "beam")[0]
	var t: TankState = s.tanks[0]
	assert_eq([t.last_fire_x, t.last_fire_y], [b["x1"], b["y1"]])
	assert_eq(t.last_fire_y, -1, "left through the top")
	assert_eq(StateSerial.validate(s), "", "such a state is valid")


func test_a_lost_shell_records_minus_one() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = WU.fire(s, "pulse_missile", 1500, 1000)
	assert_eq(_end_of(ev, 0)["reason"], "lost")
	var t: TankState = s.tanks[0]
	assert_eq([t.last_fire_x, t.last_fire_y], [-1, -1])
	assert_eq(t.last_fire_angle, 1500)
	assert_eq(t.last_fire_power, 1000)
	assert_eq(t.last_fire_weapon, Catalog.index_of("pulse_missile"))
	assert_eq(t.last_fire_turn, 0)


func test_a_lost_shot_overwrites_an_earlier_impact() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].set_stock("pulse_missile", 5)
	WU.fire(s, "pulse_missile", 450, 600)
	assert_gt(s.tanks[0].last_fire_x, 0)
	s.current_tank = 0
	s.tanks[1].set_stock("pulse_missile", 5)
	WU.fire(s, "pulse_missile", 1500, 1000)
	assert_eq([s.tanks[0].last_fire_x, s.tanks[0].last_fire_y], [-1, -1])


func test_timeout_and_split_cases_via_the_event_reader() -> void:
	var t := TankState.new()
	t.last_fire_x = 77
	t.last_fire_y = 88
	var timeout: Array[Dictionary] = [
		{"type": "fire", "tick": 0}, {"type": "projectile", "tick": 0, "id": 0},
		{"type": "projectile_end", "tick": 1500, "id": 0, "reason": "timeout", "x": 5, "y": 6}]
	WeaponResolver.record_impact(t, timeout, 0)
	assert_eq([t.last_fire_x, t.last_fire_y], [-1, -1], "timeout, even with stale values")
	var split_lost: Array[Dictionary] = [
		{"type": "projectile_end", "tick": 9, "id": 0, "reason": "split", "x": 5, "y": 6},
		{"type": "projectile_end", "tick": 90, "id": 1, "reason": "lost", "x": 5, "y": 6},
		{"type": "projectile_end", "tick": 99, "id": 2, "reason": "terrain", "x": 11, "y": 12}]
	WeaponResolver.record_impact(t, split_lost, 0)
	assert_eq([t.last_fire_x, t.last_fire_y], [-1, -1], "only the first child counts")
	var split_hit: Array[Dictionary] = [
		{"type": "projectile_end", "tick": 9, "id": 0, "reason": "split", "x": 5, "y": 6},
		{"type": "projectile_end", "tick": 90, "id": 1, "reason": "shield", "x": 21, "y": 22}]
	WeaponResolver.record_impact(t, split_hit, 0)
	assert_eq([t.last_fire_x, t.last_fire_y], [21, 22])
	var main_hit: Array[Dictionary] = [
		{"type": "projectile_end", "tick": 9, "id": 0, "reason": "tank", "x": 31, "y": 32},
		{"type": "projectile_end", "tick": 9, "id": 1, "reason": "terrain", "x": 1, "y": 2}]
	WeaponResolver.record_impact(t, main_hit, 0)
	assert_eq([t.last_fire_x, t.last_fire_y], [31, 32])
	var none: Array[Dictionary] = []
	WeaponResolver.record_impact(t, none, 0)
	assert_eq([t.last_fire_x, t.last_fire_y], [-1, -1], "no events at all")
	var skipped: Array[Dictionary] = [
		{"type": "projectile_end", "tick": 9, "id": 0, "reason": "terrain", "x": 1, "y": 2},
		{"type": "projectile_end", "tick": 9, "id": 0, "reason": "terrain", "x": 3, "y": 4}]
	WeaponResolver.record_impact(t, skipped, 1)
	assert_eq([t.last_fire_x, t.last_fire_y], [3, 4], "only events from the start index")


func test_every_behaviour_records_a_valid_shot() -> void:
	for id: String in Catalog.IDS:
		if not Catalog.is_weapon(id):
			continue
		var s: MatchState = U.flat_state(2)
		WU.fire(s, id, 600, 700)
		var t: TankState = s.tanks[0]
		assert_eq(t.last_fire_weapon, Catalog.index_of(id), id)
		assert_eq(StateSerial.validate(s), "", "%s leaves a valid state" % id)


func test_other_actions_leave_the_record_alone() -> void:
	var s: MatchState = U.flat_state(2)
	WU.fire(s, "pulse_missile", 450, 600)
	WU.fire(s, "pulse_missile", 1350, 650)
	assert_eq(s.current_tank, 0)
	var before0: Array[int] = _fired_fields(s.tanks[0])
	var before1: Array[int] = _fired_fields(s.tanks[1])
	var wrong_turn: Dictionary = {"kind": "fire", "tank": 1, "angle": 450, "power": 600, "weapon": "pulse_missile"}
	assert_eq(Simulation.apply_action(s, wrong_turn).size(), 0, "not his turn: refused")
	var bad: Dictionary = {"kind": "fire", "tank": 0, "angle": 9999, "power": 600, "weapon": "pulse_missile"}
	assert_eq(Simulation.apply_action(s, bad).size(), 0)
	assert_eq(_fired_fields(s.tanks[0]), before0, "an illegal action writes nothing")
	assert_eq(_fired_fields(s.tanks[1]), before1)
	assert_gt(Simulation.apply_action(s, U.pass_turn(0)).size(), 0)
	assert_eq(_fired_fields(s.tanks[0]), before0, "pass keeps the record")
	assert_eq(_fired_fields(s.tanks[1]), before1)


# --- reset ---------------------------------------------------------------------------------------

func test_start_round_resets_the_record_of_every_tank() -> void:
	var st := MatchSettings.new()
	st.seed = 8
	st.num_tanks = 2
	st.rounds = 2
	var s: MatchState = U.started_match(st)
	WU.fire(s, "pulse_missile", 450, 600)
	WU.fire(s, "pulse_missile", 1350, 600)
	assert_ne(s.tanks[0].last_fire_weapon, -1)
	assert_ne(s.tanks[1].last_fire_weapon, -1)
	U.kill_all_but(s, 0)
	Simulation.apply_action(s, U.pass_turn(s.current_tank))
	assert_eq(s.phase, SimConstants.PHASE_SHOP)
	assert_ne(s.tanks[0].last_fire_weapon, -1, "kept through the shop")
	U.begin_round(s)
	assert_eq(s.phase, SimConstants.PHASE_AIM)
	for t: TankState in s.tanks:
		_assert_reset(t, "after the second start_round")


# --- fingerprint, save, duplicate ---------------------------------------------------------------

func _fired_state() -> MatchState:
	var st := MatchSettings.new()
	st.seed = 21
	st.num_tanks = 3
	st.rounds = 3
	st.controllers = PackedInt32Array([0, 2, 4])
	var s: MatchState = U.started_match(st)
	WU.fire(s, "pulse_missile", 450, 620)
	WU.fire(s, "prism_splitter", 1300, 640)
	return s


func test_each_last_fire_field_changes_the_fingerprint() -> void:
	var base: MatchState = _fired_state()
	var fp: String = Simulation.fingerprint(base)
	for f: String in LAST_FIRE_FIELDS:
		for tank: int in range(base.tanks.size()):
			var s: MatchState = base.duplicate_state()
			s.tanks[tank].set(f, (s.tanks[tank].get(f) as int) + 1)
			assert_ne(Simulation.fingerprint(s), fp, "%s of tank %d" % [f, tank])


func test_duplicate_tank_copies_the_record() -> void:
	var s: MatchState = _fired_state()
	var d: MatchState = s.duplicate_state()
	for i: int in range(s.tanks.size()):
		assert_eq(_fired_fields(d.tanks[i]), _fired_fields(s.tanks[i]))
	assert_eq(Simulation.fingerprint(d), Simulation.fingerprint(s))
	assert_ne(d.tanks[0].last_fire_weapon, -1)


func test_save_round_trip_keeps_the_record_and_controllers() -> void:
	var s: MatchState = _fired_state()
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_true(res["ok"], str(res["error"]))
	var back: MatchState = res["state"]
	for i: int in range(s.tanks.size()):
		assert_eq(_fired_fields(back.tanks[i]), _fired_fields(s.tanks[i]), "tank %d" % i)
	assert_eq(back.settings.controllers, s.settings.controllers)
	assert_eq(Simulation.fingerprint(back), Simulation.fingerprint(s))
	_assert_reset(back.tanks[2], "a tank that never fired stays reset")


func test_old_save_version_is_rejected() -> void:
	var s: MatchState = _fired_state()
	var bytes: PackedByteArray = SaveCodec.encode(s, [] as Array[Dictionary])
	bytes.encode_u32(4, 1)
	var res: Dictionary = SaveCodec.decode(bytes)
	assert_false(res["ok"])
	assert_eq(res["error"], "bad_version")
	assert_gte(SaveCodec.SAVE_VERSION, 2)


# --- validation ---------------------------------------------------------------------------------

func _assert_rejected(mutate: Callable, what: String) -> void:
	var s: MatchState = _fired_state()
	assert_eq(StateSerial.validate(s), "", "the base state is valid")
	mutate.call(s)
	assert_ne(StateSerial.validate(s), "", what)
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	assert_false(res["ok"], "decode rejects: %s" % what)
	assert_eq(res["error"], "invalid_state", what)


func test_validate_accepts_the_reset_and_fired_records() -> void:
	assert_eq(StateSerial.validate(_fired_state()), "")
	var s: MatchState = _fired_state()
	s.tanks[0].last_fire_x = 1599
	s.tanks[0].last_fire_y = 899
	assert_eq(StateSerial.validate(s), "", "impact in the far corner")
	s.tanks[0].last_fire_x = -1
	s.tanks[0].last_fire_y = -1
	assert_eq(StateSerial.validate(s), "", "lost shot")


func test_validate_rejects_bad_controllers() -> void:
	_assert_rejected(func(s: MatchState) -> void: s.settings.controllers[0] = 5, "controller 5")
	_assert_rejected(func(s: MatchState) -> void: s.settings.controllers[1] = -1, "controller -1")
	_assert_rejected(func(s: MatchState) -> void: s.settings.controllers.resize(2), "too few controllers")
	_assert_rejected(func(s: MatchState) -> void: s.settings.controllers.resize(4), "too many controllers")
	_assert_rejected(func(s: MatchState) -> void: s.settings.full_unlocked = false, "Expert without the full version")


func test_validate_rejects_out_of_range_last_fire_values() -> void:
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_weapon = -2, "weapon -2")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_weapon = Catalog.count(), "weapon past the catalog")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_weapon = Catalog.index_of("glow_shield"), "an item as weapon")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_angle = -1, "angle -1")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_angle = 1801, "angle 1801")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_power = 0, "power 0 with a weapon")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_power = 1001, "power 1001")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_x = -2, "x -2")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_x = SimConstants.WORLD_W + 1, "x off the map")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_y = -2, "y -2")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_y = SimConstants.WORLD_H + 1, "y below the map")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_wind = s.settings.wind_max + 1, "wind beyond wind_max")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_wind = -s.settings.wind_max - 1, "wind below -wind_max")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_turn = -1, "turn -1 with a weapon")
	_assert_rejected(func(s: MatchState) -> void: s.tanks[0].last_fire_turn = s.turn_number + 1, "fired in the future")


func test_validate_rejects_a_record_without_a_weapon() -> void:
	_assert_rejected(func(s: MatchState) -> void:
		s.tanks[2].last_fire_power = 500, "power set while weapon is -1")
	_assert_rejected(func(s: MatchState) -> void:
		s.tanks[2].last_fire_turn = 0, "turn set while weapon is -1")
	_assert_rejected(func(s: MatchState) -> void:
		s.tanks[2].last_fire_x = 10, "x set while weapon is -1")
	_assert_rejected(func(s: MatchState) -> void:
		s.tanks[0].last_fire_weapon = -1, "a fired record whose weapon was wiped")
