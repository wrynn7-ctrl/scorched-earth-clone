extends GutTest
## Credits, damage pipeline and standings (docs/ARCHITECTURE.md section 18, 21).

const U = preload("res://tests/core/sim_test_util.gd")


func _dmg(s: MatchState, attacker: int, target: int, amount: int, cause: String = "explosion") -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	Simulation.apply_damage(s, attacker, target, amount, cause, 5, ev)
	return ev


func test_damage_credit_uses_actual_hp_removed() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].money = 0
	var ev: Array[Dictionary] = _dmg(s, 0, 1, 30)
	assert_eq(s.tanks[1].health, 70)
	assert_eq(s.tanks[0].money, 450, "30 HP * 15")
	assert_eq(s.tanks[0].damage_dealt, 30)
	assert_eq(U.types(ev), ["damage", "money"] as Array[String], "money right after the damage")
	assert_eq(ev[1], {"type": "money", "tick": 5, "tank": 0, "delta": 450, "money": 450, "reason": "damage"})
	assert_eq(ev[0], {"type": "damage", "tick": 5, "tank": 1, "amount": 30, "health": 70, "cause": "explosion"})


func test_overkill_pays_only_the_remaining_hp() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].money = 0
	s.tanks[1].health = 10
	var ev: Array[Dictionary] = _dmg(s, 0, 1, 80)
	assert_eq(s.tanks[1].health, 0)
	assert_false(s.tanks[1].alive)
	assert_eq(s.tanks[0].damage_dealt, 10)
	assert_eq(s.tanks[0].money, 10 * 15 + 1500, "10 HP credit + kill bonus; never 80 * 15")
	assert_eq(U.types(ev), ["damage", "money", "money"] as Array[String])
	assert_eq(ev[0]["amount"], 80, "the damage event keeps the nominal amount")
	assert_eq(ev[1]["reason"], "damage")
	assert_eq(ev[1]["delta"], 150)
	assert_eq(ev[2]["reason"], "kill")
	assert_eq(ev[2]["delta"], 1500)
	assert_eq(s.tanks[0].kills, 1)


func test_kill_bonus_only_for_the_killing_blow() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[0].money = 0
	s.tanks[1].health = 50
	_dmg(s, 0, 1, 30)
	assert_eq(s.tanks[0].kills, 0)
	_dmg(s, 0, 1, 30)
	assert_eq(s.tanks[0].kills, 1)
	assert_eq(s.tanks[0].money, 50 * 15 + 1500)


func test_hitting_a_dead_tank_does_nothing() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var ev: Array[Dictionary] = _dmg(s, 0, 1, 40)
	assert_eq(ev.size(), 0)
	assert_eq(s.tanks[0].money, 0)
	assert_eq(s.tanks[0].damage_dealt, 0)


func test_zero_and_negative_damage_do_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	assert_eq(_dmg(s, 0, 1, 0).size(), 0)
	assert_eq(_dmg(s, 0, 1, -5).size(), 0)
	assert_eq(s.tanks[1].health, 100)


func test_self_damage_costs_money_and_never_goes_below_zero() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].money = 1000
	var ev: Array[Dictionary] = _dmg(s, 0, 0, 20)
	assert_eq(s.tanks[0].money, 700, "20 HP * -15")
	assert_eq(ev[1], {"type": "money", "tick": 5, "tank": 0, "delta": -300, "money": 700, "reason": "self_damage"})
	assert_eq(s.tanks[0].damage_dealt, 0, "self damage is not damage dealt")
	assert_eq(s.tanks[0].kills, 0)
	var ev2: Array[Dictionary] = _dmg(s, 0, 0, 40)  # penalty 600 leaves 100... then 0
	assert_eq(s.tanks[0].money, 100)
	var ev3: Array[Dictionary] = _dmg(s, 0, 0, 20)  # penalty 300 > 100
	assert_eq(s.tanks[0].money, 0, "floored at 0")
	assert_eq(ev3[1]["delta"], -100, "the event reports the delta actually applied")
	assert_eq(ev3[1]["money"], 0)
	s.tanks[0].health = 100
	var ev4: Array[Dictionary] = _dmg(s, 0, 0, 10)
	assert_eq(U.types(ev4), ["damage"] as Array[String], "no money event when nothing changes")
	assert_eq(s.tanks[0].money, 0)
	assert_eq(ev2.size(), 2)


func test_suicide_pays_no_kill_bonus() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].money = 5000
	s.tanks[0].health = 10
	_dmg(s, 0, 0, 99)
	assert_false(s.tanks[0].alive)
	assert_eq(s.tanks[0].kills, 0)
	assert_eq(s.tanks[0].money, 5000 - 150, "only the penalty for the 10 HP removed")


func test_teammate_damage_is_penalised_like_self_damage() -> void:
	var s: MatchState = U.flat_state(3)
	s.tanks[1].team = 0
	s.tanks[0].money = 1000
	_dmg(s, 0, 1, 20)
	assert_eq(s.tanks[0].money, 700)
	assert_eq(s.tanks[0].damage_dealt, 0)
	s.tanks[1].health = 5
	_dmg(s, 0, 1, 20)
	assert_eq(s.tanks[0].kills, 0, "no bonus for a teammate")


func test_unattributed_damage_pays_nothing() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _dmg(s, -1, 1, 20)
	assert_eq(U.types(ev), ["damage"] as Array[String])
	assert_eq(s.tanks[0].money, 0)
	assert_eq(s.tanks[1].health, 80)
	var ev2: Array[Dictionary] = _dmg(s, 7, 1, 20)  # out-of-range attacker is treated as nobody
	assert_eq(U.types(ev2), ["damage"] as Array[String])


func test_shield_absorption_pays_nothing_for_the_absorbed_part() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	_dmg(s, 0, 1, 20)
	assert_eq(s.tanks[0].money, 0, "fully absorbed: no health removed")
	assert_eq(s.tanks[0].damage_dealt, 0)
	_dmg(s, 0, 1, 25)  # 10 absorbed, 15 to health
	assert_eq(s.tanks[1].health, 85)
	assert_eq(s.tanks[0].money, 15 * 15)
	assert_eq(s.tanks[0].damage_dealt, 15)


func test_fall_damage_is_attributed_to_the_given_attacker() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = _dmg(s, 0, 1, 10, "fall")
	assert_eq(s.tanks[0].money, 150)
	assert_eq(ev[0]["cause"], "fall")


func test_fire_timeline_credits_the_shooter() -> void:
	var s: MatchState = U.flat_state(2)
	var p: int = U.power_for_target(s, 450, s.tanks[1].x)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	var hp_removed: int = 100 - s.tanks[1].health
	assert_gt(hp_removed, 0)
	assert_eq(s.tanks[0].money, hp_removed * 15 + (1500 if not s.tanks[1].alive else 0))
	assert_eq(s.tanks[0].damage_dealt, hp_removed)
	var money_events: Array[Dictionary] = U.find(ev, "money")
	assert_gt(money_events.size(), 0)
	for m: Dictionary in money_events:
		assert_true(["damage", "kill", "self_damage", "survive", "win"].has(m["reason"]))


func test_kill_in_a_fire_timeline_pays_kill_survive_and_win() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[1].health = 1
	var p: int = U.power_for_target(s, 450, s.tanks[1].x)
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.fire(0, 450, p))
	assert_false(s.tanks[1].alive)
	var reasons: Array[String] = []
	var types: Array[String] = U.types(ev)
	for m: Dictionary in U.find(ev, "money"):
		reasons.append(m["reason"])
	assert_eq(reasons, ["damage", "kill", "survive", "win"] as Array[String])
	assert_eq(s.tanks[0].money, 15 + 1500 + 1000 + 2500)
	assert_eq(s.tanks[0].kills, 1)
	assert_eq(s.tanks[0].round_wins, 1)
	# order: ... damage, money(damage), money(kill) ... tank_destroyed, round_end, money(survive), money(win)
	var round_end_at: int = types.find("round_end")
	assert_eq(types.slice(round_end_at), ["round_end", "money", "money"] as Array[String])
	assert_true(types.find("tank_destroyed") < round_end_at)


func test_survive_and_win_pay_at_round_end() -> void:
	var s: MatchState = U.flat_state(3)
	for t: TankState in s.tanks:
		t.money = 100
	U.kill_all_but(s, 0)
	s.tanks[1].alive = false
	# tank 1 and 2 dead, tank 0 alone: pass ends the round
	var ev: Array[Dictionary] = Simulation.apply_action(s, U.pass_turn(0))
	var re: int = U.types(ev).find("round_end")
	assert_gt(re, -1)
	assert_eq(ev[re]["winner"], 0)
	var pays: Array[Dictionary] = U.find(ev, "money")
	assert_eq(pays.size(), 2)
	assert_eq([pays[0]["tank"], pays[0]["delta"], pays[0]["reason"]], [0, 1000, "survive"])
	assert_eq([pays[1]["tank"], pays[1]["delta"], pays[1]["reason"]], [0, 2500, "win"])
	assert_eq(s.tanks[0].money, 100 + 3500)
	assert_eq(s.tanks[1].money, 100, "the dead are not paid")
	assert_eq(s.tanks[0].round_wins, 1)
	assert_eq(s.tanks[1].round_wins, 0)


func test_draw_pays_nobody() -> void:
	var s: MatchState = U.flat_state(2)
	s.tanks[0].alive = false
	s.tanks[0].health = 0
	s.tanks[1].alive = false
	s.tanks[1].health = 0
	var ev: Array[Dictionary] = []
	Economy.pay_round(s, -1, 0, ev)
	assert_eq(ev.size(), 0)
	assert_eq(s.tanks[0].round_wins + s.tanks[1].round_wins, 0)


func test_survivor_who_did_not_win_still_gets_survive_pay() -> void:
	# Defensive: pay_round with a winner of -1 and one alive tank still pays survive only.
	var s: MatchState = U.flat_state(3)
	s.tanks[1].alive = false
	s.tanks[2].alive = false
	var ev: Array[Dictionary] = []
	Economy.pay_round(s, -1, 3, ev)
	assert_eq(U.types(ev), ["money"] as Array[String])
	assert_eq(ev[0]["reason"], "survive")
	assert_eq(ev[0]["tick"], 3)


func test_add_money_floor_and_zero_events() -> void:
	var s: MatchState = U.flat_state(2)
	var ev: Array[Dictionary] = []
	assert_eq(Economy.add_money(s, 0, 0, "damage", 0, ev), 0)
	assert_eq(Economy.add_money(s, 0, -50, "self_damage", 0, ev), 0, "nothing to lose")
	assert_eq(ev.size(), 0)
	assert_eq(Economy.add_money(s, 0, 80, "damage", 0, ev), 80)
	assert_eq(Economy.add_money(s, 0, -200, "self_damage", 0, ev), -80)
	assert_eq(s.tanks[0].money, 0)
	assert_eq(ev.size(), 2)


func test_helpers() -> void:
	assert_eq(Economy.damage_credit(10), 150)
	assert_eq(Economy.damage_credit(0), 0)
	assert_eq(Economy.damage_credit(-5), 0)
	assert_eq(Economy.self_damage_penalty(4), 60)
	var def: Dictionary = WeaponDefs.get_def("pulse_missile")
	assert_eq(Economy.buy_cost(def, 3), 4500)
	assert_eq(Economy.buy_units(def, 3), 15)
	assert_eq(Economy.sell_refund(def, 0, 5), 0)
	assert_eq(Economy.sell_refund(def, 5, 0), 0)
	assert_eq(Economy.sell_refund(def, 10, 5), 750, "capped at owned")


# --- standings -----------------------------------------------------------------------

func _stats(wins: Array[int], dmg: Array[int], kills: Array[int]) -> MatchState:
	var s: MatchState = U.flat_state(wins.size())
	for i: int in range(wins.size()):
		s.tanks[i].round_wins = wins[i]
		s.tanks[i].damage_dealt = dmg[i]
		s.tanks[i].kills = kills[i]
	return s


func test_standings_order_by_wins() -> void:
	var s: MatchState = _stats([1, 3, 2], [999, 0, 0], [9, 0, 0])
	assert_eq(Simulation.standings(s), [1, 2, 0] as Array[int])


func test_standings_tie_break_damage_then_kills_then_id() -> void:
	var s: MatchState = _stats([2, 2, 2, 2], [10, 50, 50, 50], [0, 1, 3, 3])
	assert_eq(Simulation.standings(s), [2, 3, 1, 0] as Array[int], "wins tie -> damage -> kills -> lower id")
	var all_tied: MatchState = _stats([0, 0, 0], [0, 0, 0], [0, 0, 0])
	assert_eq(Simulation.standings(all_tied), [0, 1, 2] as Array[int])


func test_standings_is_pure_and_covers_every_tank() -> void:
	var s: MatchState = _stats([0, 5, 0, 1, 1, 0, 2, 2], [1, 1, 1, 1, 9, 1, 1, 1], [0, 0, 0, 0, 0, 0, 0, 5])
	var before: String = Simulation.fingerprint(s)
	var order: Array[int] = Simulation.standings(s)
	assert_eq(order, [1, 7, 6, 4, 3, 0, 2, 5] as Array[int])
	assert_eq(Simulation.fingerprint(s), before)
	var sorted: Array[int] = order.duplicate()
	sorted.sort()
	assert_eq(sorted, [0, 1, 2, 3, 4, 5, 6, 7] as Array[int])
