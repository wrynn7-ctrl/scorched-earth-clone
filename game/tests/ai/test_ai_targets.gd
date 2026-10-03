extends GutTest
## Target choice per difficulty (docs/ARCHITECTURE.md section 29).

const SHOOTER: int = 0


func _ffa(level: int, n: int = 4) -> MatchState:
	# Tanks at x = 300, 633, 966, 1300 (n = 4); the shooter is tank 0.
	return AiTestUtil.flat_ffa(level, n)


func _pick(state: MatchState, level: int) -> int:
	return AiTargets.pick(state, state.tanks[SHOOTER], level).id


func _shot_at_me(state: MatchState, shooter_id: int, turn: int) -> void:
	var t: TankState = state.tanks[shooter_id]
	t.last_fire_weapon = Catalog.index_of("pulse_missile")
	t.last_fire_x = state.tanks[SHOOTER].x + 20
	t.last_fire_y = state.tanks[SHOOTER].y - 3
	t.last_fire_turn = turn
	t.last_fire_power = 500
	t.last_fire_angle = 450


func test_easy_shoots_the_nearest_tank() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_EASY)
	assert_eq(_pick(state, SimConstants.CTRL_EASY), 1)
	state.tanks[2].x = 400
	assert_eq(_pick(state, SimConstants.CTRL_EASY), 2)
	state.tanks[1].health = 5
	assert_eq(_pick(state, SimConstants.CTRL_EASY), 2, "health is irrelevant to Easy")
	state.tanks[2].alive = false
	assert_eq(_pick(state, SimConstants.CTRL_EASY), 1, "dead tanks are not targets")


func test_normal_goes_for_revenge_on_whoever_just_shot_at_it() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_NORMAL)
	assert_eq(_pick(state, SimConstants.CTRL_NORMAL), 1, "nearest by default")
	state.turn_number = 5
	_shot_at_me(state, 3, 4)
	assert_eq(_pick(state, SimConstants.CTRL_NORMAL), 3, "tank 3 just shot at me")
	_shot_at_me(state, 2, 5)
	assert_eq(_pick(state, SimConstants.CTRL_NORMAL), 2, "the most recent shooter wins")
	state.turn_number = 40
	assert_eq(_pick(state, SimConstants.CTRL_NORMAL), 1, "an old grudge is forgotten")
	var far_shot: MatchState = _ffa(SimConstants.CTRL_NORMAL)
	far_shot.turn_number = 5
	_shot_at_me(far_shot, 3, 4)
	far_shot.tanks[3].last_fire_x = 1000  # landed nowhere near me
	assert_eq(_pick(far_shot, SimConstants.CTRL_NORMAL), 1, "a shot that missed me by a mile is no provocation")


func test_hard_finishes_the_weakest() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_HARD)
	state.tanks[2].health = 30
	state.tanks[3].health = 60
	assert_eq(_pick(state, SimConstants.CTRL_HARD), 2)
	state.tanks[2].shield_type = Catalog.index_of("ion_shield")
	state.tanks[2].shield_hp = 60
	assert_eq(_pick(state, SimConstants.CTRL_HARD), 3, "a shield counts as health")
	state.tanks[1].health = 60
	assert_eq(_pick(state, SimConstants.CTRL_HARD), 1, "ties go to the nearer tank")


func test_expert_takes_the_best_payoff() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_EXPERT)
	# Same health everywhere: the near, dangerous one.
	assert_eq(_pick(state, SimConstants.CTRL_EXPERT), 1)
	# A tank it can kill with one shot is worth the kill bonus, even if it is farther.
	state.tanks[3].health = 40
	assert_eq(_pick(state, SimConstants.CTRL_EXPERT), 3, "a sure kill")
	# But not if a shield soaks the damage: shields pay nothing.
	state.tanks[3].shield_type = Catalog.index_of("ion_shield")
	state.tanks[3].shield_hp = 60
	assert_ne(_pick(state, SimConstants.CTRL_EXPERT), 3, "shielded target pays nothing")


func test_expert_prefers_somebody_who_is_shooting_at_it_and_keeps_its_target() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_EXPERT)
	state.tanks[1].x = 700
	state.tanks[2].x = 600
	state.turn_number = 3
	_shot_at_me(state, 1, 2)
	assert_eq(_pick(state, SimConstants.CTRL_EXPERT), 1, "threat counts")
	var cont: MatchState = _ffa(SimConstants.CTRL_EXPERT)
	var me: TankState = cont.tanks[SHOOTER]
	me.last_fire_weapon = Catalog.index_of("pulse_missile")
	me.last_fire_x = cont.tanks[2].x - 30
	me.last_fire_y = cont.tanks[2].y
	me.last_fire_turn = 0
	cont.tanks[1].x = cont.tanks[2].x - 20
	cont.turn_number = 2
	assert_true(_pick(cont, SimConstants.CTRL_EXPERT) in [1, 2])


func test_teammates_are_never_targets() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_EXPERT)
	state.tanks[1].team = state.tanks[0].team
	for level: int in [1, 2, 3, 4]:
		assert_ne(_pick(state, level), 1, "level %d spares its teammate" % level)
	state.tanks[2].alive = false
	state.tanks[3].alive = false
	assert_null(AiTargets.pick(state, state.tanks[0], SimConstants.CTRL_EASY), "nobody left to shoot")


func test_best_damage_follows_the_rack() -> void:
	var state: MatchState = _ffa(SimConstants.CTRL_EXPERT)
	var me: TankState = state.tanks[0]
	me.set_stock("pulse_missile", 0)
	assert_eq(AiTargets.best_damage(me), 30, "only the Spark Dart")
	me.set_stock("pulse_missile", 1)
	assert_eq(AiTargets.best_damage(me), 55)
	me.set_stock("nova_core", 1)
	assert_eq(AiTargets.best_damage(me), 100)
