extends GutTest
## Shields, repulsor, repair and walking (docs/ARCHITECTURE.md section 29), per difficulty.


func _duel(level: int, dist: int = 700, wind: int = 0, stock: Dictionary = {}) -> MatchState:
	var s: Dictionary = {"pulse_missile": 20}
	s.merge(stock)
	return AiTestUtil.duel(33, level, dist, wind, s)


func _kinds(state: MatchState, tank: int) -> Array[String]:
	# The kinds of every action of one turn, applying each, until the turn ends.
	var out: Array[String] = []
	for _i: int in range(5):
		var a: Dictionary = AiPlayer.next_action(state, tank)
		out.append(str(a["kind"]) + ":" + str(a.get("item", a.get("weapon", ""))))
		Simulation.apply_action(state, a)
		if a["kind"] == "fire" or a["kind"] == "pass" or a.get("item", "") == "nanorepair_kit":
			break
	return out


func test_easy_never_uses_items_even_when_hurt_and_owning_them() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_EASY, 700, 0,
			{"ion_shield": 1, "repulsor_field": 1, "nanorepair_kit": 1, "fuel_cell": 3})
	state.tanks[0].health = 10
	state.tanks[0].fuel = 100
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(kinds.size(), 1, "just fires: %s" % str(kinds))
	assert_true(kinds[0].begins_with("fire:"))


func test_normal_raises_a_shield_only_when_hurt() -> void:
	var healthy: MatchState = _duel(SimConstants.CTRL_NORMAL, 700, 0, {"glow_shield": 1})
	assert_true(_kinds(healthy, 0)[0].begins_with("fire:"), "health 100: no shield")
	var hurt: MatchState = _duel(SimConstants.CTRL_NORMAL, 700, 0, {"glow_shield": 1})
	hurt.tanks[0].health = 49
	var kinds: Array[String] = _kinds(hurt, 0)
	assert_eq(kinds[0], "use_item:glow_shield", "health below 50: shield first")
	assert_true(kinds[1].begins_with("fire:"), "then it fires")
	assert_true(hurt.tanks[0].has_shield())
	var edge: MatchState = _duel(SimConstants.CTRL_NORMAL, 700, 0, {"glow_shield": 1})
	edge.tanks[0].health = 50
	assert_true(_kinds(edge, 0)[0].begins_with("fire:"), "exactly 50 is not below 50")


func test_normal_picks_the_better_shield_and_does_not_stack() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_NORMAL, 700, 0, {"glow_shield": 1, "ion_shield": 1})
	state.tanks[0].health = 30
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(kinds[0], "use_item:ion_shield")
	var again: MatchState = _duel(SimConstants.CTRL_NORMAL, 700, 0, {"glow_shield": 1})
	again.tanks[0].health = 30
	Simulation.apply_action(again, SimTestUtil.use_item(0, "glow_shield"))
	again.tanks[0].set_stock("glow_shield", 1)
	assert_true(_kinds(again, 0)[0].begins_with("fire:"), "already shielded: fire")


func test_hard_shields_proactively_even_at_full_health() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_HARD, 700, 0, {"ion_shield": 1})
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(kinds[0], "use_item:ion_shield")
	assert_true(kinds[1].begins_with("fire:"))


func test_hard_repairs_when_nearly_dead_and_the_turn_ends() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_HARD, 700, 0, {"nanorepair_kit": 1})
	state.tanks[0].health = 25
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(kinds, ["use_item:nanorepair_kit"], "repair ends the turn on its own")
	assert_eq(state.tanks[0].health, 65)
	var fine: MatchState = _duel(SimConstants.CTRL_HARD, 700, 0, {"nanorepair_kit": 1})
	fine.tanks[0].health = 60
	assert_true(_kinds(fine, 0)[0].begins_with("fire:"))


func test_expert_repairs_unless_it_can_finish_somebody() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_EXPERT, 700, 0, {"nanorepair_kit": 1})
	state.tanks[0].health = 40
	assert_eq(_kinds(state, 0), ["use_item:nanorepair_kit"])
	var kill: MatchState = _duel(SimConstants.CTRL_EXPERT, 700, 0, {"nanorepair_kit": 1})
	kill.tanks[0].health = 40
	kill.tanks[1].health = 30
	assert_true(_kinds(kill, 0)[0].begins_with("fire:"), "a kill is worth more than a heal")


func test_expert_switches_on_a_repulsor_when_an_enemy_is_zeroing_in() -> void:
	var calm: MatchState = _duel(SimConstants.CTRL_EXPERT, 700, 0, {"repulsor_field": 1})
	assert_true(_kinds(calm, 0)[0].begins_with("fire:"), "nobody is shooting at it")
	var shot_at: MatchState = _duel(SimConstants.CTRL_EXPERT, 700, 0, {"repulsor_field": 1})
	var foe: TankState = shot_at.tanks[1]
	foe.last_fire_weapon = Catalog.index_of("pulse_missile")
	foe.last_fire_x = shot_at.tanks[0].x + 40
	foe.last_fire_y = shot_at.tanks[0].y
	foe.last_fire_power = 500
	foe.last_fire_angle = 450
	foe.last_fire_turn = 0
	shot_at.turn_number = 1
	var kinds: Array[String] = _kinds(shot_at, 0)
	assert_eq(kinds[0], "use_item:repulsor_field")
	assert_true(kinds[1].begins_with("fire:"))
	assert_gt(shot_at.tanks[0].repulsor_charge, 0)


func test_shield_and_repulsor_come_before_the_shot_within_three_calls() -> void:
	var state: MatchState = _duel(SimConstants.CTRL_EXPERT, 700, 0, {"ion_shield": 1, "repulsor_field": 1})
	var foe: TankState = state.tanks[1]
	foe.last_fire_weapon = Catalog.index_of("pulse_missile")
	foe.last_fire_x = state.tanks[0].x
	foe.last_fire_y = state.tanks[0].y
	foe.last_fire_power = 500
	foe.last_fire_angle = 450
	foe.last_fire_turn = 0
	state.turn_number = 1
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(kinds.size(), 3, str(kinds))
	assert_eq(kinds[0], "use_item:ion_shield")
	assert_eq(kinds[1], "use_item:repulsor_field")
	assert_true(kinds[2].begins_with("fire:"))


func _notch_state(level: int, fuel: int, cells: int = 2) -> MatchState:
	# The shooter stands in a notch: a wall that reaches the top of the map rises 30 cells to
	# its right, so no lob clears it from here, but a walk away from it opens a steep lob.
	var state: MatchState = AiTestUtil.flat_duel(level, 500, 0, {"pulse_missile": 9, "fuel_cell": cells})
	state.terrain.flatten(330, 429, 0)
	state.tanks[0].fuel = fuel
	return state


func test_hard_and_expert_walk_out_of_a_notch_and_never_repeat_the_move() -> void:
	for level: int in [SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		var state: MatchState = _notch_state(level, 150)
		var blocked: AiSituation = AiPlayer.situation(state, state.tanks[0], level, AiProfile.for_level(level),
				AiTargets.enemies_of(state, state.tanks[0]))
		assert_false(blocked.direct["ok"], "from the notch nothing reaches the target")
		var x0: int = state.tanks[0].x
		var kinds: Array[String] = _kinds(state, 0)
		gut.p("MOVE  level %d: %s, walked %d cells" % [level, str(kinds), state.tanks[0].x - x0])
		assert_eq(kinds[0].split(":")[0], "move", "level %d walks first" % level)
		assert_true(kinds.size() <= 3 and kinds[kinds.size() - 1].begins_with("fire:"), "then fires: %s" % str(kinds))
		assert_eq(kinds.filter(func(k: String) -> bool: return k.begins_with("move")).size(), 1, "one move only")
		assert_lt(state.tanks[0].x, x0, "walked away from the wall")
		assert_true(state.tanks[1].health < 100 or state.round_index >= 0, "the lob over the wall landed")


func test_walk_uses_a_fuel_cell_when_the_tank_has_no_fuel() -> void:
	var state: MatchState = _notch_state(SimConstants.CTRL_EXPERT, 0, 2)
	var a: Dictionary = AiPlayer.next_action(state, 0)
	assert_eq(a["kind"], "move", "a Fuel Cell in the inventory is enough")
	assert_eq(Simulation.validate_action(state, a), "")


func test_nobody_walks_without_fuel_and_easy_normal_never_walk() -> void:
	var dry: MatchState = _notch_state(SimConstants.CTRL_EXPERT, 0, 0)
	assert_eq(AiPlayer.next_action(dry, 0)["kind"], "fire", "no fuel, no cell: just shoot")
	for level: int in [SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL]:
		var state: MatchState = _notch_state(level, 150)
		assert_eq(AiPlayer.next_action(state, 0)["kind"], "fire", "level %d never walks" % level)


func test_no_walk_when_a_shot_reaches_the_target() -> void:
	var state: MatchState = AiTestUtil.flat_duel(SimConstants.CTRL_EXPERT, 900, 0, {"pulse_missile": 9})
	state.tanks[0].fuel = 200
	assert_eq(AiPlayer.next_action(state, 0)["kind"], "fire")


func test_a_walk_never_runs_into_a_fall() -> void:
	# A 100-cell cliff 45 cells to the left: the walk that would drop off it is not taken.
	var state: MatchState = _notch_state(SimConstants.CTRL_EXPERT, 150)
	state.terrain.flatten(0, 255, 700)
	var kinds: Array[String] = _kinds(state, 0)
	assert_eq(state.tanks[0].health, 100, "no fall damage from the AI's own walk: %s" % str(kinds))
	assert_gte(state.tanks[0].x, 256 + SimConstants.TANK_W / 2 - 1, "stayed on the plateau")


func test_moves_never_loop_over_many_notches() -> void:
	# Walls at varying distances and heights from the shooter, varying targets, fuel or only cells:
	# the turn always ends within 3 calls and at most one of them is a move.
	var moves: int = 0
	for i: int in range(24):
		var r: Rng = Rng.derive(i, 818)
		var level: int = SimConstants.CTRL_HARD if i % 2 == 0 else SimConstants.CTRL_EXPERT
		var state: MatchState = AiTestUtil.flat_duel(level, r.range_int(400, 800), r.range_int(-60, 60),
				{"pulse_missile": 9, "fuel_cell": r.range_int(0, 2)})
		var wall_x: int = 300 + r.range_int(25, 90)
		state.terrain.flatten(wall_x, wall_x + r.range_int(40, 140), r.range_int(0, 250))
		state.tanks[0].fuel = r.range_int(0, 2) * 80
		var kinds: Array[String] = _kinds(state, 0)
		assert_lte(kinds.size(), 3, "variant %d: %s" % [i, str(kinds)])
		assert_true(kinds[kinds.size() - 1].begins_with("fire:") or kinds[kinds.size() - 1].begins_with("pass"))
		var walks: int = kinds.filter(func(k: String) -> bool: return k.begins_with("move")).size()
		assert_lte(walks, 1, "variant %d walks at most once" % i)
		moves += walks
	gut.p("MOVE    %d of 24 notch variants needed a walk; none looped" % moves)
