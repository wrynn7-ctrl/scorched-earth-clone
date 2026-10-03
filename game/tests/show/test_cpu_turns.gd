extends GutTest
## Computer opponents in the battle: the turn banner and input lock, the AI's action through the
## normal path, shield-then-fire, the invalid-action fallback, a watch-only match, autosave in
## the middle of a CPU turn, and the CPU turn speed.

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const PATH: String = "user://test_cpu_autosave.crtl"
const SEED: int = 777

const H: int = SimConstants.CTRL_HUMAN
const EASY: int = SimConstants.CTRL_EASY
const NORMAL: int = SimConstants.CTRL_NORMAL
const HARD: int = SimConstants.CTRL_HARD
const EXPERT: int = SimConstants.CTRL_EXPERT


func before_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()


func after_each() -> void:
	SaveStore.delete(PATH)
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()
	get_tree().paused = false


## A battle with the given controllers. `ready` starts the round (the humans "press READY").
func _battle(controllers: Array, instant: bool = true, rounds: int = 3, ready: bool = true) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(rounds, SEED, instant, controllers.size())
	c.set_controllers(PackedInt32Array(controllers))
	add_child_autofree(c)
	if ready and c.get_state().phase == SimConstants.PHASE_SHOP:
		assert_true(c.quick_start())  # (with no human at all the round has started already)
	return c


## A deep copy of the authoritative state, so the AI can be asked without touching the match.
func _copy(c: BattleController) -> MatchState:
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(c.get_state(), c.get_session().actions))
	assert_true(res["ok"], str(res["error"]))
	return res["state"] as MatchState


## Advances the controller by `seconds` of frames (calls _process with a fixed step).
func _pump(c: BattleController, seconds: float, step: float = 1.0 / 30.0) -> void:
	var t: float = 0.0
	while t < seconds:
		c._process(step)
		t += step


## Plays the round-start timeline (non-instant controllers) so the CPU's turn is waiting to be
## decided. No awaits: the engine's own frames must not advance the CPU behind the test's back.
func _settle(c: BattleController) -> void:
	var n: int = 0
	while c._playing and n < 600:
		c._process(1.0 / 30.0)
		n += 1
	assert_eq(c.get_cpu_driver().stage, CpuDriver.Stage.COMPUTE, "the CPU turn is waiting for its first frame")


## Hurts tank `id` in the state and refreshes the views (a test shortcut, not a game path).
func _wound(c: BattleController, id: int, health: int) -> void:
	c.get_state().tanks[id].health = health
	c._rebuild_display()


## Simulated seconds until the CPU's next action is logged; -1 when it never comes.
func _seconds_until_action(c: BattleController, limit: float = 8.0) -> float:
	var before: int = c.get_session().actions.size()
	var t: float = 0.0
	while t < limit:
		c._process(1.0 / 30.0)
		t += 1.0 / 30.0
		if c.get_session().actions.size() > before:
			return t
	return -1.0


# --- the turn presentation ------------------------------------------------------------------

func test_cpu_turn_shows_the_cpu_banner_thinking_line_and_locks_input() -> void:
	var c: BattleController = _battle([NORMAL, H, EASY])
	var hud: BattleHud = c.get_hud()
	assert_eq(c.get_state().current_tank, 0)
	assert_true(c.is_cpu_turn_active())
	assert_eq(hud.get_turn_banner().get_text(), "CPU NORMAL — PLAYER 1")
	assert_true(hud.get_turn_banner().is_thinking())
	assert_eq(hud.get_turn_banner().get_thinking_text(), "thinking…")
	assert_true(hud.is_controls_locked(), "the aim surface is locked")
	assert_true(c.is_busy())
	# Every human input path refuses.
	assert_eq(c.fire_current(), "busy")
	assert_eq(c.move_current(1), "busy")
	assert_eq(c.use_item("glow_shield"), "busy")
	assert_eq(c.pass_turn(), "busy")
	assert_eq(c.select_weapon("pulse_missile"), "busy")
	var before: Vector2i = c.get_aim(0)
	c.set_aim(100, 100)
	assert_eq(c.get_aim(0), before, "aim changes are ignored")
	assert_eq(c.get_session().actions.back()["kind"], "ready", "nothing was fired by the human inputs")
	# The CPU plays; the human's turn is the plain banner with no thinking line.
	c.drive_cpu(3)
	assert_eq(c.get_state().current_tank, 1)
	assert_false(c.is_cpu_turn_active())
	assert_eq(hud.get_turn_banner().get_text(), "PLAYER 2'S TURN")
	assert_false(hud.get_turn_banner().is_thinking())
	assert_false(hud.is_controls_locked())
	assert_false(c.is_busy())
	assert_eq(c.fire_current(), "", "the human can fire now")
	# And the next one is CPU Easy.
	assert_eq(c.get_state().current_tank, 2)
	assert_eq(hud.get_turn_banner().get_text(), "CPU EASY — PLAYER 3")
	assert_true(c.is_cpu_turn_active())


func test_cpu_turn_takes_the_players_colour() -> void:
	var c: BattleController = _battle([H, EXPERT])
	c.fire_current()
	assert_eq(c.get_state().current_tank, 1)
	assert_eq(c.get_hud().get_turn_banner().get_text(), "CPU EXPERT — PLAYER 2")
	var label: Label = c.get_hud().get_turn_banner().find_child("Text", true, false)
	assert_eq(label.get_theme_color("font_color"), PlayerLooks.color(1), "the player's own colour")


func test_the_turret_and_power_sweep_to_the_chosen_aim() -> void:
	var c: BattleController = _battle([EASY, H], false)
	_settle(c)
	var expected: Dictionary = AiPlayer.next_action(_copy(c), 0)
	assert_eq(expected["kind"], "fire", "Easy never prepares: it fires straight away")
	var from: Vector2i = c.get_aim(0)
	# Advance by hand: one frame to decide, then through the pause into the sweep.
	c._process(0.0)
	assert_eq(c.get_cpu_driver().stage, CpuDriver.Stage.COMPUTE, "the first frame is only the yield")
	c._process(0.0)
	assert_eq(c.get_cpu_driver().stage, CpuDriver.Stage.THINK)
	assert_eq(c.get_cpu_driver().action, expected, "the pending action is the AI's")
	assert_eq(c.get_selected_weapon(), expected["weapon"], "the weapon button shows the CPU's weapon")
	var think: float = CpuDriver.think_seconds(c.get_state(), 0, 1)
	assert_between(think, 0.5, 1.2, "think pause")
	c._process(think * 0.5)
	assert_eq(c.get_cpu_driver().stage, CpuDriver.Stage.THINK, "still thinking")
	assert_eq(c.get_aim(0), from, "the turret waits while it thinks")
	c._process(think * 0.5 + 0.01)
	assert_eq(c.get_cpu_driver().stage, CpuDriver.Stage.SWEEP)
	var sweep: float = c.get_cpu_driver().duration
	assert_between(sweep, 0.6, 1.0, "sweep length")
	c._process(sweep * 0.5)
	var mid: Vector2i = c.get_aim(0)
	var want := Vector2i(expected["angle"] as int, expected["power"] as int)
	assert_gt(absi(want.x - from.x) + absi(want.y - from.y), 20, "this scenario has something to sweep")
	if absi(want.x - from.x) > 20:
		assert_ne(mid.x, from.x, "the turret has started to move")
		assert_ne(mid.x, want.x, "and has not arrived")
		assert_eq(mid.x, roundi(lerpf(float(from.x), float(want.x), 0.5)), "halfway at half time (eased)")
	assert_eq(c.get_tank_view(0).get_angle_tenths(), mid.x, "the turret view follows")
	assert_eq(c.get_hud().get_angle_tenths(), mid.x, "so does the angle readout")
	assert_eq(c.get_hud().get_power(), mid.y, "and the power readout")
	assert_eq(c.get_session().actions.back()["kind"], "ready", "still not fired")
	assert_true(c.get_hud().get_turn_banner().is_thinking(), "still thinking while it aims")
	c._process(sweep)
	assert_eq(c.get_session().actions.back()["kind"], "fire", "fired at the end of the sweep")
	assert_eq(c.get_aim(0), want)
	assert_false(c.get_hud().get_turn_banner().is_thinking(), "no more thinking once it fires")


# --- the action goes through the normal path -------------------------------------------------

func test_cpu_action_is_exactly_what_the_ai_decides() -> void:
	for level: int in [EASY, NORMAL, HARD, EXPERT]:
		var c: BattleController = _battle([level, H])
		var expected: Dictionary = AiPlayer.next_action(_copy(c), 0)
		var logged: int = c.get_session().actions.size()
		assert_eq(c.drive_cpu(1), 1)
		var got: Dictionary = c.get_session().actions[logged]
		assert_eq(got, Simulation.normalize_action(expected), "level %d: the logged action is the AI's" % level)
		if expected["kind"] == "fire":
			assert_eq(c.get_state().tanks[0].last_fire_angle, expected["angle"], "the simulation fired it")
			assert_eq(c.get_state().tanks[0].last_fire_power, expected["power"])
		assert_eq(c.cpu_fallbacks, 0)
		c.queue_free()


func test_a_cpu_with_a_shield_uses_it_and_then_fires() -> void:
	var c: BattleController = _battle([NORMAL, H])
	var t: TankState = c.get_state().tanks[0]
	t.set_stock("glow_shield", 1)
	for id: String in ["ion_shield", "fortress_field"]:
		t.set_stock(id, 0)
	_wound(c, 0, 30)  # Normal raises a shield when hurt
	var logged: int = c.get_session().actions.size()
	var spent: int = c.drive_cpu(3)
	assert_lte(spent, 3, "a turn-ending action within 3 calls")
	assert_gte(spent, 2)
	var log: Array[Dictionary] = c.get_session().actions.slice(logged)
	assert_eq(log[0]["kind"], "use_item", "the shield first")
	assert_eq(log[0]["item"], "glow_shield")
	assert_eq(log[log.size() - 1]["kind"], "fire", "then the shot")
	assert_eq(log.size(), spent)
	assert_eq(c.get_tank_view(0).get_shield_hp(), c.get_state().tanks[0].shield_hp, "the bubble shows what the state says")
	assert_eq(c.get_state().current_tank, 1, "the turn passed on after the shot")
	assert_eq(c.cpu_fallbacks, 0)


func test_a_non_ending_action_asks_the_ai_again_in_real_time_too() -> void:
	var c: BattleController = _battle([NORMAL, H], false)
	_settle(c)
	var tank: TankState = c.get_state().tanks[0]
	for id: String in ["ion_shield", "fortress_field"]:
		tank.set_stock(id, 0)
	tank.set_stock("glow_shield", 1)
	_wound(c, 0, 30)
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_INSTANT
	var kinds: Array[String] = []
	var guard: int = 0
	while c.get_state().current_tank == 0 and guard < 900:
		guard += 1
		var n: int = c.get_session().actions.size()
		c._process(1.0 / 30.0)
		if c.get_session().actions.size() > n:
			kinds.append(c.get_session().actions.back()["kind"] as String)
	assert_eq(kinds, ["use_item", "fire"] as Array[String], "shield, then fire")
	assert_eq(c.get_state().current_tank, 1)


# --- never soft-lock -------------------------------------------------------------------------

func test_an_invalid_ai_action_becomes_a_pass_and_the_game_goes_on() -> void:
	var c: BattleController = _battle([EASY, H])
	watch_signals(c)
	c.cpu_action_override = func(_state: MatchState, id: int) -> Dictionary:
		return {"kind": "fire", "tank": id, "angle": 99999, "power": 500, "weapon": "spark_dart"}
	var logged: int = c.get_session().actions.size()
	assert_eq(c.drive_cpu(1), 1)
	assert_eq(c.get_session().actions[logged], {"kind": "pass", "tank": 0}, "fell back to a pass")
	assert_eq(c.cpu_fallbacks, 1)
	assert_signal_emitted(c, "cpu_fallback")
	assert_eq(c.get_state().current_tank, 1, "the game continues with the next player")
	assert_false(c.is_busy())
	assert_eq(c.fire_current(), "", "the human is not locked out")
	# Garbage of every kind is survived.
	var c2: BattleController = _battle([EASY, H])
	for bad: Dictionary in [{}, {"kind": "banana"}, {"kind": "fire"}, {"kind": "fire", "tank": 1, "angle": 450, "power": 500, "weapon": "spark_dart"}]:
		var answer: Dictionary = bad
		c2.cpu_action_override = func(_s: MatchState, _id: int) -> Dictionary: return answer
		var before: int = c2.cpu_fallbacks
		c2.drive_cpu(1)
		assert_eq(c2.cpu_fallbacks, before + 1, "fallback for %s" % str(bad))
		assert_eq(c2.get_session().actions.back()["kind"], "pass")
		c2.fire_current()  # the human's turn
		assert_eq(c2.get_state().current_tank, 0, "round-robin is back at the CPU")
		assert_true(c2.is_cpu_turn_active())


func test_an_ai_that_never_ends_its_turn_is_cut_off() -> void:
	var c: BattleController = _battle([HARD, H])
	c.get_state().tanks[0].set_stock("glow_shield", 9)
	c.cpu_action_override = func(_s: MatchState, id: int) -> Dictionary:
		return {"kind": "use_item", "tank": id, "item": "glow_shield"}
	var logged: int = c.get_session().actions.size()
	var spent: int = c.drive_cpu(10)
	assert_eq(spent, CpuDriver.MAX_CALLS, "three shields, then the fourth answer becomes a pass")
	var log: Array[Dictionary] = c.get_session().actions.slice(logged)
	assert_eq(log.back(), {"kind": "pass", "tank": 0})
	assert_eq(c.cpu_fallbacks, 1)
	assert_eq(c.get_state().current_tank, 1)


# --- a match with nobody at the controls ------------------------------------------------------

func test_a_watch_match_runs_to_match_over_in_instant_mode() -> void:
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_INSTANT
	var c: BattleController = _battle([NORMAL, HARD, EXPERT], true, 2, false)
	# No human: the shop opens and closes by itself, the round starts without anyone pressing READY.
	assert_false(c.get_shop().is_showing_handover())
	assert_false(c.get_shop().is_showing_shop())
	assert_eq(c.get_state().phase, SimConstants.PHASE_AIM, "round 1 is already running")
	var summaries: int = 0
	var guard: int = 0
	while c.get_state().phase != SimConstants.PHASE_MATCH_OVER and guard < 800:
		guard += 1
		if c.get_round_overlay().visible:
			summaries += 1
			if summaries == 1:
				_check_summary_lines(c)
			c.next_round()
		else:
			c.drive_cpu(8)
	assert_eq(c.get_state().phase, SimConstants.PHASE_MATCH_OVER, "ran to the end (%d loops)" % guard)
	assert_true(c.get_match_overlay().visible, "the standings are shown")
	assert_eq(summaries, 1, "a summary after round 1; the last round goes straight to the standings")
	assert_eq(c.cpu_fallbacks, 0, "the AI never needed the fallback")
	assert_eq(c.mismatch_count, 0, "playback matched the simulation")
	for a: Dictionary in c.get_session().actions:
		assert_true(["ready", "buy", "sell", "fire", "move", "use_item", "pass"].has(a["kind"]))


func _check_summary_lines(c: BattleController) -> void:
	var lines: PackedStringArray = c.get_round_overlay().get_cpu_lines()
	assert_eq(lines.size(), 3, "one purchases line per CPU")
	assert_string_contains(lines[0], "PLAYER 1 (CPU NORMAL) — Bought: ")
	assert_string_contains(lines[1], "PLAYER 2 (CPU HARD) — Bought: ")
	assert_string_contains(lines[2], "PLAYER 3 (CPU EXPERT) — Bought: ")
	assert_eq(c.get_cpu_purchases().size(), 3)


func test_the_summary_lists_what_the_cpus_bought() -> void:
	var c: BattleController = _battle([H, NORMAL, EXPERT], true, 3, false)
	var buys: Array[Dictionary] = c.get_cpu_purchases()
	assert_eq(buys.size(), 2, "the two CPUs shopped when the match opened")
	assert_eq([buys[0]["tank"], buys[1]["tank"]], [1, 2])
	for b: Dictionary in buys:
		assert_true(c.get_state().tanks[b["tank"] as int].ready, "and are ready")
		for it: Dictionary in b["items"] as Array[Dictionary]:
			assert_gt(c.get_state().tanks[b["tank"] as int].stock_of(it["id"] as String), 0, "what they bought is in stock")
	var overlay: RoundEndOverlay = c.get_round_overlay()
	var rows: Array[Dictionary] = [{"id": 0, "earned": 0, "kills": 0, "wins": 0}, {"id": 1, "earned": 0, "kills": 0, "wins": 0},
			{"id": 2, "earned": 0, "kills": 0, "wins": 0}]
	var fake: Array[Dictionary] = [{"tank": 2, "level": NORMAL, "items": [{"id": "pulse_missile", "units": 5}, {"id": "glow_shield", "units": 1}] as Array[Dictionary]}]
	overlay.show_summary(0, rows, 1, 3, fake)
	assert_eq(overlay.get_cpu_lines(), PackedStringArray(["PLAYER 3 (CPU NORMAL) — Bought: Pulse Missile ×5, Glow Shield"]))
	var none: Array[Dictionary] = [{"tank": 1, "level": EASY, "items": [] as Array[Dictionary]}]
	overlay.show_summary(0, rows, 1, 3, none)
	assert_eq(overlay.get_cpu_lines(), PackedStringArray(["PLAYER 2 (CPU EASY) — Bought: nothing"]))
	overlay.show_summary(0, rows, 1, 3)
	assert_eq(overlay.get_cpu_lines().size(), 0, "no CPUs: no lines")
	assert_false(overlay.get_cpu_scroll().visible)


# --- autosave and continue in the middle of a CPU turn ----------------------------------------

func test_autosave_mid_cpu_turn_then_continue_gives_the_same_action() -> void:
	var c: BattleController = _battle([H, HARD, NORMAL], true, 3, true)
	c.set_autosave_path(PATH)
	c.fire_current()  # the human; now it is CPU Hard's turn
	assert_eq(c.get_state().current_tank, 1)
	assert_true(c.is_cpu_turn_active())
	assert_true(c.autosave_now(), "saved while the CPU is thinking")
	var expected: Dictionary = Simulation.normalize_action(AiPlayer.next_action(_copy(c), 1))
	# Continue: a new controller restores the file; the CPU decides again from the state.
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var d: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(d)
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(c.get_state()), "restored the same state")
	assert_true(d.is_cpu_turn_active(), "and the CPU is on its turn again")
	assert_eq(d.get_hud().get_turn_banner().get_text(), "CPU HARD — PLAYER 2")
	assert_true(d.is_busy())
	var logged: int = d.get_session().actions.size()
	assert_eq(d.drive_cpu(1), 1)
	assert_eq(d.get_session().actions[logged], expected, "the same action as before the save")
	# The original controller makes the same decision (same state, same action).
	c.drive_cpu(1)
	assert_eq(c.get_session().actions.back(), expected)
	assert_eq(Simulation.fingerprint(d.get_state()), Simulation.fingerprint(c.get_state()), "and the same resulting state")


func test_cpu_purchases_survive_a_save_on_the_summary_screen() -> void:
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_INSTANT
	var c: BattleController = _battle([NORMAL, EXPERT], true, 3, false)
	c.set_autosave_path(PATH)
	var guard: int = 0
	while not c.get_round_overlay().visible and guard < 400:
		guard += 1
		c.drive_cpu(8)
	assert_true(c.get_round_overlay().visible, "round 1 ended")
	var lines: PackedStringArray = c.get_round_overlay().get_cpu_lines()
	assert_eq(lines.size(), 2)
	assert_true(c.autosave_now())
	BattleConfig.autosave_path = PATH
	BattleConfig.resume = true
	BattleConfig.instant = true
	var d: BattleController = (load(BATTLE) as PackedScene).instantiate()
	add_child_autofree(d)
	assert_true(d.get_round_overlay().visible, "the summary is back")
	assert_eq(d.get_round_overlay().get_cpu_lines(), lines, "with the same purchases")


# --- the CPU turn speed ---------------------------------------------------------------------

func test_cpu_speed_setting_scales_the_wait_helpers() -> void:
	assert_eq(ShowSettings.cpu_speed_scale(), 1.0)
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_FAST
	assert_almost_eq(ShowSettings.cpu_speed_scale(), 0.35, 0.0001)
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_INSTANT
	assert_eq(ShowSettings.cpu_speed_scale(), 0.0)
	ShowSettings.cpu_turn_speed = 99
	assert_eq(ShowSettings.cpu_speed_scale(), 0.0, "out of range clamps to the last level")
	assert_eq(CpuDriver.wait_scale(1.0, 1.0, false), 1.0)
	assert_eq(CpuDriver.wait_scale(1.0, 2.0, false), 0.5, "the 2x toggle halves the waits")
	assert_almost_eq(CpuDriver.wait_scale(0.35, 2.0, false), 0.175, 0.0001, "Fast and 2x multiply")
	assert_eq(CpuDriver.wait_scale(1.0, 1.0, true), 0.0, "instant (tests) never waits")


func test_pauses_are_seeded_by_the_turn_so_they_repeat() -> void:
	var c: BattleController = _battle([EASY, EASY])
	var s: MatchState = c.get_state()
	var a: float = CpuDriver.think_seconds(s, 0, 1)
	assert_eq(CpuDriver.think_seconds(s, 0, 1), a, "the same turn gives the same pause")
	assert_eq(CpuDriver.sweep_seconds(s, 0), CpuDriver.sweep_seconds(s, 0))
	var seen: Dictionary = {}
	for turn: int in range(20):
		s.turn_number = turn
		seen[snappedf(CpuDriver.think_seconds(s, 0, 1), 0.01)] = true
		assert_between(CpuDriver.think_seconds(s, 0, 1), 0.5, 1.2)
		assert_between(CpuDriver.sweep_seconds(s, 0), 0.6, 1.0)
	assert_gt(seen.size(), 8, "and they vary from turn to turn")
	assert_lt(CpuDriver.think_seconds(s, 0, 2), 1.2 * CpuDriver.FOLLOW_UP + 0.001, "a follow-up in the same turn is quicker")


func test_normal_fast_and_instant_turn_lengths() -> void:
	var seconds: Dictionary = {}
	for mode: int in [ShowSettings.CPU_SPEED_NORMAL, ShowSettings.CPU_SPEED_FAST, ShowSettings.CPU_SPEED_INSTANT]:
		ShowSettings.cpu_turn_speed = mode
		var c: BattleController = _battle([EASY, H], false)
		_settle(c)
		seconds[mode] = _seconds_until_action(c)
	var normal: float = seconds[ShowSettings.CPU_SPEED_NORMAL]
	var fast: float = seconds[ShowSettings.CPU_SPEED_FAST]
	var instant: float = seconds[ShowSettings.CPU_SPEED_INSTANT]
	assert_between(normal, 1.1, 2.4, "think 0.5-1.2 s plus sweep 0.6-1.0 s")
	assert_between(fast, 0.35 * 1.1 - 0.1, 0.35 * 2.2 + 0.2, "Fast is about a third of that")
	assert_lt(fast, normal)
	assert_lte(instant, 0.12, "Instant: one frame to decide, then it acts")
	# The 1x/2x toggle shortens it as well.
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_NORMAL
	var c2: BattleController = _battle([EASY, H], false)
	_settle(c2)
	c2.set_speed(2.0)
	var doubled: float = _seconds_until_action(c2)
	assert_between(doubled, 0.55 - 0.1, 1.2 + 0.1, "2x halves the pauses")
	assert_lt(doubled, normal)
	ShowSettings.playback_speed = 1.0
