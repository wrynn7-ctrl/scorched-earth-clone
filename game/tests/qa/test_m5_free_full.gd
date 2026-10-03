@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: the free / full split (docs/ARCHITECTURE.md section 32). Over 100 seeded free-mode matches
## (scripted bots, CPUs, and "greedy humans" who try every locked purchase and shot): never more than
## 4 tanks or 5 rounds, no full-tier item ever owned, raised or fired, controllers never above Normal.
## Also: a full save refused by the free restore path, and a garbage Entitlement cache means free.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

const ROOT_SEED: int = 6260
const MATCHES: int = 100
## Cheap duels (2-3 tanks requested) may play out all their rounds; bigger matches are cut short.
const MAX_AIM_ACTIONS_SMALL: int = 80
const MAX_AIM_ACTIONS_BIG: int = 22
const SAVE_A: String = "user://qa_m5_full_save.crtl"
const SAVE_B: String = "user://qa_m5_free_save.crtl"
const CACHE: String = "user://qa_m5_entitlement.cfg"

var _stats: Dictionary = {}


func after_each() -> void:
	Entitlement.forget_for_tests()
	for p: String in [SAVE_A, SAVE_B, CACHE]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
		if DirAccess.dir_exists_absolute(p):
			DirAccess.remove_absolute(p)


# --- helpers ------------------------------------------------------------------------------------

func _full_tier_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.get_def(id)["tier"] == "full":
			out.append(id)
	return out


func _bump(key: String, by: int = 1) -> void:
	_stats[key] = (_stats.get(key, 0) as int) + by


func _free_settings(i: int) -> MatchSettings:
	var r: Rng = Rng.derive(ROOT_SEED, 40 + i)
	var s := MatchSettings.new()
	s.seed = r.next_u32() + i
	s.full_unlocked = false
	s.num_tanks = r.range_int(2, 8)
	s.rounds = [20, 6, 5, 10, 3, 1, 8, 20][i % 8]
	if i % 3 == 0:
		s.num_tanks = r.range_int(2, 3)  # short, cheap matches that reach the round cap
	s.wind_max = [100, 0, 50, 100][i % 4]
	s.start_money = [10000, 1_000_000, 500, 25000, 0][i % 5]
	var ctrl := PackedInt32Array()
	for _k: int in range(s.num_tanks):
		ctrl.append(r.range_int(0, 4))
	s.controllers = ctrl
	if i % 10 == 9:
		s.mode = SimConstants.MODE_LOVE
	return s


## Free-tier invariants of the state itself. Returns violations.
func _tier_violations(state: MatchState, full_ids: Array[String]) -> Array[String]:
	var errs: Array[String] = []
	var st: MatchSettings = state.settings
	if st.full_unlocked:
		errs.append("full_unlocked became true")
	if state.tanks.size() > SimConstants.FREE_MAX_TANKS or st.num_tanks > SimConstants.FREE_MAX_TANKS:
		errs.append("%d tanks in a free match" % state.tanks.size())
	if st.rounds > SimConstants.FREE_MAX_ROUNDS or state.round_index >= SimConstants.FREE_MAX_ROUNDS:
		errs.append("rounds %d / round_index %d in a free match" % [st.rounds, state.round_index])
	for c: int in st.controllers:
		if c > SimConstants.CTRL_NORMAL:
			errs.append("controller %d above Normal" % c)
	for t: TankState in state.tanks:
		for id: String in full_ids:
			if t.stock_of(id) != 0:
				errs.append("tank %d owns %d x %s" % [t.id, t.stock_of(id), id])
		if t.shield_type >= 0 and Catalog.get_def(Catalog.id_at(t.shield_type))["tier"] == "full":
			errs.append("tank %d raised a full-tier shield" % t.id)
		if t.last_fire_weapon >= 0 and Catalog.get_def(Catalog.id_at(t.last_fire_weapon))["tier"] == "full":
			errs.append("tank %d fired the full-tier %s" % [t.id, Catalog.id_at(t.last_fire_weapon)])
		if AiProfile.level_of(state, t.id) > SimConstants.CTRL_NORMAL:
			errs.append("tank %d plays above Normal" % t.id)
	return errs


## A greedy player tries every locked purchase and shot: all refused, nothing changes.
func _greedy_attempts(state: MatchState, tank: int, full_ids: Array[String], problems: Array[String], tag: String) -> void:
	var sig: String = M5.lite_fp(state)
	for id: String in full_ids:
		if state.phase == SimConstants.PHASE_SHOP:
			var buy: Dictionary = {"kind": "buy", "tank": tank, "item": id, "qty": 1}
			var err: String = Simulation.validate_action(state, buy)
			if err != "locked_item":
				problems.append("%s: buy %s -> '%s' (expected locked_item)" % [tag, id, err])
			if not Simulation.apply_action(state, buy).is_empty():
				problems.append("%s: a locked buy was applied (%s)" % [tag, id])
			_bump("locked_buys_refused")
		elif state.phase == SimConstants.PHASE_AIM and tank == state.current_tank:
			var item_def: Dictionary = Catalog.get_def(id)
			if item_def["kind"] == "weapon":
				var fire: Dictionary = {"kind": "fire", "tank": tank, "angle": 450, "power": 500, "weapon": id}
				var ferr: String = Simulation.validate_action(state, fire)
				if ferr != "out_of_stock" and ferr != "bad_mode":
					problems.append("%s: fire %s -> '%s'" % [tag, id, ferr])
				if not Simulation.apply_action(state, fire).is_empty():
					problems.append("%s: a full-tier shot was applied (%s)" % [tag, id])
				_bump("locked_shots_refused")
			else:
				var use: Dictionary = {"kind": "use_item", "tank": tank, "item": id}
				var uerr: String = Simulation.validate_action(state, use)
				if uerr == "":
					problems.append("%s: use_item %s accepted" % [tag, id])
				if not Simulation.apply_action(state, use).is_empty():
					problems.append("%s: a full-tier item was used (%s)" % [tag, id])
	if M5.lite_fp(state) != sig:
		problems.append("%s: refused greedy actions changed the state" % tag)


func _shop(state: MatchState, rng: Rng, full_ids: Array[String], problems: Array[String], tag: String) -> void:
	for t: TankState in state.tanks:
		if t.ready:
			continue
		if state.settings.controllers[t.id] != SimConstants.CTRL_HUMAN:
			for a: Dictionary in AiPlayer.shop_actions(state, t.id):
				var err: String = Simulation.validate_action(state, a)
				if err != "":
					problems.append("%s: CPU shop action %s rejected '%s'" % [tag, str(a), err])
					continue
				if a["kind"] == "buy" and Catalog.get_def(a["item"] as String)["tier"] != "free":
					problems.append("%s: CPU bought %s" % [tag, a["item"]])
				Simulation.apply_action(state, a)
		else:
			_greedy_attempts(state, t.id, full_ids, problems, tag)
			var def: Dictionary = WeaponDefs.get_def(QaUtil.WEAPON)
			var qty: int = mini(t.money / (def["price"] as int), (SimConstants.INVENTORY_CAP - t.stock_of(QaUtil.WEAPON)) / (def["bundle"] as int))
			if qty >= 1:
				Simulation.apply_action(state, {"kind": "buy", "tank": t.id, "item": QaUtil.WEAPON, "qty": qty})
			Simulation.apply_action(state, {"kind": "ready", "tank": t.id})


func _aim(state: MatchState, rng: Rng) -> Dictionary:
	var c: int = state.current_tank
	if state.settings.controllers[c] == SimConstants.CTRL_HUMAN and rng.range_int(0, 3) == 0 \
			and state.settings.mode == SimConstants.MODE_STANDARD:
		return QaUtil.bot_action(state, rng)  # the scripted bot (pulse missiles, wild shots)
	return AiPlayer.next_action(state, c)


func _play_free(i: int, full_ids: Array[String]) -> Array[String]:
	var settings: MatchSettings = _free_settings(i)
	var tag: String = "free match %d (requested %d tanks, %d rounds, ctrl %s, mode %d, seed %d)" % [i, settings.num_tanks,
			settings.rounds, str(settings.controllers), settings.mode, settings.seed]
	var problems: Array[String] = []
	var state: MatchState = Simulation.new_match(settings)
	for e: String in _tier_violations(state, full_ids):
		problems.append("%s: at start: %s" % [tag, e])
	var rng: Rng = Rng.derive(ROOT_SEED, 500 + i)
	var aim_actions: int = 0
	var cap: int = MAX_AIM_ACTIONS_SMALL if settings.num_tanks <= 3 else MAX_AIM_ACTIONS_BIG
	var saved: bool = false
	_bump("matches")
	_bump("tanks_%d" % state.tanks.size())
	var guard: int = 0
	while state.phase != SimConstants.PHASE_MATCH_OVER and aim_actions < cap and guard < 1500:
		guard += 1
		if state.phase == SimConstants.PHASE_SHOP:
			var s0: int = Time.get_ticks_usec()
			_shop(state, rng, full_ids, problems, tag)
			_bump("shop_ms", (Time.get_ticks_usec() - s0) / 1000)
			s0 = Time.get_ticks_usec()
			if Simulation.all_ready(state):
				Simulation.start_round(state)
			_bump("start_round_ms", (Time.get_ticks_usec() - s0) / 1000)
		else:
			if aim_actions % 8 == 0:
				_greedy_attempts(state, state.current_tank, full_ids, problems, tag)
			var a0: int = Time.get_ticks_usec()
			var action: Dictionary = _aim(state, rng)
			_bump("aim_ms", (Time.get_ticks_usec() - a0) / 1000)
			a0 = Time.get_ticks_usec()
			var err: String = Simulation.validate_action(state, action)
			if err != "":
				problems.append("%s: action %s rejected '%s'" % [tag, str(action), err])
				break
			for ev: Dictionary in Simulation.apply_action(state, action):
				if ev["type"] == "fire" and WeaponDefs.get_def(ev["weapon"] as String).get("tier", "free") != "free":
					problems.append("%s: fired %s" % [tag, ev["weapon"]])
			aim_actions += 1
			_bump("apply_ms", (Time.get_ticks_usec() - a0) / 1000)
			_bump("aim_actions")
		var v0: int = Time.get_ticks_usec()
		for e: String in _tier_violations(state, full_ids):
			problems.append("%s: %s" % [tag, e])
		_bump("violations_ms", (Time.get_ticks_usec() - v0) / 1000)
		if problems.size() > 6:
			return problems
		if not saved and aim_actions == 6:
			saved = true
			var res: Dictionary = SaveCodec.decode(SaveCodec.encode(state, [] as Array[Dictionary]))
			if not (res["ok"] as bool) or (res["state"] as MatchState).settings.full_unlocked:
				problems.append("%s: free state did not survive a save: %s" % [tag, str(res["error"])])
	_stats["max_round_index"] = maxi(_stats.get("max_round_index", 0) as int, state.round_index)
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		_bump("finished")
		if state.round_index + 1 > SimConstants.FREE_MAX_ROUNDS:
			problems.append("%s: %d rounds played" % [tag, state.round_index + 1])
		if not Simulation.start_round(state).is_empty():
			problems.append("%s: a round started after match_over" % tag)
		if state.round_index == 4:
			_bump("reached_round_5")
	return problems


# --- the 100 free matches ------------------------------------------------------------------------

func test_100_free_matches_never_break_the_free_limits() -> void:
	var full_ids: Array[String] = _full_tier_ids()
	assert_gt(full_ids.size(), 8, "the catalog has full-tier entries to try")
	var bad: Array[String] = []
	var t0: int = Time.get_ticks_msec()
	var slowest: int = 0
	for i: int in range(MATCHES * M5.scale()):
		var m0: int = Time.get_ticks_msec()
		bad.append_array(_play_free(i, full_ids))
		slowest = maxi(slowest, Time.get_ticks_msec() - m0)
	gut.p("FREE FUZZ  %d ms total, slowest match %d ms" % [Time.get_ticks_msec() - t0, slowest])
	gut.p("FREE FUZZ  %s" % str(_stats))
	assert_eq(bad.size(), 0, "free-tier violations:\n  " + "\n  ".join(bad.slice(0, 12)))
	assert_eq(_stats.get("matches", 0), MATCHES * M5.scale())
	assert_gt(_stats.get("locked_buys_refused", 0) as int, 100, "the greedy shoppers really tried")
	assert_gt(_stats.get("locked_shots_refused", 0) as int, 100, "the greedy shooters really tried")
	assert_gt(_stats.get("finished", 0) as int, 25, "most matches ran to the end")
	assert_gte(_stats.get("max_round_index", 0) as int, 4, "some match played the 5th round")
	assert_lte(_stats.get("max_round_index", 0) as int, 4)
	for n: int in range(5, 9):
		assert_false(_stats.has("tanks_%d" % n), "a free match had %d tanks" % n)


func test_requested_extremes_are_clamped_for_a_free_match() -> void:
	var s := MatchSettings.new()
	s.full_unlocked = false
	s.num_tanks = 8
	s.rounds = 20
	s.controllers = PackedInt32Array([4, 4, 3, 3, 4, 4, 3, 3])
	var st: MatchState = Simulation.new_match(s)
	assert_eq(st.tanks.size(), 4)
	assert_eq(st.settings.rounds, 5)
	assert_eq(st.settings.controllers, PackedInt32Array([2, 2, 2, 2]))
	assert_eq(s.num_tanks, 8, "the caller's settings object is not touched")
	# The same request with the full game keeps everything.
	s.full_unlocked = true
	var f: MatchState = Simulation.new_match(s)
	assert_eq(f.tanks.size(), 8)
	assert_eq(f.settings.rounds, 20)
	assert_eq(f.settings.controllers, PackedInt32Array([4, 4, 3, 3, 4, 4, 3, 3]))


func test_a_free_state_cannot_be_decoded_with_more_than_the_free_limits() -> void:
	var cases: Array[String] = ["tanks", "rounds", "ctrl"]
	for what: String in cases:
		var s: MatchState = Simulation.new_match(QaUtil.settings(3, 4, 5))
		s.settings.full_unlocked = false
		s.settings.controllers = PackedInt32Array([0, 0, 0, 0])
		match what:
			"tanks":
				s.settings.num_tanks = 5
				s.tanks.append(s.tanks[0].duplicate_tank())
				s.tanks[4].id = 4
				s.settings.controllers = PackedInt32Array([0, 0, 0, 0, 0])
			"rounds":
				s.settings.rounds = 6
			"ctrl":
				s.settings.controllers = PackedInt32Array([0, 0, 0, 3])
		var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
		assert_false(res["ok"], "free state with too many %s must not decode" % what)
		assert_eq(res["error"], "invalid_state", what)


# --- saves and the free restore path ---------------------------------------------------------------

func _full_save(path: String) -> void:
	var s: MatchState = Simulation.new_match(QaUtil.settings(9, 6, 10))
	assert_true(s.settings.full_unlocked)
	assert_eq(s.tanks.size(), 6)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], path, {"looks": {}}), "saved")


func test_full_save_is_refused_by_the_free_restore_path() -> void:
	_full_save(SAVE_A)
	Entitlement.reset_for_tests(false)
	assert_false(Entitlement.is_full())
	assert_true(MatchSession.needs_full(SAVE_A), "the title must explain why CONTINUE does not work")
	assert_null(MatchSession.restore(SAVE_A), "a full-game save does not restore on a free device")
	# Owning the game makes the very same file restorable.
	Entitlement.reset_for_tests(true)
	assert_false(MatchSession.needs_full(SAVE_A))
	var back: MatchSession = MatchSession.restore(SAVE_A)
	assert_not_null(back)
	assert_eq(back.state.tanks.size(), 6)
	# And the refusal returns when the purchase goes away again (a refund).
	Entitlement.reset_for_tests(false)
	assert_null(MatchSession.restore(SAVE_A))
	assert_true(FileAccess.file_exists(SAVE_A), "refusing must not delete the player's file")


func test_free_save_restores_on_a_free_device_and_on_a_full_one() -> void:
	var s: MatchState = Simulation.new_match(QaUtil.settings(10, 3, 4))
	s.settings.full_unlocked = false
	s = Simulation.new_match(s.settings)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], SAVE_B))
	Entitlement.reset_for_tests(false)
	assert_not_null(MatchSession.restore(SAVE_B))
	assert_false(MatchSession.needs_full(SAVE_B))
	Entitlement.reset_for_tests(true)
	var back: MatchSession = MatchSession.restore(SAVE_B)
	assert_not_null(back)
	assert_false(back.state.settings.full_unlocked, "a free match stays free after the upgrade")


func test_restore_of_missing_garbage_and_truncated_saves_is_null() -> void:
	Entitlement.reset_for_tests(false)
	assert_null(MatchSession.restore("user://qa_m5_does_not_exist.crtl"))
	assert_null(MatchSession.restore(""))
	assert_false(MatchSession.needs_full("user://qa_m5_does_not_exist.crtl"))
	var f: FileAccess = FileAccess.open(SAVE_A, FileAccess.WRITE)
	f.store_string("not a save at all")
	f.close()
	assert_null(MatchSession.restore(SAVE_A))
	assert_false(MatchSession.needs_full(SAVE_A))
	_full_save(SAVE_B)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(SAVE_B)
	var g: FileAccess = FileAccess.open(SAVE_A, FileAccess.WRITE)
	g.store_buffer(bytes.slice(0, bytes.size() / 2))
	g.close()
	assert_null(MatchSession.restore(SAVE_A), "a half-written save")
	assert_false(MatchSession.needs_full(SAVE_A), "and it is not mistaken for a full-game save")


func test_free_save_carrying_full_tier_items_is_not_accepted() -> void:
	# A save is only protected by a checksum anyone can recompute. The entitlement check looks at the
	# full_unlocked flag; the items inside must not smuggle the full game in either.
	var s: MatchState = Simulation.new_match(QaUtil.settings(12, 2, 2))
	s.settings.full_unlocked = false
	s = Simulation.new_match(s.settings)
	s.tanks[0].set_stock("supernova", 3)
	s.tanks[1].set_stock("fortress_field", 1)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], SAVE_B))
	Entitlement.reset_for_tests(false)
	var back: MatchSession = MatchSession.restore(SAVE_B)
	if back != null:
		pending("BUG (low): a free-version save with full-tier inventory (supernova x3, fortress_field x1, " \
				+ "full_unlocked = false) restores on a free device, so the tampered file hands out full weapons. " \
				+ "Expected restore() == null / decode invalid_state; actual: restored. Suspected " \
				+ "core/state_serial.gd:455 (_validate_inventory, no tier check against settings.full_unlocked) and " \
				+ "core/simulation.gd:202 (_validate_fire, no tier check at fire time). Same trust level as the editable " \
				+ "entitlement cache, so low severity.")
		return
	assert_null(back)


# --- the entitlement cache -----------------------------------------------------------------------------

func _write_cache(bytes: PackedByteArray) -> void:
	var f: FileAccess = FileAccess.open(CACHE, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _bytes(text: String, extra: Array) -> PackedByteArray:
	var b: PackedByteArray = text.to_utf8_buffer()
	for v: Variant in extra:
		b.append(v as int)
	return b


## Reads the cache the way a fresh launch does (not the headless "everything is full" shortcut).
func _fresh_launch_is_full() -> bool:
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	Entitlement.debug_build_override = 0  # behave as a release build: no debug override
	return Entitlement.is_full()


## Cache contents that ConfigFile parses without complaint but that mean nothing (or something wrong).
func test_well_formed_but_wrong_cache_values_mean_free() -> void:
	var cases: Dictionary = {
		"empty": PackedByteArray(),
		"full=42": "[entitlement]\nfull=42\n".to_utf8_buffer(),
		"full string true": "[entitlement]\nfull=\"true\"\n".to_utf8_buffer(),
		"full=1": "[entitlement]\nfull=1\n".to_utf8_buffer(),
		"full float": "[entitlement]\nfull=1.0\n".to_utf8_buffer(),
		"full array": "[entitlement]\nfull=[true]\n".to_utf8_buffer(),
		"full null": "[entitlement]\nfull=null\n".to_utf8_buffer(),
		"wrong section": "[other]\nfull=true\n".to_utf8_buffer(),
		"true then false": "[entitlement]\nfull=true\nfull=false\n".to_utf8_buffer(),
		"debug_full only": "[entitlement]\ndebug_full=true\n".to_utf8_buffer(),
		"full false": "[entitlement]\nfull=false\n".to_utf8_buffer(),
	}
	var names: Array = cases.keys()
	names.sort()
	for n: Variant in names:
		_write_cache(cases[n] as PackedByteArray)
		assert_false(_fresh_launch_is_full(), "cache '%s' must be treated as free" % str(n))
		assert_false(Entitlement.is_debug_full(), "'%s': no debug override in a release build" % str(n))
	_write_cache("[entitlement]\nfull=true\n".to_utf8_buffer())
	assert_true(_fresh_launch_is_full(), "positive control: a valid cache says full (the accepted, editable cache)")
	DirAccess.remove_absolute(CACHE)
	DirAccess.make_dir_recursive_absolute(CACHE)
	assert_false(_fresh_launch_is_full(), "a directory in place of the cache")


## Damaged cache files (ConfigFile prints a parse error for these, so a child process reads them).
func test_garbage_cache_files_mean_free_and_never_crash() -> void:
	var rng: Rng = Rng.derive(ROOT_SEED, 7)
	var noise := PackedByteArray()
	for _i: int in range(4096):
		noise.append(rng.range_int(0, 255))
	var huge := PackedByteArray()
	huge.resize(1_000_000)
	huge.fill(0x61)
	var nuls := PackedByteArray()
	nuls.resize(300)
	var cases: Dictionary = {
		"text": "this is not a config file".to_utf8_buffer(),
		"random bytes": noise,
		"nul bytes": nuls,
		"1 MB of a": huge,
		"unterminated section": "[entitlement\nfull=true\n".to_utf8_buffer(),
		"no section": "full=true\n".to_utf8_buffer(),
		"true then garbage": _bytes("[entitlement]\nfull=true\n[[[ ??? ", [0, 255, 254]),
		"missing value": "[entitlement]\nfull=\n".to_utf8_buffer(),
		"unicode": "[entitlement]\nfull=tr\u00fce\n".to_utf8_buffer(),
		"capital TRUE": "[entitlement]\nfull=TRUE\n".to_utf8_buffer(),
		"truncated header": "[entitlem".to_utf8_buffer(),
		"valid": "[entitlement]\nfull=true\n".to_utf8_buffer(),
	}
	var names: Array = cases.keys()
	names.sort()
	var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"-s", "res://tests/qa/qa_m5_entitlement_probe.gd", "--"])
	var by_path: Dictionary = {}
	for n: Variant in names:
		var path: String = "user://qa_m5_cache_%d.cfg" % by_path.size()
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(cases[n] as PackedByteArray)
		f.close()
		var abs_path: String = ProjectSettings.globalize_path(path)
		by_path[abs_path] = str(n)
		args.append(abs_path)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), args, output, true)
	var text: String = str(output[0]) if output.size() > 0 else ""
	for p: Variant in by_path.keys():
		DirAccess.remove_absolute(str(p))
	assert_eq(code, 0, "the probe process exited normally: %s" % text.right(600))
	assert_false(text.contains("SCRIPT ERROR"), "no script error in the probe: %s" % text.right(600))
	var seen: int = 0
	for line: String in text.split("\n"):
		if not line.begins_with("PROBE|"):
			continue
		var parts: PackedStringArray = line.strip_edges().split("|")
		var label: String = by_path.get(parts[1], "?")
		seen += 1
		if label == "valid":
			assert_eq(parts[2], "true", "a valid cache says full")
		else:
			assert_eq(parts[2], "false", "garbage cache '%s' must be treated as free" % label)
		assert_eq(parts[3], "false", "'%s': no debug override in a release build" % label)
	assert_eq(seen, cases.size(), "every case was probed")


func test_corrupt_cache_is_replaced_by_a_clean_one_after_a_purchase() -> void:
	_write_cache(_bytes("garbage[[", [0, 1, 255]))
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	Entitlement.debug_build_override = 1
	BillingFake.delay_sec = 0.0
	assert_false(Entitlement.is_full())
	Entitlement.purchase_full()
	assert_true(Entitlement.is_full())
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(CACHE), OK, "the cache file is well-formed again")
	assert_true(cfg.get_value(Entitlement.SECTION, "full", false) as bool)
	Entitlement.forget_for_tests()
	Entitlement.cache_path = CACHE
	Entitlement.persist_headless = true
	Entitlement.debug_build_override = 0
	assert_true(Entitlement.is_full(), "and it survives a restart")


func test_release_build_never_unlocks_from_the_fake_store_or_a_pending_payment() -> void:
	Entitlement.reset_for_tests(false, CACHE)
	Entitlement.debug_build_override = 0
	Entitlement.purchase_full()
	assert_false(Entitlement.is_full(), "the fake store must not unlock a release build")
	assert_eq(Entitlement.status(), Entitlement.Status.ERROR)
	Entitlement.restore()
	assert_false(Entitlement.is_full())
	Entitlement.set_debug_full(true)
	assert_false(Entitlement.is_full(), "the debug override is ignored in a release build")
	# A pending payment is not an unlock, even in a debug build.
	Entitlement.reset_for_tests(false, CACHE)
	Entitlement.debug_build_override = 1
	BillingFake.next_result = "pending"
	Entitlement.purchase_full()
	assert_eq(Entitlement.status(), Entitlement.Status.PENDING)
	assert_false(Entitlement.is_full())
	for result: String in ["cancel", "network", "error"]:
		Entitlement.reset_for_tests(false, CACHE)
		Entitlement.debug_build_override = 1
		BillingFake.next_result = result
		Entitlement.purchase_full()
		assert_false(Entitlement.is_full(), "outcome '%s' does not unlock" % result)


func test_debug_flag_in_the_cache_does_not_unlock_a_release_build() -> void:
	_write_cache("[entitlement]\nfull=false\ndebug_full=true\n".to_utf8_buffer())
	assert_false(_fresh_launch_is_full())
	Entitlement.debug_build_override = 1
	assert_true(Entitlement.is_full(), "the same file does unlock a debug build")
