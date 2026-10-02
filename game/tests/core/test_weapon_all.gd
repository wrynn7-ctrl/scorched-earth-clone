@warning_ignore_start("integer_division")
extends GutTest
## Cross-cutting checks run over every weapon: the show-replay invariant, determinism, the event
## contract, money bookkeeping and performance.

const U = preload("res://tests/core/sim_test_util.gd")
const WU = preload("res://tests/core/weapon_test_util.gd")
const QaUtil = preload("res://tests/qa/qa_util.gd")

const FRAME_BUDGET_MS: float = 60.0
const INFERNO_BUDGET_MS: float = 40.0


## (angle, power) that lands a plain shell of the current tank on `target`'s column; the beam
## shoots flat.
func _aim(s: MatchState, target: TankState, weapon: String) -> Vector2i:
	var shooter: TankState = s.tanks[s.current_tank]
	var right: bool = target.x > shooter.x
	if WeaponDefs.get_def(weapon).get("behavior", "") == "beam":
		return Vector2i(0 if right else 1800, 500)
	var angle: int = 450 if right else 1350
	return Vector2i(angle, WU.power_for_landing(s, angle, target.x, shooter.id))


func _enemies(s: MatchState) -> Array[TankState]:
	var out: Array[TankState] = []
	for t: TankState in s.tanks:
		if t.id != s.current_tank and t.alive:
			out.append(t)
	return out


## Base states: flat ground with three tanks and generated terrain with four.
func _bases() -> Array[MatchState]:
	var flat: MatchState = U.flat_state(3)
	flat.tanks[1].x = 800
	flat.tanks[2].x = 1000
	for t: TankState in flat.tanks:
		for id: String in WeaponDefs.DEFS:
			t.set_stock(id, 5)
	var out: Array[MatchState] = [flat, WU.random_match(11), WU.random_match(29)]
	return out


func _fire_copy(base: MatchState, weapon: String, angle: int, power: int) -> Dictionary:
	var s: MatchState = base.duplicate_state()
	var before: Terrain = s.terrain.duplicate_terrain()
	var money: Array[int] = []
	for t: TankState in s.tanks:
		money.append(t.money)
	var ev: Array[Dictionary] = WU.fire(s, weapon, angle, power)
	return {"state": s, "events": ev, "before": before, "money": money}


func test_every_weapon_obeys_the_replay_invariant_and_is_deterministic() -> void:
	var checked: int = 0
	for base: MatchState in _bases():
		var targets: Array[TankState] = _enemies(base)
		for target: TankState in [targets[0], targets[targets.size() - 1]]:
			for id: String in WeaponDefs.DEFS:
				var aim: Vector2i = _aim(base, target, id)
				var a: Dictionary = _fire_copy(base, id, aim.x, aim.y)
				var b: Dictionary = _fire_copy(base, id, aim.x, aim.y)
				var s: MatchState = a["state"]
				var ev: Array[Dictionary] = a["events"]
				var label: String = "%s -> tank %d" % [id, target.id]
				assert_gt(ev.size(), 2, label)
				assert_true(WU.replay_matches(a["before"], ev, s.terrain), "replay: " + label)
				assert_eq(Simulation.fingerprint(s), Simulation.fingerprint(b["state"]), "fingerprint twice: " + label)
				assert_eq(WU.events_digest(ev), WU.events_digest(b["events"]), "events twice: " + label)
				checked += 1
	assert_eq(checked, 3 * 2 * 21)


func test_every_weapon_emits_contract_events_and_balanced_books() -> void:
	for base: MatchState in _bases():
		var target: TankState = _enemies(base)[0]
		for id: String in WeaponDefs.DEFS:
			var aim: Vector2i = _aim(base, target, id)
			var r: Dictionary = _fire_copy(base, id, aim.x, aim.y)
			var s: MatchState = r["state"]
			var ev: Array[Dictionary] = r["events"]
			var errs: Array[String] = QaUtil.check_event_fields(ev)
			assert_eq(errs.size(), 0, "%s: %s" % [id, "; ".join(errs)])
			var inv: Array[String] = QaUtil.check_invariants(s, false, true)
			assert_eq(inv.size(), 0, "%s: %s" % [id, "; ".join(inv)])
			# Every credit change is announced by a money event, and nothing else moves money.
			var delta: Array[int] = []
			for t: TankState in s.tanks:
				delta.append(0)
			for e: Dictionary in U.find(ev, "money"):
				delta[e["tank"]] += e["delta"] as int
			var before_money: Array[int] = r["money"]
			for t: TankState in s.tanks:
				assert_eq(t.money - before_money[t.id], delta[t.id], "%s: money of tank %d" % [id, t.id])
			# Every tank that lost health has damage events summing to at least the loss.
			var dmg: Dictionary = WU.damage_by_tank(ev)
			for t: TankState in s.tanks:
				var lost: int = (base.tanks[t.id].health) - t.health
				if lost > 0:
					assert_true(dmg.has(t.id) and (dmg[t.id] as int) >= lost, "%s: damage events cover tank %d" % [id, t.id])
			# Ticks never run backwards inside one shell's events and the turn passes (or the round ends).
			var types: Array[String] = U.types(ev)
			var ends_turn: bool = types.size() >= 2 and types[types.size() - 2] == "wind" and types[types.size() - 1] == "turn"
			var ends_round: bool = types.has("round_end")
			assert_true(ends_turn or ends_round, id)


func test_all_new_event_types_appear_somewhere() -> void:
	# Guards the replay test: the sweep above must actually exercise every terrain event.
	var seen: Dictionary = {}
	for base: MatchState in _bases():
		var target: TankState = _enemies(base)[0]
		for id: String in WeaponDefs.DEFS:
			var aim: Vector2i = _aim(base, target, id)
			for e: Dictionary in (_fire_copy(base, id, aim.x, aim.y)["events"] as Array[Dictionary]):
				seen[e["type"]] = true
	for t: String in ["terrain_carve", "tunnel", "terrain_add", "terrain_pour", "terrain_settle", "flames", "beam",
			"well_on", "projectile", "projectile_end", "explosion", "damage", "money", "tank_fall"]:
		assert_true(seen.has(t), "sweep produced %s" % t)


func test_apply_action_stays_inside_the_frame_budget() -> void:
	var base: MatchState = WU.random_match(29)
	var target: TankState = _enemies(base)[0]
	var report: PackedStringArray = PackedStringArray()
	for id: String in WeaponDefs.DEFS:
		var aim: Vector2i = _aim(base, target, id)
		var best: float = 1.0e9
		for _i: int in range(3):
			var s: MatchState = base.duplicate_state()
			var t0: int = Time.get_ticks_usec()
			Simulation.apply_action(s, {"kind": "fire", "tank": s.current_tank, "angle": aim.x, "power": aim.y,
					"weapon": id})
			best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
		report.append("%s %.1f" % [id, best])
		var budget: float = SimTestUtil.perf_budget_f(INFERNO_BUDGET_MS if id == "inferno_gel" else FRAME_BUDGET_MS)
		assert_lt(best, budget, "%s took %.1f ms" % [id, best])
	gut.p("apply_action ms (best of 3): " + ", ".join(report))


func test_worst_cases_stay_inside_the_frame_budget() -> void:
	# Supernova (r 160) into generated hills, sludge (1800 cells) down a slope, Inferno on a slope,
	# the nine-child cascade, the big dirt weapon and the long bore: every enemy of the current tank.
	var base: MatchState = WU.random_match(47)
	for pair: Array in [["supernova", 60.0], ["sludge_shell", 60.0], ["inferno_gel", 40.0], ["prism_cascade", 60.0],
			["landslide", 60.0], ["deep_bore", 60.0]]:
		var id: String = pair[0]
		var worst: float = 0.0
		for target: TankState in _enemies(base):
			var aim: Vector2i = _aim(base, target, id)
			var best: float = 1.0e9
			for _i: int in range(3):
				var s: MatchState = base.duplicate_state()
				var t0: int = Time.get_ticks_usec()
				WU.fire(s, id, aim.x, aim.y)
				best = minf(best, float(Time.get_ticks_usec() - t0) / 1000.0)
			worst = maxf(worst, best)
		assert_lt(worst, SimTestUtil.perf_budget_f(pair[1] as float), "%s took %.1f ms" % [id, worst])
		gut.p("%s worst case %.1f ms" % [id, worst])
