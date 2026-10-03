extends GutTest
## Self-damage and friendly-fire guard, the critical-health repair rule, the lost-shot bracket and
## the exact (sub-step) AiFlight terrain check.


func _flat(xs: Array[int], level: int, stock: Dictionary) -> MatchState:
	var state: MatchState = SimTestUtil.flat_state(xs.size())
	var ctrl := PackedInt32Array()
	for i: int in range(xs.size()):
		state.tanks[i].x = xs[i]
		state.tanks[i].set_stock("pulse_missile", 0)
		ctrl.append(level if i == 0 else SimConstants.CTRL_HUMAN)
	state.settings.controllers = ctrl
	state.settings.num_tanks = xs.size()
	for id: String in stock.keys():
		state.tanks[0].set_stock(id, stock[id])
	return state


func _damage_to(events: Array[Dictionary], tank: int) -> int:
	var total: int = 0
	for e: Dictionary in events:
		if e["type"] == "damage" and (e["tank"] as int) == tank:
			total += e["amount"] as int
	return total


func test_no_level_hurts_itself_at_point_blank_range() -> void:
	var cases: int = 0
	var passes: int = 0
	for level: int in [1, 2, 3, 4]:
		for d: int in range(26, 100, 8):
			var state: MatchState = _flat([300, 300 + d], level, {"nova_core": 5, "hyperpulse": 5})
			var turn: Dictionary = AiTestUtil.play_turn(state, 0)
			cases += 1
			if turn["action"]["kind"] == "pass":
				passes += 1
			assert_eq(_damage_to(turn["events"], 0), 0, "level %d at %d cells took self damage" % [level, d])
	gut.p("SAFETY  point blank (%d shots, 26-90 cells, Nova+Hyperpulse in stock): no self damage; %d passes" % [cases, passes])


func test_harm_estimate_follows_blast_radius_and_distance() -> void:
	var near: MatchState = _flat([300, 345], 4, {"nova_core": 1})
	var me: TankState = near.tanks[0]
	var sit: AiSituation = AiPlayer.situation(near, me, 4, AiProfile.for_level(4), AiTargets.enemies_of(near, me))
	var plan: Dictionary = AiWeapons.plan_for(sit, "nova_core")
	var nova: Dictionary = AiWeapons.estimate_harm(sit, plan, "nova_core")
	assert_gt(nova["self"], 30, "a Nova 21 cells from the enemy box is a big self hit")
	assert_gt(nova["enemy"], 0)
	var far: MatchState = _flat([300, 700], 4, {"nova_core": 1})
	var sit2: AiSituation = AiPlayer.situation(far, far.tanks[0], 4, AiProfile.for_level(4), AiTargets.enemies_of(far, far.tanks[0]))
	var nova_far: Dictionary = AiWeapons.estimate_harm(sit2, AiWeapons.plan_for(sit2, "nova_core"), "nova_core")
	assert_eq(nova_far["self"], 0, "at 400 cells the Nova is safe")
	assert_gt(nova_far["enemy"], 50)


func test_the_cpu_does_not_splash_a_teammate() -> void:
	for level: int in [1, 2, 3, 4]:
		var state: MatchState = _flat([300, 1000, 1030], level, {"nova_core": 3, "hyperpulse": 3})
		state.tanks[1].team = 0
		var turn: Dictionary = AiTestUtil.play_turn(state, 0)
		assert_eq(_damage_to(turn["events"], 1), 0, "level %d: the teammate was not hurt" % level)


func test_in_a_crowd_a_cpu_only_hurts_itself_when_the_trade_is_good() -> void:
	# Six tanks 30 cells apart: every blast reaches somebody next door. A CPU may still take a
	# self-hit when it hurts the enemies by more than 1.5x as much (and never kills itself).
	var xs: Array[int] = []
	for i: int in range(6):
		xs.append(700 + 30 * i)
	var state: MatchState = _flat(xs, 4, {})
	for t: TankState in state.tanks:
		t.set_stock("nova_core", 2)
		t.set_stock("hyperpulse", 3)
	state.settings.controllers = PackedInt32Array([4, 3, 4, 3, 2, 4])
	var suicides: int = 0
	var turns: int = 0
	for _i: int in range(10):
		if state.phase != SimConstants.PHASE_AIM:
			break
		var id: int = state.current_tank
		var before: int = state.tanks[id].health
		var turn: Dictionary = AiTestUtil.play_turn(state, id)
		turns += 1
		var self_dmg: int = _damage_to(turn["events"], id)
		var enemy_dmg: int = 0
		for e: Dictionary in turn["events"]:
			if e["type"] == "damage" and (e["tank"] as int) != id:
				enemy_dmg += e["amount"] as int
		if self_dmg > 0:
			assert_gt(enemy_dmg * 2, self_dmg * 3, "tank %d: %d self vs %d enemy damage" % [id, self_dmg, enemy_dmg])
		if before > 0 and state.tanks[id].health <= 0:
			suicides += 1
	assert_gt(turns, 3)
	assert_eq(suicides, 0, "nobody destroyed itself")


func test_critical_health_means_repair_for_hard_and_expert() -> void:
	for level: int in [3, 4]:
		var state: MatchState = _flat([300, 1000], level, {"pulse_missile": 5, "nanorepair_kit": 1})
		state.tanks[0].health = 20
		state.tanks[1].health = 30  # a kill is possible, but only if the shot lands
		assert_eq(AiPlayer.next_action(state, 0)["item"], "nanorepair_kit", "level %d heals at 20 HP" % level)
	var lance: MatchState = _flat([300, 700], 4, {"photon_lance": 1, "nanorepair_kit": 1})
	lance.tanks[0].health = 10
	lance.tanks[1].health = 30
	var a: Dictionary = AiPlayer.next_action(lance, 0)
	assert_eq(a["kind"], "fire", "a clear Photon Lance shot at the last enemy is a certain kill: fire")
	var bracketed: MatchState = _flat([300, 420], 4, {"pulse_missile": 5, "nanorepair_kit": 1})
	bracketed.tanks[0].health = 10
	bracketed.tanks[1].health = 30
	var me: TankState = bracketed.tanks[0]
	me.last_fire_weapon = Catalog.index_of("pulse_missile")
	me.last_fire_x = 410
	me.last_fire_y = me.y
	me.last_fire_angle = 450
	me.last_fire_power = 300
	me.last_fire_turn = 0
	bracketed.turn_number = 1
	assert_eq(AiPlayer.next_action(bracketed, 0)["kind"], "fire", "close range, already bracketed: finish it")
	var two: MatchState = _flat([300, 420, 1000], 4, {"pulse_missile": 5, "nanorepair_kit": 1})
	two.tanks[0].health = 10
	two.tanks[1].health = 30
	two.tanks[2].health = 30
	two.tanks[0].last_fire_weapon = Catalog.index_of("pulse_missile")
	two.tanks[0].last_fire_x = 410
	two.tanks[0].last_fire_y = two.tanks[0].y
	two.tanks[0].last_fire_turn = 0
	two.turn_number = 1
	assert_eq(AiPlayer.next_action(two, 0)["kind"], "use_item", "two enemies left: no single shot ends the round")


func test_a_lost_shell_still_brackets_the_next_shot() -> void:
	# A biased tank whose shell flew off the map used to repeat the same shot for ever.
	var state: MatchState = AiTestUtil.duel(11, SimConstants.CTRL_EASY, 800, 0)
	var me: TankState = state.tanks[0]
	me.last_fire_weapon = Catalog.index_of("pulse_missile")
	me.last_fire_x = -1
	me.last_fire_y = -1
	me.last_fire_angle = 450 if state.tanks[1].x > me.x else 1350
	me.last_fire_power = 1000
	me.last_fire_turn = 0
	state.turn_number = 1
	var sit: AiSituation = AiPlayer.situation(state, me, 1, AiProfile.for_level(1), AiTargets.enemies_of(state, me))
	assert_false(sit.corr.is_empty(), "a lost shot still gives a correction base")
	var action: Dictionary = AiPlayer.finalize(sit, AiWeapons.choose_and_plan(sit))
	assert_lt(action["power"], 1000, "less power than the lost shell had")


func test_flight_model_sees_a_thin_pillar_and_terrain_high_in_the_sky() -> void:
	var state: MatchState = AiTestUtil.flat_duel(4, 700, 0, {"pulse_missile": 5})
	state.terrain.flatten(600, 603, 150)  # a thin tower, 450 cells tall
	var me: TankState = state.tanks[0]
	var agree: int = 0
	for p: int in range(300, 700, 25):
		var tr: Dictionary = Ballistics.trace(state, 0, 500, p, "pulse_missile", 0, 420)
		var flight := AiFlight.new(state.terrain)
		flight.fly_shot(me.x, me.y, 500, p, 0, 420)
		if absi(flight.r_x - (tr["end_x"] as int)) <= 2 and (tr["end_reason"] != "terrain" or flight.r_reason == AiFlight.REASON_TERRAIN):
			agree += 1
	assert_eq(agree, 16, "the model agrees with the real trace for every power")
	var high := AiFlight.new(state.terrain)
	assert_eq(high.peak_row(), 150, "the real highest terrain row, not a fixed sky line")
	state.terrain.flatten(900, 940, 20)
	assert_eq(AiFlight.new(state.terrain).peak_row(), 20)
