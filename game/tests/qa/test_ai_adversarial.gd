@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: adversarial hand-built situations for the computer opponents. Every scenario checks the
## contract (no crash, every action passes validate_action, the turn ends within 3 calls) and
## then something cheap and sensible about behaviour. Defects are recorded as pending("BUG: ...")
## so the suite stays green; see the QA report for the list.

const QA_AI = preload("res://tests/qa/qa_ai.gd")
const NAMES: Array[String] = ["", "easy", "normal", "hard", "expert"]
const LEVELS: Array[int] = [1, 2, 3, 4]

var _notes: Array[String] = []


## Marks the test pending with the bug text when `ok` is false.
func _bug(ok: bool, desc: String) -> void:
	if ok:
		pass_test("bug no longer reproduces (remove the pending guard): %s" % desc)
	else:
		pending("BUG: %s" % desc)


func _desc(a: Dictionary) -> String:
	match a["kind"]:
		"fire":
			return "fire %s a=%d p=%d" % [a["weapon"], a["angle"], a["power"]]
		"use_item":
			return "use %s" % a["item"]
		"move":
			return "move %d" % a["dx"]
	return a["kind"]


## Plays tank `id`'s whole turn on a COPY of `state` and checks the contract. Returns the
## QA_AI.play_turn dictionary plus `last` (the turn-ending action), `self_dmg`, `copy`.
func _turn(label: String, state: MatchState, id: int = 0) -> Dictionary:
	var copy: MatchState = state.duplicate_state()
	var r: Dictionary = QA_AI.play_turn(copy, id)
	assert_eq(r["errors"], [] as Array[String], "%s: every action legal, turn ends" % label)
	assert_lte(r["calls"] as int, 3, "%s: turn ended within 3 calls" % label)
	var acts: Array[Dictionary] = r["actions"]
	r["last"] = acts[acts.size() - 1] if not acts.is_empty() else {}
	r["self_dmg"] = QA_AI.damage_to(r["events"], id)
	r["copy"] = copy
	var parts: Array[String] = []
	for a: Dictionary in acts:
		parts.append(_desc(a))
	_notes.append("%-40s [%s] self-damage %d" % [label, ", ".join(parts), r["self_dmg"]])
	return r


var _t0: int = 0


func before_each() -> void:
	_t0 = Time.get_ticks_msec()


func after_each() -> void:
	_notes.append("time %d ms: %s" % [Time.get_ticks_msec() - _t0, gut.get_current_test_object().name])


func after_all() -> void:
	for n: String in _notes:
		gut.p("AIADV  " + n)


# --- buried / pit / walls ------------------------------------------------------------------------------

func test_cpu_fully_buried_in_dirt() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.tanks[0].fuel = 100
		QA_AI.fill_rect(s.terrain, 270, 330, 540, 600)  # 60 cells of dirt over the tank
		var r: Dictionary = _turn("buried %s" % NAMES[lv], s)
		assert_lt(r["self_dmg"] as int, s.tanks[0].health, "buried %s survives its first shot" % NAMES[lv])
		# Second turn from the crater it made: must not keep hurting itself.
		var copy: MatchState = r["copy"]
		if copy.phase == SimConstants.PHASE_AIM and copy.tanks[0].alive:
			if copy.current_tank == 1:
				Simulation.apply_action(copy, SimTestUtil.pass_turn(1))
			if copy.current_tank == 0:
				var r2: Dictionary = _turn("buried %s turn 2" % NAMES[lv], copy)
				assert_eq(r2["self_dmg"], 0, "second shot from the dug-out tank is harmless")


func test_cpu_in_a_deep_pit_with_steep_walls() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.terrain.flatten(286, 314, 800)  # 28 wide, 200 deep
		s.tanks[0].y = 800
		s.tanks[0].fuel = 100
		var r: Dictionary = _turn("pit %s" % NAMES[lv], s)
		var last: Dictionary = r["last"]
		assert_eq(last["kind"], "fire")
		assert_eq(r["self_dmg"], 0, "pit %s does not blow up its own walls" % NAMES[lv])
		assert_gt(last["angle"] as int, 800, "pit %s lobs steeply to clear 200-cell walls" % NAMES[lv])
		assert_lt(last["angle"] as int, 1000)


func test_target_behind_a_full_height_wall() -> void:
	# A wall that reaches row 0. Shells may still fly over the top of the map (y < 0 is open sky),
	# so the steepest lobs clear it; a flat shot does not.
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.terrain.flatten(640, 680, 0)
		for id: String in ["deep_bore", "bore_shell", "photon_lance"]:
			s.tanks[0].set_stock(id, 2)
		s.tanks[0].fuel = 100
		var r: Dictionary = _turn("full wall %s" % NAMES[lv], s)
		assert_eq(r["self_dmg"], 0)


func test_target_behind_a_tall_wall_and_on_a_mesa() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.terrain.flatten(640, 680, 200)
		for id: String in ["deep_bore", "bore_shell", "photon_lance"]:
			s.tanks[0].set_stock(id, 2)
		_turn("tall wall %s" % NAMES[lv], s)
		var m: MatchState = QA_AI.flat([300, 900], [lv, 2])
		m.terrain.flatten(880, 920, 300)
		m.tanks[1].y = 300
		_turn("mesa target %s" % NAMES[lv], m)


# --- map edges -------------------------------------------------------------------------------------------

func test_cpu_at_the_extreme_map_edges_shoots_towards_the_enemy() -> void:
	# 1576 cells apart, at the two extreme positions, in both directions, with max headwind / tailwind
	# and several seeds (the round's power bias flips sign with the seed).
	var miss: Dictionary = {1: [] as Array[int], 2: [] as Array[int], 3: [] as Array[int], 4: [] as Array[int]}
	for lv: int in LEVELS:
		for wind: int in [-100, 0, 100]:
			for side: int in [0, 1]:
				for seed_value: int in [1, 2, 3, 4]:
					var xs: Array[int] = [12, 1588]
					if side == 1:
						xs = [1588, 12]
					var s: MatchState = QA_AI.flat(xs, [lv, 2])
					s.wind = wind
					s.seed = seed_value
					var r: Dictionary = _turn("edge %s side %d wind %d seed %d" % [NAMES[lv], side, wind, seed_value], s)
					var last: Dictionary = r["last"]
					assert_eq(last["kind"], "fire", "edge shooter fires")
					if side == 0:
						assert_lte(last["angle"] as int, 900, "left-edge tank aims right (angle %d)" % last["angle"])
					else:
						assert_gte(last["angle"] as int, 900, "right-edge tank aims left (angle %d)" % last["angle"])
					for e: Dictionary in r["events"]:
						if e["type"] == "projectile_end":
							(miss[lv] as Array[int]).append(absi((e["x"] as int) - xs[1]))
	var line: String = "AIADV  edge duels, first-shot distance of the shell's end from the target column (cells, median/p90):"
	for lv: int in LEVELS:
		line += "  %s %d/%d" % [NAMES[lv], QA_AI.percentile(miss[lv], 50), QA_AI.percentile(miss[lv], 90)]
	gut.p(line)
	assert_lt(QA_AI.percentile(miss[4], 90), 200, "Expert's edge shots end near the target even across the whole map")
	assert_lt(QA_AI.percentile(miss[3], 90), 260)


func test_cpu_at_the_edge_with_an_enemy_next_door() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([12, 40], [lv, 2])
		var r: Dictionary = _turn("edge neighbour %s" % NAMES[lv], s)
		# Next door every blast reaches us: the self-damage rule (M4-Q fix) may pass instead of firing.
		assert_true((r["last"] as Dictionary)["kind"] in ["fire", "pass"], "fires or passes, level %d" % lv)
		assert_lt(r["self_dmg"] as int, 100)


# --- teams -------------------------------------------------------------------------------------------------

func test_only_a_teammate_alive_the_cpu_passes_and_never_targets_itself() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 900], [lv, 2])
		s.tanks[1].team = 0
		var r: Dictionary = _turn("only teammate %s" % NAMES[lv], s)
		assert_eq((r["last"] as Dictionary)["kind"], "pass", "no enemy: the CPU passes instead of shooting its teammate or itself")
		assert_eq(AiTargets.enemies_of(s, s.tanks[0]).size(), 0)
		assert_eq(QA_AI.damage_to(r["events"], 1), 0)


func test_teammate_in_the_line_of_fire_is_never_shot() -> void:
	var ally_hits: int = 0
	var total: int = 0
	for lv: int in LEVELS:
		for tx: int in [330, 350, 400, 500, 600, 700, 800, 900, 1050]:
			var s: MatchState = QA_AI.flat([300, tx, 1100], [lv, 2, 2])
			s.tanks[1].team = 0
			var r: Dictionary = _turn("ally x=%d %s" % [tx, NAMES[lv]], s)
			total += 1
			if QA_AI.damage_to(r["events"], 1) > 0:
				ally_hits += 1
	gut.p("AIADV  teammate hit by friendly fire in %d of %d shots" % [ally_hits, total])
	assert_eq(ally_hits, 0, "friendly fire")


func test_blast_next_to_a_teammate_is_reported() -> void:
	# Friendly splash: the enemy stands 30 cells from a teammate of the shooter. A Nova Core (r 90) hurts the
	# teammate; a Spark Dart / Pulse Missile would not. Teams equal ids today, so this is a forward-looking probe.
	var hurt: int = 0
	var cases: int = 0
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000, 1030], [lv, 2, 2])
		s.tanks[1].team = 0  # tank 1 is an ally standing right next to enemy tank 2
		s.tanks[0].set_stock("nova_core", 3)
		s.tanks[0].set_stock("hyperpulse", 3)
		var r: Dictionary = _turn("splash near ally %s" % NAMES[lv], s)
		cases += 1
		if QA_AI.damage_to(r["events"], 1) > 0:
			hurt += 1
	gut.p("AIADV  friendly splash: the teammate was hurt in %d of %d shots at an enemy 30 cells from it" % [hurt, cases])
	assert_eq(hurt, 0, "the CPU never fires an area weapon whose blast reaches a teammate (%d of %d levels did)" % [hurt, cases])


func test_targeting_never_picks_self_a_teammate_or_a_dead_tank() -> void:
	var bad: int = 0
	for i: int in range(40):
		var s: MatchState = AiTestUtil.random_state(3000 + i)
		var r: Rng = Rng.derive(i, 12)
		for t: TankState in s.tanks:
			t.team = r.range_int(0, 2)  # random alliances
		for me: TankState in s.tanks:
			if not me.alive:
				continue
			var enemies: Array[TankState] = AiTargets.enemies_of(s, me)
			for lv: int in LEVELS:
				var pick: TankState = AiTargets.pick(s, me, lv)
				if enemies.is_empty():
					if pick != null:
						bad += 1
				elif pick == null or pick.id == me.id or not pick.alive or pick.team == me.team:
					bad += 1
	assert_eq(bad, 0, "targets that were self / allies / dead / null")


# --- economy extremes ---------------------------------------------------------------------------------------

func test_cpu_with_no_money_and_no_stock_fires_spark_dart() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		QA_AI.clear_stock(s.tanks[0])
		s.tanks[0].money = 0
		var r: Dictionary = _turn("spark only %s" % NAMES[lv], s)
		var last: Dictionary = r["last"]
		assert_eq(last["kind"], "fire")
		assert_eq(last["weapon"], "spark_dart")
		assert_eq(r["calls"], 1)
	# The shop of a broke tank: nothing to buy, just ready.
	for lv: int in LEVELS:
		var st := MatchSettings.new()
		st.seed = 5
		st.num_tanks = 2
		st.start_money = 0
		st.controllers = PackedInt32Array([lv, lv])
		var shop: MatchState = Simulation.new_match(st)
		var acts: Array[Dictionary] = AiPlayer.shop_actions(shop, 0)
		assert_eq(acts, [{"kind": "ready", "tank": 0}] as Array[Dictionary], "broke %s shop: ready only" % NAMES[lv])
	# 1 credit short of the cheapest item.
	var st2 := MatchSettings.new()
	st2.seed = 6
	st2.num_tanks = 2
	st2.start_money = 999
	st2.controllers = PackedInt32Array([4, 1])
	var shop2: MatchState = Simulation.new_match(st2)
	assert_eq((AiPlayer.shop_actions(shop2, 0)).size(), 1, "999 credits buy nothing")


func test_cpu_with_everything_at_99() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 700, 1100], [lv, lv, lv])
		for t: TankState in s.tanks:
			QA_AI.give_everything(t)
			t.fuel = 300
		var used: Dictionary = {}
		var guard: int = 0
		while s.phase == SimConstants.PHASE_AIM and guard < 18:
			guard += 1
			var id: int = s.current_tank
			var r: Dictionary = QA_AI.play_turn(s, id)
			assert_eq(r["errors"], [] as Array[String], "99-stock %s turn %d" % [NAMES[lv], guard])
			assert_lte(r["calls"] as int, 3)
			for a: Dictionary in r["actions"]:
				var k: String = a.get("weapon", a.get("item", a["kind"]))
				used[k] = (used.get(k, 0) as int) + 1
		_notes.append("everything@99 %s used: %s" % [NAMES[lv], str(used)])
		assert_gt(used.size(), 1)
	# The shop with a full rack and plenty of money.
	var st := MatchSettings.new()
	st.seed = 9
	st.num_tanks = 3
	st.start_money = 1_000_000
	st.controllers = PackedInt32Array([1, 3, 4])
	var shop: MatchState = Simulation.new_match(st)
	for t: TankState in shop.tanks:
		QA_AI.give_everything(t)
	for t: TankState in shop.tanks:
		assert_eq(AiPlayer.shop_actions(shop, t.id), [{"kind": "ready", "tank": t.id}] as Array[Dictionary], "a full rack buys nothing (tank %d)" % t.id)


func test_rich_cpu_does_not_overbuy_and_every_buy_is_affordable() -> void:
	for lv: int in LEVELS:
		var st := MatchSettings.new()
		st.seed = 20 + lv
		st.num_tanks = 2
		st.start_money = 1_000_000
		st.controllers = PackedInt32Array([lv, lv])
		var shop: MatchState = Simulation.new_match(st)
		var acts: Array[Dictionary] = AiPlayer.shop_actions(shop, 0)
		var spent: int = 0
		for a: Dictionary in acts:
			assert_eq(Simulation.validate_action(shop, a), "")
			Simulation.apply_action(shop, a)
		spent = 1_000_000 - shop.tanks[0].money
		_notes.append("rich shop %s: %d actions, spent %d of 1,000,000" % [NAMES[lv], acts.size(), spent])
		assert_lt(spent, 200000, "%s keeps most of a huge purse" % NAMES[lv])


# --- shields, repulsors, wells ----------------------------------------------------------------------------

func test_enemy_with_fortress_field_and_repulsor_expert_counters() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.tanks[1].shield_type = Catalog.index_of("fortress_field")
		s.tanks[1].shield_hp = 100
		s.tanks[1].repulsor_charge = 100
		s.tanks[0].set_stock("static_burst", 3)
		s.tanks[0].set_stock("photon_lance", 3)
		var r: Dictionary = _turn("fortress+repulsor %s" % NAMES[lv], s)
		if lv == SimConstants.CTRL_EXPERT:
			assert_eq((r["last"] as Dictionary)["weapon"], "static_burst", "Expert strips the shield first")
	# Repulsor only: Expert uses the Photon Lance (a beam ignores the field).
	var s2: MatchState = QA_AI.flat([300, 900], [4, 2])
	s2.tanks[1].repulsor_charge = 100
	s2.tanks[0].set_stock("photon_lance", 3)
	var r2: Dictionary = _turn("repulsor only expert", s2)
	assert_eq((r2["last"] as Dictionary)["weapon"], "photon_lance")


func test_active_enemy_singularity_seed_near_the_cpu() -> void:
	for lv: int in LEVELS:
		for dx: int in [-150, -60, 60, 150]:
			var s: MatchState = QA_AI.flat([700, 1300], [lv, 2])
			s.wells.append({"owner": 1, "x": 700 + dx, "y": 450, "expires_turn": 99})
			var r: Dictionary = _turn("well near cpu dx=%d %s" % [dx, NAMES[lv]], s)
			assert_eq((r["last"] as Dictionary)["kind"], "fire")
	# A well right on top of the CPU's muzzle (inside its 4-cell dead zone).
	var s2: MatchState = QA_AI.flat([700, 1300], [4, 2])
	s2.wells.append({"owner": 1, "x": 700, "y": 588, "expires_turn": 99})
	_turn("well on the muzzle expert", s2)


func test_max_wind_both_ways_every_level() -> void:
	for lv: int in LEVELS:
		for wind: int in [-100, 100]:
			for dist: int in [250, 700, 1300]:
				var s: MatchState = QA_AI.flat([200, 200 + dist], [lv, 2])
				s.wind = wind
				var r: Dictionary = _turn("wind %d dist %d %s" % [wind, dist, NAMES[lv]], s)
				assert_eq((r["last"] as Dictionary)["kind"], "fire")


# --- crowds ---------------------------------------------------------------------------------------------------

func test_eight_cpus_packed_close_together() -> void:
	var xs: Array[int] = []
	var levels: Array[int] = []
	for i: int in range(8):
		xs.append(700 + 30 * i)
		levels.append(1 + i % 4)
	var s: MatchState = QA_AI.flat(xs, levels)
	for t: TankState in s.tanks:
		t.set_stock("hyperpulse", 3)
		t.set_stock("nova_core", 1)
		t.fuel = 100
	var self_hits: int = 0
	var suicides: int = 0
	var turns: int = 0
	var passes: int = 0
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 40:
		guard += 1
		var id: int = s.current_tank
		var r: Dictionary = QA_AI.play_turn(s, id)
		assert_eq(r["errors"], [] as Array[String], "packed turn %d (tank %d)" % [guard, id])
		assert_lte(r["calls"] as int, 3)
		turns += 1
		if QA_AI.damage_to(r["events"], id) > 0:
			self_hits += 1
		if QA_AI.destroyed(r["events"], id):
			suicides += 1
		if (r["actions"] as Array[Dictionary]).back()["kind"] == "pass":
			passes += 1
		assert_eq(QA_AI.M3.check_state(s), [] as Array[String], "invariants after packed turn %d" % guard)
	gut.p("AIADV  8 packed CPUs: %d turns, %d damaged themselves, %d suicides, %d passes, phase %s" % [turns, self_hits, suicides, passes, s.phase])
	assert_gt(turns, 3)
	assert_eq(passes, 0, "somebody always has a safe target in the packed crowd")
	assert_eq(self_hits, 0, "8 CPUs packed 30 cells apart: %d of %d turns damaged the shooter, %d suicides" % [self_hits, turns, suicides])


# --- repair -----------------------------------------------------------------------------------------------------

func test_cpu_at_one_hp_repairs_when_its_level_allows() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s.tanks[0].health = 1
		s.tanks[0].set_stock("nanorepair_kit", 2)
		var r: Dictionary = _turn("1 HP with a kit %s" % NAMES[lv], s)
		var last: Dictionary = r["last"]
		if lv >= SimConstants.CTRL_HARD:
			assert_eq(last["kind"], "use_item", "%s repairs at 1 HP" % NAMES[lv])
			assert_eq(last["item"], "nanorepair_kit")
			assert_eq((r["copy"] as MatchState).tanks[0].health, 41)
		else:
			assert_eq(last["kind"], "fire", "%s has no repair logic (docs/ARCHITECTURE.md section 29)" % NAMES[lv])
	# Thresholds: Hard repairs at <= 30, Expert at <= 45.
	for pair: Array in [[3, 30, true], [3, 31, false], [4, 45, true], [4, 46, false]]:
		var s2: MatchState = QA_AI.flat([300, 1000], [pair[0], 2])
		s2.tanks[0].health = pair[1]
		s2.tanks[0].set_stock("nanorepair_kit", 1)
		var a: Dictionary = AiPlayer.next_action(s2, 0)
		var repaired: bool = a["kind"] == "use_item" and a["item"] == "nanorepair_kit"
		assert_eq(repaired, pair[2], "level %d at %d HP" % [pair[0], pair[1]])
	# No kit: fire as usual, never an illegal repair.
	for lv: int in LEVELS:
		var s3: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		s3.tanks[0].health = 1
		var r3: Dictionary = _turn("1 HP, no kit %s" % NAMES[lv], s3)
		assert_eq((r3["last"] as Dictionary)["kind"], "fire")


func test_expert_at_one_hp_does_not_gamble_on_a_kill_it_may_miss() -> void:
	# Expert skips the repair if ANY enemy has <= 55 effective HP ("can kill"), without asking whether
	# the shot will hit. At 1 HP that is a coin flip for its life. Enemy 40 HP, 700 cells away.
	var s: MatchState = QA_AI.flat([300, 1000], [4, 2])
	s.tanks[0].health = 1
	s.tanks[0].set_stock("nanorepair_kit", 2)
	s.tanks[1].health = 40
	var r: Dictionary = _turn("1 HP vs 40 HP enemy expert", s)
	var last: Dictionary = r["last"]
	assert_eq(last["kind"], "use_item", "Expert at 1 HP with a kit heals instead of gambling (did: %s)" % _desc(last))


# --- movement ---------------------------------------------------------------------------------------------------

func test_walking_is_limited_to_hard_and_expert_and_stays_inside_three_calls() -> void:
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([360, 1000], [lv, 2])
		s.terrain.flatten(400, 460, 350)  # a 250-cell hill 40 cells in front of the tank
		s.tanks[0].fuel = 200
		var r: Dictionary = _turn("hill+fuel %s" % NAMES[lv], s)
		var kinds: Array[String] = []
		for a: Dictionary in r["actions"]:
			kinds.append(a["kind"])
		# No weapon reaches over this hill, so every level may walk (ARCHITECTURE §38 out-of-reach rule).
		assert_true(kinds.count("move") <= 1, "at most one walk per turn")
		assert_true(kinds.has("fire") or kinds.has("pass"), "%s still ends the turn" % NAMES[lv])
	# Cornered at the map edge with fuel: a walk must stay on the map (validate_action covers that).
	for lv: int in [3, 4]:
		var s2: MatchState = QA_AI.flat([14, 1000], [lv, 2])
		s2.terrain.flatten(40, 100, 300)
		s2.tanks[0].fuel = 200
		_turn("edge hill %s" % NAMES[lv], s2)


# --- self harm ------------------------------------------------------------------------------------------------------

func test_cpu_does_not_nuke_itself_at_point_blank_range() -> void:
	# Hard/Expert prefer the Nova Core (blast radius 90) as the "weapon that kills" even when the
	# target is 26-90 cells away, i.e. inside its own blast. A Pulse Missile / Spark Dart (r 28 / 14)
	# or a hyperpulse would hurt the enemy just as well from there.
	var worst: String = ""
	var worst_dmg: int = 0
	var cases: int = 0
	var hurt: int = 0
	for lv: int in LEVELS:
		for d: int in range(26, 100, 8):
			var s: MatchState = QA_AI.flat([300, 300 + d], [lv, 0])
			s.tanks[0].set_stock("nova_core", 5)
			s.tanks[0].set_stock("hyperpulse", 5)
			var r: Dictionary = _turn("close d=%d %s" % [d, NAMES[lv]], s)
			cases += 1
			if (r["self_dmg"] as int) > 0:
				hurt += 1
			if (r["self_dmg"] as int) > worst_dmg:
				worst_dmg = r["self_dmg"] as int
				worst = "%s at %d cells fired %s and took %d damage (destroyed: %s)" % [NAMES[lv], d, _desc(r["last"]), worst_dmg, str(QA_AI.destroyed(r["events"], 0))]
	assert_eq(worst_dmg, 0, "no self-damage at point-blank range (%d of %d shots hurt; worst: %s)" % [hurt, cases, worst])


func test_cpu_sealed_in_a_tight_chamber_does_not_hurt_itself() -> void:
	# Every shot explodes on the chamber wall next to the tank; the only harmless option is pass. (An Easy
	# tank may take a small self-hit of at most 10; none of the levels does today.)
	var hurt: int = 0
	var worst: int = 0
	var desc: String = ""
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([300, 1000], [lv, 2])
		QA_AI.fill_rect(s.terrain, 150, 450, 300, 600)
		QA_AI.clear_rect(s.terrain, 282, 318, 560, 600)  # 36 wide, 40 tall: 6 cells of room each side
		var r: Dictionary = _turn("sealed chamber %s" % NAMES[lv], s)
		assert_gte((r["copy"] as MatchState).tanks[0].health, 1, "survives")
		if (r["self_dmg"] as int) > (10 if lv == SimConstants.CTRL_EASY else 0):
			hurt += 1
			if (r["self_dmg"] as int) > worst:
				worst = r["self_dmg"] as int
				desc = "%s: %s took %d" % [NAMES[lv], _desc(r["last"]), worst]
	assert_eq(hurt, 0, "the CPU in a sealed chamber passes instead of hitting its own wall (%d of 4 levels hurt themselves: %s)" % [hurt, desc])


# --- entry points with strange arguments --------------------------------------------------------------------------

func test_entry_points_survive_strange_arguments() -> void:
	var s: MatchState = QA_AI.flat([300, 1000, 1500], [2, 2, 2])
	# Wrong tank, dead tank, out-of-range ids: a harmless dictionary comes back, no crash.
	for id: int in [-1, 3, 99, 1, 2]:
		var a: Dictionary = AiPlayer.next_action(s, id)
		assert_true(a.has("kind"), "next_action(%d) returns an action dictionary" % id)
	s.tanks[0].alive = false
	s.tanks[0].health = 0
	var dead: Dictionary = AiPlayer.next_action(s, 0)
	assert_true(dead.has("kind"))
	# The state is flat_state, which is in the aim phase: shop_actions must be empty.
	assert_eq(AiPlayer.shop_actions(s, 1), [] as Array[Dictionary], "no shopping in the aim phase")
	assert_eq(AiPlayer.shop_actions(s, -1), [] as Array[Dictionary])
	assert_eq(AiPlayer.shop_actions(s, 77), [] as Array[Dictionary])
	# Shop phase: next_action does not crash and a ready tank gets no shop actions.
	var shop: MatchState = SimTestUtil.shop_state(3, 1, 3)
	shop.settings.controllers = PackedInt32Array([2, 3, 4])
	var a2: Dictionary = AiPlayer.next_action(shop, 0)
	assert_true(a2.has("kind"))
	Simulation.apply_action(shop, SimTestUtil.ready(1))
	assert_eq(AiPlayer.shop_actions(shop, 1), [] as Array[Dictionary], "an already-ready tank gets nothing")
	# Match over.
	var over: MatchState = shop.duplicate_state()
	over.phase = SimConstants.PHASE_MATCH_OVER
	assert_true(AiPlayer.next_action(over, 0).has("kind"))
	assert_eq(AiPlayer.shop_actions(over, 0), [] as Array[Dictionary])
	# Last tank standing in the aim phase (a state the sim would never leave open): pass.
	var lone: MatchState = QA_AI.flat([300, 1000], [4, 4])
	lone.tanks[1].alive = false
	lone.tanks[1].health = 0
	var a3: Dictionary = AiPlayer.next_action(lone, 0)
	assert_eq(a3["kind"], "pass")
	assert_eq(Simulation.validate_action(lone, a3), "")
	# A human slot handed to the AI plays as Normal.
	var h: MatchState = QA_AI.flat([300, 1000], [0, 0])
	assert_eq(AiProfile.level_of(h, 0), SimConstants.CTRL_NORMAL)
	assert_eq(Simulation.validate_action(h, AiPlayer.next_action(h, 0)), "")


func test_last_two_tanks_can_kill_each_other_and_the_ai_survives_the_aftermath() -> void:
	# Both CPUs at 1 HP, 40 cells apart, nova cores in hand: whoever shoots may kill both.
	for lv: int in LEVELS:
		var s: MatchState = QA_AI.flat([500, 540], [lv, lv])
		for t: TankState in s.tanks:
			t.health = 1
			t.set_stock("nova_core", 2)
		var r: Dictionary = QA_AI.play_turn(s, 0)
		assert_eq(r["errors"], [] as Array[String])
		if QA_AI.QaUtil.alive_count(s) <= 1:
			assert_ne(s.phase, SimConstants.PHASE_AIM, "round decided when <= 1 tank is alive")
		else:
			assert_eq(s.phase, SimConstants.PHASE_AIM)
		assert_eq(QA_AI.M3.check_state(s), [] as Array[String])
