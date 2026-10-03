extends GutTest
## Weapon choice and the aim for each kind of weapon, per difficulty.

const ALL_WEAPONS: Array[String] = [
	"pulse_missile", "hyperpulse", "nova_core", "supernova", "prism_splitter", "prism_cascade",
	"glide_orb", "heavy_orb", "bore_shell", "deep_bore", "mound_mortar", "landslide", "sludge_shell",
	"ember_rain", "inferno_gel", "seeker", "photon_lance", "static_burst", "singularity_seed",
	"riptide_anchor",
]
const EXPERT_ONLY: Array[String] = ["static_burst", "singularity_seed", "riptide_anchor"]


func _stock_all(units: int = 5) -> Dictionary:
	var d: Dictionary = {}
	for id: String in ALL_WEAPONS:
		d[id] = units
	return d


func _chosen(state: MatchState, level: int) -> String:
	var me: TankState = state.tanks[0]
	var sit: AiSituation = AiPlayer.situation(state, me, level, AiProfile.for_level(level),
			AiTargets.enemies_of(state, me))
	return AiWeapons.choose_and_plan(sit)["weapon"]


func _fired_weapons(level: int, n: int, tag: int) -> Dictionary:
	var seen: Dictionary = {}
	for i: int in range(n):
		var p: Vector2i = AiTestUtil.params(i, tag)
		var state: MatchState = AiTestUtil.duel(8000 + i, level, p.x, p.y, _stock_all())
		var w: String = _chosen(state, level)
		seen[w] = (seen.get(w, 0) as int) + 1
	return seen


func test_easy_only_ever_fires_basic_missiles() -> void:
	var seen: Dictionary = _fired_weapons(SimConstants.CTRL_EASY, 40, 1)
	gut.p("WEAPONS easy picks (owning everything): %s" % str(seen))
	for id: String in seen.keys():
		assert_true(id == "pulse_missile" or id == "hyperpulse", "Easy fired %s" % id)
	assert_gte(seen.size(), 2, "and it varies between them (random choice)")


func test_normal_and_hard_never_use_the_expert_only_weapons() -> void:
	for level: int in [SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD]:
		var seen: Dictionary = _fired_weapons(level, 40, 2)
		gut.p("WEAPONS level %d picks (owning everything): %s" % [level, str(seen)])
		for id: String in EXPERT_ONLY:
			assert_false(seen.has(id), "level %d fired Expert-only %s" % [level, id])
	var normal: Dictionary = _fired_weapons(SimConstants.CTRL_NORMAL, 40, 2)
	for id: String in ["photon_lance", "bore_shell", "deep_bore", "glide_orb", "heavy_orb", "mound_mortar"]:
		assert_false(normal.has(id), "Normal fired the specialist weapon %s" % id)


func test_the_cheapest_weapon_that_kills_is_used() -> void:
	var cases: Array = [[20, "spark_dart"], [30, "spark_dart"], [50, "pulse_missile"], [55, "pulse_missile"],
			[65, "hyperpulse"], [70, "hyperpulse"], [95, "nova_core"]]
	for c: Array in cases:
		var state: MatchState = AiTestUtil.duel(5, SimConstants.CTRL_EXPERT, 700, 0,
				{"pulse_missile": 5, "hyperpulse": 5, "nova_core": 2})
		state.tanks[1].health = c[0]
		assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), c[1], "Expert vs %d hp" % c[0])
	var hard: MatchState = AiTestUtil.duel(5, SimConstants.CTRL_HARD, 700, 0, {"pulse_missile": 5, "hyperpulse": 5})
	hard.tanks[1].health = 20
	assert_eq(_chosen(hard, SimConstants.CTRL_HARD), "pulse_missile", "Hard leaves the Spark Dart alone")


func test_normal_uses_a_big_blast_on_a_healthy_distant_target() -> void:
	var state: MatchState = AiTestUtil.duel(5, SimConstants.CTRL_NORMAL, 800, 0,
			{"pulse_missile": 5, "hyperpulse": 5, "nova_core": 1})
	assert_eq(_chosen(state, SimConstants.CTRL_NORMAL), "nova_core")
	state.tanks[1].health = 40
	assert_eq(_chosen(state, SimConstants.CTRL_NORMAL), "pulse_missile", "a weak target needs no Nova")


# --- Photon Lance ------------------------------------------------------------------------------

func test_lance_in_a_gale_hits_and_ignores_the_wind() -> void:
	var hits: int = 0
	for i: int in range(12):
		var level: int = SimConstants.CTRL_HARD if i % 2 == 0 else SimConstants.CTRL_EXPERT
		var state: MatchState = AiTestUtil.flat_duel(level, 400 + i * 35, 95 if i % 3 != 0 else -95,
				{"photon_lance": 3, "pulse_missile": 5})
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		assert_eq(turn["action"]["weapon"], "photon_lance", "gale: the beam ignores wind (dist %d)" % (400 + i * 35))
		if AiTestUtil.hit_target(turn["events"]):
			hits += 1
	assert_gte(hits, 11, "the beam finds the target: %d/12" % hits)


func test_lance_counters_a_repulsor_and_is_skipped_when_the_line_is_blocked() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 600, 0, {"photon_lance": 3, "pulse_missile": 5})
	state.tanks[1].repulsor_charge = 80
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "photon_lance")
	state.terrain.flatten(400, 600, 0)  # a 200-cell wall: the beam cuts at most 120 solid cells
	assert_ne(_chosen(state, SimConstants.CTRL_EXPERT), "photon_lance", "blocked line: not the lance")
	var calm: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 600, 0, {"photon_lance": 3, "pulse_missile": 5})
	assert_ne(_chosen(calm, SimConstants.CTRL_EXPERT), "photon_lance", "no gale, no repulsor: a missile is cheaper")


# --- Static Burst --------------------------------------------------------------------------------

func test_expert_strips_a_shield_with_static_burst_hard_does_not() -> void:
	var stripped: int = 0
	for i: int in range(10):
		var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 500 + i * 40, 0,
				{"static_burst": 2, "pulse_missile": 5})
		state.tanks[1].shield_type = Catalog.index_of("ion_shield")
		state.tanks[1].shield_hp = 60
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		assert_eq(turn["action"]["weapon"], "static_burst")
		if not state.tanks[1].has_shield():
			stripped += 1
	assert_gte(stripped, 9, "the shield is gone after the burst: %d/10" % stripped)
	var hard: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_HARD, 600, 0, {"static_burst": 2, "pulse_missile": 5})
	hard.tanks[1].shield_type = Catalog.index_of("ion_shield")
	hard.tanks[1].shield_hp = 60
	assert_ne(_chosen(hard, SimConstants.CTRL_HARD), "static_burst")


# --- Seeker ---------------------------------------------------------------------------------------

func test_seeker_is_chosen_in_strong_wind_and_hits() -> void:
	for level: int in [SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		var hits: int = 0
		var chosen: int = 0
		for i: int in range(15):
			var wind: int = 75 if i % 2 == 0 else -75
			var state: MatchState = AiTestUtil.flat_duel(level, 450 + i * 40, wind, {"seeker": 6, "pulse_missile": 6})
			if _chosen(state, level) == "seeker":
				chosen += 1
			var res: Dictionary = AiTestUtil.shoot_until_hit(state, 3)
			if res["first_hit"] > 0:
				hits += 1
		gut.p("SEEKER level %d: chosen %d/15 in wind 75, hit within 3 shots %d/15" % [level, chosen, hits])
		assert_eq(chosen, 15, "level %d takes the Seeker in strong wind" % level)
		assert_gte(hits, 13 if level > 2 else 10, "level %d hits" % level)


func test_a_light_breeze_does_not_call_for_a_seeker() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_HARD, 700, 20, {"seeker": 6, "pulse_missile": 6})
	assert_eq(_chosen(state, SimConstants.CTRL_HARD), "pulse_missile")


func test_seeker_aim_tolerates_a_wide_error() -> void:
	# The shell steers itself in: even a plan that is 30 cells off by the plain model is accepted.
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_HARD, 800, 80, {"seeker": 6})
	var me: TankState = state.tanks[0]
	var sit: AiSituation = AiPlayer.situation(state, me, 3, AiProfile.for_level(3), AiTargets.enemies_of(state, me))
	var plan: Dictionary = AiWeapons.plan_for(sit, "seeker")
	assert_eq(plan["weapon"], "seeker")
	assert_true(plan["ok"])
	assert_eq(AiWeapons.SEEKER_TOL, 40)


# --- Prism Splitter -----------------------------------------------------------------------------------

func test_normal_spreads_a_splitter_at_long_range_and_still_learns() -> void:
	var hits: int = 0
	for i: int in range(20):
		var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_NORMAL, 750 + i * 20, 10,
				{"prism_splitter": 20})
		assert_eq(_chosen(state, SimConstants.CTRL_NORMAL), "prism_splitter")
		if AiTestUtil.shoot_until_hit(state, 4)["first_hit"] > 0:
			hits += 1
	gut.p("SPLITTER Normal at 750-1130 cells: hit within 4 shots %d/20" % hits)
	assert_gte(hits, 14)


func test_expert_uses_a_splitter_on_clustered_enemies() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 800, 0, {"prism_splitter": 4, "pulse_missile": 5})
	var third := TankState.new()
	third.id = 2
	third.team = 2
	third.x = state.tanks[1].x + 60
	third.y = state.tanks[1].y
	third.inventory = Catalog.new_inventory()
	state.tanks.append(third)
	state.settings.num_tanks = 3
	state.settings.controllers = PackedInt32Array([SimConstants.CTRL_EXPERT, 0, 0])
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "prism_splitter")
	third.x = state.tanks[1].x + 400
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "pulse_missile", "no cluster, no splitter")


# --- Glide Orb / Heavy Orb --------------------------------------------------------------------------------

func _pit_duel(level: int, i: int, stock: Dictionary) -> MatchState:
	var state: MatchState = AiTestUtil.flat_duel(level, 600 + i * 30, 0, stock)
	var tg: TankState = state.tanks[1]
	state.terrain.carve_circle(tg.x, 540, 90)  # a bowl: the target rests in the bottom
	tg.y = TankState.rest_y(state.terrain, tg.x)
	return state


func test_a_roller_is_chosen_for_a_target_in_a_pit_and_rolls_in() -> void:
	for level: int in [SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		var chosen: int = 0
		var hits: int = 0
		for i: int in range(10):
			var state: MatchState = _pit_duel(level, i, {"glide_orb": 5, "heavy_orb": 5, "pulse_missile": 5})
			var w: String = _chosen(state, level)
			if w == "heavy_orb" or w == "glide_orb":
				chosen += 1
			var turn: Dictionary = AiTestUtil.play_turn(state, 0)
			if AiTestUtil.hit_target(turn["events"]):
				hits += 1
		gut.p("ROLLER level %d: chosen %d/10 for a target in a 90-cell bowl, first shot hit %d/10" % [level, chosen, hits])
		assert_gte(chosen, 7, "level %d" % level)
		assert_gte(hits, 5, "the orb rolls into the bowl (level %d)" % level)
	var normal: MatchState = _pit_duel(SimConstants.CTRL_NORMAL, 0, {"glide_orb": 5, "pulse_missile": 5})
	assert_eq(_chosen(normal, SimConstants.CTRL_NORMAL), "pulse_missile", "Normal does not know the trick")


func test_no_roller_on_open_flat_ground() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 700, 0, {"glide_orb": 5, "pulse_missile": 5})
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "pulse_missile")


# --- Bore Shell / Deep Bore ---------------------------------------------------------------------------------

func _walled_duel(level: int, stock: Dictionary) -> MatchState:
	# A wall reaching the top of the map, with the target tucked 25 cells behind it: no lob can
	# come down that steeply, so the only way in is through.
	var state: MatchState = AiTestUtil.flat_duel(level, 500, 0, stock)
	state.terrain.flatten(600, 735, 0)
	state.tanks[1].x = 760
	return state


func test_a_hill_no_lob_can_clear_is_tunnelled_through() -> void:
	for level: int in [SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		var chosen: int = 0
		var planned_hits: int = 0
		var played_hits: int = 0
		for i: int in range(8):
			var state: MatchState = _walled_duel(level, {"deep_bore": 3, "bore_shell": 3, "pulse_missile": 5})
			state.tanks[1].x = 752 + i * 2
			var me: TankState = state.tanks[0]
			var sit: AiSituation = AiPlayer.situation(state, me, level, AiProfile.for_level(level),
					AiTargets.enemies_of(state, me))
			assert_false(sit.direct["ok"], "no lob reaches the target behind the wall")
			var plan: Dictionary = AiWeapons.choose_and_plan(sit)
			if plan["weapon"] == "deep_bore" or plan["weapon"] == "bore_shell":
				chosen += 1
			# The exact plan (before the human-like error) against a copy of the state.
			var copy: MatchState = state.duplicate_state()
			var ideal: Dictionary = {"kind": "fire", "tank": 0, "angle": plan["angle"], "power": plan["power"],
					"weapon": plan["weapon"]}
			if AiTestUtil.hit_target(Simulation.apply_action(copy, ideal)):
				planned_hits += 1
			if AiTestUtil.shoot_until_hit(state, 3)["first_hit"] > 0:
				played_hits += 1
		gut.p("TUNNEL level %d: tunneler chosen %d/8 for a target behind a full-height wall; the exact plan damages it %d/8, a human-like shot within 3 tries %d/8" % [
				level, chosen, planned_hits, played_hits])
		assert_gte(chosen, 7, "level %d tunnels" % level)
		assert_gte(planned_hits, 7, "the bore comes out at the target (level %d)" % level)
		assert_gte(played_hits, 6 if level == SimConstants.CTRL_EXPERT else 4, "and with its real shots (level %d)" % level)


func test_no_tunneler_when_a_lob_reaches() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 700, 0, {"deep_bore": 3, "pulse_missile": 5})
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "pulse_missile")


# --- Mound Mortar / Landslide ---------------------------------------------------------------------------------

func test_with_no_real_missile_left_dirt_can_bury_a_healthy_target() -> void:
	var buried: int = 0
	var tried: int = 0
	for i: int in range(24):
		var level: int = SimConstants.CTRL_HARD if i % 2 == 0 else SimConstants.CTRL_EXPERT
		var state: MatchState = AiTestUtil.duel(900 + i, level, 600 + i * 15, 0, {"landslide": 3, "mound_mortar": 3})
		var me: TankState = state.tanks[0]
		var sit: AiSituation = AiPlayer.situation(state, me, level, AiProfile.for_level(level),
				AiTargets.enemies_of(state, me))
		var plan: Dictionary = AiWeapons.plan_for(sit, "mound_mortar")
		assert_eq(plan["weapon"], "mound_mortar")
		if sit.direct["ok"]:
			assert_true(plan["ok"], "the mortar can be aimed when a lob reaches")
		var w: String = _chosen(state, level)
		if w == "mound_mortar" or w == "landslide":
			tried += 1
			var t: TankState = state.tanks[1]
			var solid_before: int = 0
			for x: int in range(t.x - 30, t.x + 30):
				for y: int in range(t.y - 60, t.y - 12):
					solid_before += 1 if state.terrain.is_solid(x, y) else 0
			var turn: Dictionary = AiTestUtil.play_turn(state, 0)
			var solid_after: int = 0
			for x: int in range(t.x - 30, t.x + 30):
				for y: int in range(t.y - 60, t.y - 12):
					solid_after += 1 if state.terrain.is_solid(x, y) else 0
			if solid_after > solid_before + 50 and not AiTestUtil.hit_target(turn["events"]):
				buried += 1
	gut.p("DIRT    chosen %d/24 when only dirt and a Spark Dart are left; piled on the target %d times" % [tried, buried])
	assert_gt(tried, 0, "sometimes the AI goes for the burial")
	assert_gte(buried * 10, tried * 7, "and the dirt lands on the target")


func test_dirt_is_not_used_while_a_real_missile_is_in_the_rack() -> void:
	for i: int in range(10):
		var state: MatchState = AiTestUtil.duel(950 + i, SimConstants.CTRL_EXPERT, 700, 0,
				{"landslide": 3, "mound_mortar": 3, "pulse_missile": 3})
		assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "pulse_missile")


# --- Singularity Seed ------------------------------------------------------------------------------------------

func test_expert_drops_a_singularity_seed_on_a_far_target_and_keeps_hitting_through_it() -> void:
	var seeded: int = 0
	var hits: int = 0
	for i: int in range(12):
		var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 600 + i * 40, 20,
				{"singularity_seed": 2, "pulse_missile": 9})
		var first: Dictionary = AiTestUtil.play_turn(state, 0)
		if first["action"]["weapon"] == "singularity_seed":
			seeded += 1
			assert_eq(state.wells.size(), 1, "the seed makes a well")
		var res: Dictionary = AiTestUtil.shoot_until_hit(state, 3)
		if res["first_hit"] > 0 or AiTestUtil.hit_target(first["events"]):
			hits += 1
	gut.p("WELL    seed dropped %d/12; target damaged within 3 follow-up shots through the well: %d/12" % [seeded, hits])
	assert_eq(seeded, 12)
	assert_gte(hits, 10, "the AI aims correctly with a well bending its shells")


func test_no_seed_when_the_target_is_close_or_a_well_exists() -> void:
	var close: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 300, 0, {"singularity_seed": 2, "pulse_missile": 9})
	assert_eq(_chosen(close, SimConstants.CTRL_EXPERT), "pulse_missile", "it would pull our own shells too")
	var far: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 800, 0, {"singularity_seed": 2, "pulse_missile": 9})
	far.wells.append({"owner": 1, "x": 900, "y": 400, "expires_turn": 8})
	assert_eq(_chosen(far, SimConstants.CTRL_EXPERT), "pulse_missile", "one well at a time")


# --- Riptide Anchor ----------------------------------------------------------------------------------------------

func test_expert_drags_a_target_off_a_ledge_with_riptide_anchor() -> void:
	var fell: int = 0
	var chosen: int = 0
	for i: int in range(10):
		var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 600 + i * 30, 0,
				{"riptide_anchor": 2, "pulse_missile": 5})
		var tg: TankState = state.tanks[1]
		state.terrain.flatten(tg.x - 20, tg.x + 19, 500)  # a 100-cell tower
		tg.y = TankState.rest_y(state.terrain, tg.x)
		if _chosen(state, SimConstants.CTRL_EXPERT) == "riptide_anchor":
			chosen += 1
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		if not SimTestUtil.find(turn["events"], "tank_fall").is_empty():
			fell += 1
	gut.p("ANCHOR  chosen %d/10 for a target on a 100-cell tower; it fell %d/10" % [chosen, fell])
	assert_gte(chosen, 8)
	assert_gte(fell, 7)


func test_no_anchor_on_flat_ground() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 700, 0, {"riptide_anchor": 2, "pulse_missile": 5})
	assert_eq(_chosen(state, SimConstants.CTRL_EXPERT), "pulse_missile", "nothing to fall off")


func test_an_anchor_is_not_fired_from_inside_its_own_pull_radius() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 200, 0, {"riptide_anchor": 2, "pulse_missile": 5})
	var tg: TankState = state.tanks[1]
	state.terrain.flatten(tg.x - 20, tg.x + 19, 500)
	tg.y = TankState.rest_y(state.terrain, tg.x)
	assert_ne(_chosen(state, SimConstants.CTRL_EXPERT), "riptide_anchor", "it would drag the shooter along")


# --- Teams ----------------------------------------------------------------------------------------------------

func test_a_teammate_in_the_line_of_fire_is_lobbed_over_not_hit() -> void:
	var safe: int = 0
	var on_target: int = 0
	for i: int in range(10):
		var level: int = SimConstants.CTRL_HARD if i % 2 == 0 else SimConstants.CTRL_EXPERT
		var state: MatchState = AiTestUtil.flat_duel(level, 700 + i * 20, 0, {"pulse_missile": 9})
		# A teammate standing right in the way, half way to the target.
		var mate := TankState.new()
		mate.id = 2
		mate.team = state.tanks[0].team
		mate.x = 300 + 350 + i * 10
		mate.y = state.tanks[0].y
		mate.inventory = Catalog.new_inventory()
		state.tanks.append(mate)
		state.settings.num_tanks = 3
		state.settings.controllers = PackedInt32Array([level, 0, 0])
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		if mate.health == SimConstants.MAX_HEALTH:
			safe += 1
		assert_eq(mate.health, SimConstants.MAX_HEALTH, "level %d, dist %d: the teammate was spared" % [level, 700 + i * 20])
		if level == SimConstants.CTRL_EXPERT and AiTestUtil.hit_target(turn["events"]):
			on_target += 1
	gut.p("TEAMS   a teammate stood in the line of fire: spared %d/10, Expert still hit the target %d/5" % [safe, on_target])
	assert_eq(safe, 10)
	assert_gte(on_target, 4, "and the Expert's high lob still finds the target")
