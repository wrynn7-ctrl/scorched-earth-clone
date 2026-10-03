extends GutTest
## Computer players shop instantly through the normal action path, and the shop flow shows
## hand-over screens only between two different humans.

const H: int = SimConstants.CTRL_HUMAN
const EASY: int = SimConstants.CTRL_EASY
const NORMAL: int = SimConstants.CTRL_NORMAL
const HARD: int = SimConstants.CTRL_HARD
const EXPERT: int = SimConstants.CTRL_EXPERT

var _state: MatchState = null
var _log: Array[Dictionary] = []


func after_each() -> void:
	UiScale.reset_overrides()
	ShowSettings.reset()
	PlayerLooks.reset()


func _new_state(controllers: Array, money: int = 10000) -> MatchState:
	var m := MatchSettings.new()
	m.num_tanks = controllers.size()
	m.rounds = 3
	m.seed = 4711
	m.start_money = money
	m.controllers = PackedInt32Array(controllers)
	_state = Simulation.new_match(m)
	_log.clear()
	return _state


## What the battle controller does: validate, log, apply.
func _submit(action: Dictionary) -> String:
	var a: Dictionary = Simulation.normalize_action(action)
	var err: String = Simulation.validate_action(_state, a)
	if err == "":
		_log.append(a)
		Simulation.apply_action(_state, a)
	return err


func _flow() -> ShopFlow:
	var f := ShopFlow.new()
	add_child_autofree(f)
	return f


## Records which player every hand-over screen was shown for.
func _watch_handovers(f: ShopFlow, shown: Array[int]) -> void:
	f.get_handover().visibility_changed.connect(func() -> void:
		if f.get_handover().visible:
			shown.append(f.get_handover().get_player()))


func test_cpu_shop_applies_buys_and_readies_without_a_handover() -> void:
	_new_state([H, NORMAL])
	var f: ShopFlow = _flow()
	var shown: Array[int] = []
	_watch_handovers(f, shown)
	watch_signals(f)
	f.open(_state, _submit)
	await wait_process_frames(2)
	assert_true(_state.tanks[1].ready, "the CPU readied itself")
	assert_false(_state.tanks[0].ready, "the human did not")
	var cpu_actions: Array[Dictionary] = _log.filter(func(a: Dictionary) -> bool: return a["tank"] == 1)
	assert_gt(cpu_actions.size(), 1, "it bought something and then readied")
	assert_eq(cpu_actions.back(), {"kind": "ready", "tank": 1}, "ready comes last")
	assert_lt(_state.tanks[1].money, 10000, "it spent money")
	for a: Dictionary in cpu_actions:
		assert_true(["buy", "sell", "ready"].has(a["kind"]))
	# Same actions the AI would give on the original state: it is the AI's plan, validated normally.
	var fresh: MatchState = _new_state([H, NORMAL])
	var plan: Array[Dictionary] = AiPlayer.shop_actions(fresh, 1)
	assert_eq(cpu_actions.size(), plan.size())
	for i: int in range(plan.size()):
		assert_eq(cpu_actions[i], Simulation.normalize_action(plan[i]))
	# The human is alone: straight into their shop, no hand-over screen.
	assert_eq(shown, [] as Array[int])
	assert_false(f.is_showing_handover())
	assert_true(f.is_showing_shop())
	assert_eq(f.get_screen().get_player(), 0)
	assert_eq(f.get_cpu_purchases().size(), 1)
	assert_eq(f.get_cpu_purchases()[0]["tank"], 1)
	assert_eq(f.get_cpu_purchases()[0]["level"], NORMAL)


func test_purchases_are_reported_in_units() -> void:
	_new_state([H, EXPERT])
	var f: ShopFlow = _flow()
	f.open(_state, _submit)
	var bought: Dictionary = {}
	for a: Dictionary in _log:
		if a["kind"] == "buy":
			var bundle: int = Catalog.get_def(a["item"] as String)["bundle"]
			bought[a["item"]] = (bought.get(a["item"], 0) as int) + (a["qty"] as int) * bundle
	var reported: Dictionary = {}
	for it: Dictionary in f.get_cpu_purchases()[0]["items"] as Array[Dictionary]:
		reported[it["id"]] = it["units"]
	assert_eq(reported, bought, "units (bundles x bundle size) per item")
	assert_gt(bought.size(), 0)
	var text: String = CpuShop.describe(f.get_cpu_purchases()[0]["items"] as Array[Dictionary])
	assert_string_contains(text, "×")
	assert_eq(CpuShop.describe([] as Array[Dictionary]), "nothing")


func test_one_human_and_three_cpus_never_see_a_handover() -> void:
	_new_state([H, EASY, NORMAL, HARD])
	var f: ShopFlow = _flow()
	var shown: Array[int] = []
	_watch_handovers(f, shown)
	watch_signals(f)
	f.open(_state, _submit)
	await wait_process_frames(2)
	assert_true(f.is_showing_shop(), "the lone human's shop opens directly")
	assert_false(f.is_showing_handover())
	for id: int in [1, 2, 3]:
		assert_true(_state.tanks[id].ready, "CPU %d is ready" % id)
	assert_signal_not_emitted(f, "all_ready")
	f.get_screen().ready_pressed.emit()
	assert_signal_emitted(f, "all_ready")
	assert_true(Simulation.all_ready(_state))
	assert_eq(shown, [] as Array[int], "no hand-over at any point")
	assert_false(f.is_showing_handover())


func test_a_lone_human_gets_no_handover_in_the_later_shops_either() -> void:
	# After round 1 the same flow opens again for the next shop.
	_new_state([EASY, H, NORMAL])
	var f: ShopFlow = _flow()
	var shown: Array[int] = []
	_watch_handovers(f, shown)
	f.open(_state, _submit)
	assert_true(f.is_showing_shop())
	assert_eq(f.get_screen().get_player(), 1, "the human is player 2")
	f.get_screen().ready_pressed.emit()
	assert_eq(Simulation.start_round(_state).is_empty(), false)
	# Round over, shop again: the CPUs shop first once more.
	for t: TankState in _state.tanks:
		t.health = 100
	_state.phase = SimConstants.PHASE_SHOP
	for t: TankState in _state.tanks:
		t.ready = false
	f.open(_state, _submit)
	assert_true(_state.tanks[0].ready and _state.tanks[2].ready)
	assert_true(f.is_showing_shop())
	assert_eq(shown, [] as Array[int])


func test_two_humans_and_a_cpu_see_hand_overs_only_between_the_humans() -> void:
	_new_state([H, H, NORMAL])
	var f: ShopFlow = _flow()
	var shown: Array[int] = []
	_watch_handovers(f, shown)
	watch_signals(f)
	f.open(_state, _submit)
	await wait_process_frames(2)
	assert_true(_state.tanks[2].ready, "the CPU shopped on its own")
	assert_true(f.is_showing_handover())
	assert_eq(f.get_handover().get_title_text(), "PLAYER 1 — YOUR SHOP")
	assert_false(f.is_showing_shop())
	f.get_handover().get_tap_button().pressed.emit()
	assert_true(f.is_showing_shop())
	assert_eq(f.get_screen().get_player(), 0)
	f.get_screen().ready_pressed.emit()
	assert_true(f.is_showing_handover(), "player 2 is another human: hand over")
	assert_eq(f.get_handover().get_title_text(), "PLAYER 2 — YOUR SHOP")
	f.get_handover().get_tap_button().pressed.emit()
	assert_eq(f.get_screen().get_player(), 1)
	f.get_screen().ready_pressed.emit()
	assert_signal_emitted(f, "all_ready")
	assert_eq(shown, [0, 1] as Array[int], "hand-overs for the humans only, never for the CPU (player 3)")


func test_a_cpu_between_two_humans_is_skipped() -> void:
	_new_state([H, NORMAL, H])
	var f: ShopFlow = _flow()
	var shown: Array[int] = []
	_watch_handovers(f, shown)
	f.open(_state, _submit)
	f.get_handover().get_tap_button().pressed.emit()
	f.get_screen().ready_pressed.emit()
	assert_eq(f.get_handover().get_player(), 2, "straight from player 1 to player 3")
	assert_eq(shown, [0, 2] as Array[int])


func test_all_cpu_shop_closes_by_itself() -> void:
	_new_state([NORMAL, HARD])
	var f: ShopFlow = _flow()
	watch_signals(f)
	f.open(_state, _submit)
	assert_signal_emitted(f, "all_ready")
	assert_true(Simulation.all_ready(_state))
	assert_false(f.is_showing_handover())
	assert_false(f.is_showing_shop())
	assert_eq(f.get_cpu_purchases().size(), 2)


func test_a_ready_cpu_does_not_shop_twice() -> void:
	_new_state([H, NORMAL])
	var f: ShopFlow = _flow()
	f.open(_state, _submit)
	var after_first: int = _log.size()
	var money: int = _state.tanks[1].money
	f.open(_state, _submit)
	assert_eq(_log.size(), after_first, "nothing new was logged")
	assert_eq(_state.tanks[1].money, money)
	assert_eq(f.get_cpu_purchases().size(), 0, "and nothing was bought this time")


func test_rejected_cpu_actions_are_skipped_and_the_cpu_is_still_readied() -> void:
	_new_state([H, NORMAL])
	var f: ShopFlow = _flow()
	var refuse_buys: Callable = func(action: Dictionary) -> String:
		if action["kind"] == "buy":
			return "no_money"
		return _submit(action)
	f.open(_state, refuse_buys)
	assert_true(_state.tanks[1].ready, "a CPU is never left unready")
	assert_eq(f.get_cpu_purchases()[0]["items"], [] as Array[Dictionary], "nothing counted as bought")
	assert_eq(_state.tanks[1].money, 10000)


func test_controller_levels_and_helpers() -> void:
	_new_state([H, EASY, NORMAL, HARD, EXPERT])
	assert_eq(CpuShop.human_count(_state), 1)
	assert_false(CpuShop.needs_handover(_state))
	assert_false(CpuShop.is_cpu(_state, 0))
	assert_true(CpuShop.is_cpu(_state, 4))
	assert_eq(CpuShop.level_of(_state, 3), HARD)
	assert_eq(CpuShop.level_of(_state, 99), H, "out of range counts as human")
	_new_state([H, H])
	assert_true(CpuShop.needs_handover(_state))
	_new_state([NORMAL, NORMAL])
	assert_eq(CpuShop.human_count(_state), 0)
	assert_false(CpuShop.needs_handover(_state))
