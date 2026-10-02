@warning_ignore_start("integer_division")
extends GutTest
## Economy invariants (docs/ARCHITECTURE.md section 18) re-derived independently of the
## simulation and checked after EVERY action of many shopping-bot matches: money never
## negative, per-tank money events sum to the money change, damage credits = 15 x HP actually
## removed, kills / damage_dealt match the events, round pay exactly per section 18, inventory
## within 0..99, spark_dart never stored, standings obey the tie-breaks.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const MATCHES: int = 20
const ROOT_SEED: int = 0xEC0000


func _settings(m: int) -> MatchSettings:
	var rng := Rng.new(ROOT_SEED + m * 13)
	var s := MatchSettings.new()
	s.seed = rng.next_u32()
	s.num_tanks = rng.range_int(2, 8) if m % 4 != 0 else 2
	s.rounds = rng.range_int(1, 3)
	s.wind_max = [100, 100, 40, 0][m % 4]
	s.start_money = [6000, 10000, 25000, 400, 100000][m % 5]
	s.full_unlocked = m % 7 != 3
	return s


func test_books_balance_after_every_action_of_bot_matches() -> void:
	var t0: int = Time.get_ticks_msec()
	var failures: Array[String] = []
	var actions: int = 0
	var round_ends: int = 0
	var winners: int = 0
	var draws: int = 0
	var kills: int = 0
	var fall_credits: int = 0
	var self_hits: int = 0
	var overkills: int = 0
	var shield_only: int = 0
	var clamped: int = 0
	for m: int in range(MATCHES):
		var settings: MatchSettings = _settings(m)
		var tag: String = "match %d (seed %d, %d tanks, %d rounds, money %d)" % [m, settings.seed, settings.num_tanks,
				settings.rounds, settings.start_money]
		var state: MatchState = Simulation.new_match(settings)
		var bot := Rng.new(ROOT_SEED + m)
		var total_delta: Array[int] = []
		for t: TankState in state.tanks:
			total_delta.append(0)
		var in_round: int = 0
		for step: int in range(2000):
			var action: Dictionary = M3.next_action(state, bot)
			if action.is_empty():
				break
			if M3.AIM_KINDS.has(action["kind"]):
				in_round += 1
				if in_round > 70:
					break
			var snap: Dictionary = M3.snapshot(state)
			var ev: Array[Dictionary] = M3.apply(state, action)
			actions += 1
			var errs: Array[String] = M3.audit(snap, state, action, ev)
			errs.append_array(M3.check_state(state))
			if action["kind"] != M3.START_ROUND:
				errs.append_array(M3.check_timeline(action, ev))
			if not errs.is_empty():
				failures.append("%s step %d %s:\n  %s" % [tag, step, str(action), "\n  ".join(errs.slice(0, 6))])
				break
			for e: Dictionary in ev:
				if e["type"] == "money":
					total_delta[e["tank"]] += e["delta"]
				elif e["type"] == "round_end":
					round_ends += 1
					if e["winner"] >= 0:
						winners += 1
					else:
						draws += 1
			for i: int in range(ev.size()):
				var e2: Dictionary = ev[i]
				if e2["type"] == "money" and e2["reason"] == "kill":
					kills += 1
				if e2["type"] == "money" and e2["reason"] == "self_damage":
					self_hits += 1
					if (e2["money"] as int) == 0:
						clamped += 1
				if e2["type"] == "damage" and e2["cause"] == "fall" and i + 1 < ev.size() and ev[i + 1]["type"] == "money":
					fall_credits += 1
				if e2["type"] == "shield_hit" and (i + 1 >= ev.size() or ev[i + 1]["type"] != "damage") \
						and (i + 2 >= ev.size() or ev[i + 2]["type"] != "damage"):
					shield_only += 1
				if e2["type"] == "damage" and (e2["health"] as int) == 0 and (e2["amount"] as int) > 0 and i > 0:
					overkills += 1
		# Whole-match conservation: money = start + every money event the tank ever received.
		for t: TankState in state.tanks:
			if t.money != settings.clamped().start_money + total_delta[t.id]:
				failures.append("%s: tank %d final money %d != start %d + events %d" % [tag, t.id, t.money,
						settings.clamped().start_money, total_delta[t.id]])
		if failures.size() > 4:
			break
	var ms: int = Time.get_ticks_msec() - t0
	gut.p("ECONOMY: %d matches, %d audited actions, %d round_ends (%d won, %d draws), %d kills, %d fall credits, %d self hits (%d clamped at 0), %d shield-only hits in %d ms" % [
			MATCHES, actions, round_ends, winners, draws, kills, fall_credits, self_hits, clamped, shield_only, ms])
	assert_eq(failures.size(), 0, "economy audit failures:\n%s" % "\n".join(failures))
	assert_gt(actions, 1100, "plenty of audited actions")
	assert_gt(round_ends, 12, "plenty of round ends")
	assert_gt(kills, 5, "kills were exercised")
	assert_gt(self_hits, 3, "self damage was exercised")
	assert_gt(shield_only, 0, "shield-absorbed hits were exercised")
	assert_lt(ms, 70000, "stays within its time budget")


# --- hand-built scenarios ------------------------------------------------------------------------

func _duel(hp0: int, hp1: int, money: int = 5000) -> MatchState:
	var s: MatchState = QaUtil.flat_state([300, 700] as Array[int])
	s.tanks[0].health = hp0
	s.tanks[1].health = hp1
	for t: TankState in s.tanks:
		t.money = money
	return s


## A shot straight at a tank: the explosion lands at the tank's box, with hp removal known.
func _fire(state: MatchState, weapon: String, angle: int, power: int) -> Array[Dictionary]:
	var t: TankState = state.tanks[state.current_tank]
	t.set_stock(weapon, maxi(1, t.stock_of(weapon)))
	return Simulation.apply_action(state, {"kind": "fire", "tank": t.id, "angle": angle, "power": power, "weapon": weapon})


func _blast_at(state: MatchState, x: int, y: int, radius: int, dmg: int) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	WeaponResolver.blast(state, 0, x, y, radius, dmg, "pulse_missile", 0, ev)
	return ev


func test_credit_is_for_hp_actually_removed_not_the_nominal_amount() -> void:
	var s: MatchState = _duel(100, 7)
	var ev: Array[Dictionary] = _blast_at(s, 700, 599, 60, 100)  # point blank: nominal damage far above 7
	var dmg: Array[Dictionary] = QaUtil.find(ev, "damage").filter(func(e: Dictionary) -> bool: return e["tank"] == 1)
	assert_eq(dmg.size(), 1)
	assert_gt(dmg[0]["amount"], 7, "nominal damage exceeds the remaining health")
	var money: Array[Dictionary] = QaUtil.find(ev, "money").filter(func(e: Dictionary) -> bool: return e["tank"] == 0 and e["reason"] != "self_damage")
	assert_eq(money[0]["reason"], "damage")
	assert_eq(money[0]["delta"], 7 * 15, "15 credits per HP that was actually there")
	assert_eq(money[1]["reason"], "kill")
	assert_eq(money[1]["delta"], 1500)
	assert_eq(s.tanks[0].damage_dealt, 7)
	assert_eq(s.tanks[0].kills, 1)


func test_shield_absorbed_damage_earns_nothing_and_only_the_remainder_pays() -> void:
	# Blast 43 cells above tank 1 (r 60, 150 max damage): the crater is shallow and does not drop the
	# tank (rest_y is the highest surface under its width), so there is no fall damage to muddy the sums.
	var s: MatchState = _duel(100, 100)
	s.tanks[1].shield_type = Catalog.index_of("glow_shield")
	s.tanks[1].shield_hp = 30
	var nominal: int = Damage.compute(s, 700, 545, 60, 150).filter(func(d: Dictionary) -> bool: return d["tank"] == 1)[0]["amount"]
	assert_gt(nominal, 30, "the hit is stronger than the shield")
	var before: int = s.tanks[0].money
	var ev: Array[Dictionary] = _blast_at(s, 700, 545, 60, 150)
	var hit: Array[Dictionary] = QaUtil.find(ev, "shield_hit")
	assert_eq(hit[0]["absorbed"], 30)
	assert_eq(QaUtil.find(ev, "shield_down").size(), 1)
	assert_eq(s.tanks[1].health, 100 - (nominal - 30))
	assert_eq(s.tanks[0].money, before + (nominal - 30) * 15, "credit for the HP that was removed only")
	assert_eq(s.tanks[0].damage_dealt, nominal - 30)
	# Fully absorbed: no damage event, no money event, no damage_dealt.
	var s2: MatchState = _duel(100, 100)
	s2.tanks[1].shield_type = Catalog.index_of("ion_shield")
	s2.tanks[1].shield_hp = 60
	var ev2: Array[Dictionary] = _blast_at(s2, 700, 545, 60, 100)
	assert_eq(QaUtil.find(ev2, "damage").size(), 0)
	assert_eq(QaUtil.find(ev2, "money").size(), 0)
	assert_eq(s2.tanks[0].money, 5000)
	assert_eq(s2.tanks[0].damage_dealt, 0)
	assert_lt(s2.tanks[1].shield_hp, 60)
	assert_gt(s2.tanks[1].shield_hp, 0)


func test_self_damage_costs_15_per_hp_and_never_goes_below_zero() -> void:
	var s: MatchState = _duel(100, 100, 100)  # only 100 credits
	var ev: Array[Dictionary] = _blast_at(s, 300, 545, 60, 100)  # above tank 0's own box
	var own: Array[Dictionary] = QaUtil.find(ev, "damage").filter(func(e: Dictionary) -> bool: return e["tank"] == 0)
	assert_eq(own.size(), 1)
	var removed: int = 100 - s.tanks[0].health
	assert_gt(removed * 15, 100, "the penalty would exceed the balance")
	assert_eq(s.tanks[0].money, 0, "clamped at zero")
	var pen: Array[Dictionary] = QaUtil.find(ev, "money").filter(func(e: Dictionary) -> bool: return e["tank"] == 0)
	assert_eq(pen.size(), 1)
	assert_eq(pen[0]["reason"], "self_damage")
	assert_eq(pen[0]["delta"], -100, "the event carries the delta actually applied")
	assert_eq(pen[0]["money"], 0)
	assert_eq(s.tanks[0].kills, 0)
	assert_eq(s.tanks[0].damage_dealt, 0, "hurting yourself is not damage dealt")
	# Plenty of money: exactly 15 per HP.
	var s3: MatchState = _duel(100, 100, 5000)
	_blast_at(s3, 300, 545, 60, 100)
	assert_eq(s3.tanks[0].money, 5000 - (100 - s3.tanks[0].health) * 15)
	# With zero money there is no event at all.
	var s2: MatchState = _duel(100, 100, 0)
	var ev2: Array[Dictionary] = _blast_at(s2, 300, 545, 60, 100)
	assert_eq(QaUtil.find(ev2, "money").size(), 0)
	assert_eq(s2.tanks[0].money, 0)


func test_suicide_kill_gives_no_kill_credit_and_costs_money() -> void:
	var s: MatchState = _duel(5, 100, 5000)
	var ev: Array[Dictionary] = _blast_at(s, 300, 595, 40, 60)
	assert_false(s.tanks[0].alive)
	assert_eq(s.tanks[0].kills, 0)
	for e: Dictionary in QaUtil.find(ev, "money"):
		assert_ne(e["reason"], "kill")
	assert_eq(s.tanks[0].money, 5000 - 5 * 15)


func test_round_pay_win_and_survivor_rules() -> void:
	# One blast kills tanks 1 and 2; tank 0 passes -> round_end(winner 0): the survivor is paid
	# survive then win, the dead are not paid.
	var s2: MatchState = QaUtil.flat_state([300, 340, 1000] as Array[int])
	s2.tanks[2].x = 380
	s2.tanks[1].health = 1
	s2.tanks[2].health = 1
	for t: TankState in s2.tanks:
		t.money = 2000
	var ev2: Array[Dictionary] = []
	WeaponResolver.blast(s2, 0, 360, 595, 40, 100, "pulse_missile", 0, ev2)
	assert_false(s2.tanks[1].alive)
	assert_false(s2.tanks[2].alive)
	var pass_ev: Array[Dictionary] = Simulation.apply_action(s2, {"kind": "pass", "tank": 0})
	assert_eq(QaUtil.types(pass_ev), ["round_end", "money", "money"] as Array[String])
	assert_eq(pass_ev[0]["winner"], 0)
	assert_eq([pass_ev[1]["tank"], pass_ev[1]["delta"], pass_ev[1]["reason"]], [0, 1000, "survive"])
	assert_eq([pass_ev[2]["tank"], pass_ev[2]["delta"], pass_ev[2]["reason"]], [0, 2500, "win"])
	assert_eq(s2.tanks[0].round_wins, 1)
	assert_eq(s2.tanks[1].round_wins + s2.tanks[2].round_wins, 0)
	assert_eq(s2.tanks[1].money, 2000, "dead tanks are not paid")
	assert_eq(s2.phase, SimConstants.PHASE_SHOP)


func test_draw_pays_nobody_and_counts_no_win() -> void:
	var s2: MatchState = QaUtil.flat_state([300, 340] as Array[int])
	s2.tanks[0].health = 1
	s2.tanks[1].health = 1
	s2.settings.rounds = 1
	for t: TankState in s2.tanks:
		t.money = 777
	# One simultaneous kill through the real fire path: the shell drops back on the shooter and
	# both tanks are inside the Supernova.
	s2.tanks[0].set_stock("supernova", 1)
	var ev2: Array[Dictionary] = Simulation.apply_action(s2, {"kind": "fire", "tank": 0, "angle": 900, "power": 1, "weapon": "supernova"})
	assert_eq(QaUtil.alive_count(s2), 0, "the last two tanks died together")
	var ends: Array[Dictionary] = QaUtil.find(ev2, "round_end")
	assert_eq(ends.size(), 1)
	assert_eq(ends[0]["winner"], -1)
	var pays: Array[Dictionary] = QaUtil.find(ev2, "money").filter(func(e: Dictionary) -> bool: return e["reason"] == "survive" or e["reason"] == "win")
	assert_eq(pays.size(), 0)
	assert_eq(s2.tanks[0].round_wins + s2.tanks[1].round_wins, 0)
	assert_eq(s2.phase, SimConstants.PHASE_MATCH_OVER, "a draw in the last round ends the match")
	assert_eq(ev2[ev2.size() - 1]["type"], "round_end", "nothing is paid after a draw")
	assert_eq(M3.check_standings(s2).size(), 0)


func test_match_over_after_last_round_and_shop_between() -> void:
	var settings: MatchSettings = QaUtil.settings(4, 2, 2)
	var state: MatchState = Simulation.new_match(settings)
	for r: int in range(2):
		M3.apply(state, {"kind": "ready", "tank": 0})
		M3.apply(state, {"kind": "ready", "tank": 1})
		assert_eq(M3.apply(state, {"kind": M3.START_ROUND}).size(), 3)
		state.tanks[1].health = 1
		state.tanks[state.current_tank].set_stock("nova_core", 1)
		var cur: int = state.current_tank
		# Shoot the other tank point blank: put the shooter's aim at it by a direct blast + pass.
		WeaponResolver.blast(state, cur, state.tanks[1 - cur].x, state.tanks[1 - cur].y - 5, 60, 100, "nova_core", 0, [] as Array[Dictionary])
		if state.tanks[cur].alive:
			Simulation.apply_action(state, {"kind": "pass", "tank": cur})
		else:
			Simulation.apply_action(state, {"kind": "pass", "tank": 1 - cur})
		var expect: String = SimConstants.PHASE_SHOP if r == 0 else SimConstants.PHASE_MATCH_OVER
		assert_eq(state.phase, expect, "after round %d" % r)
	assert_eq(Simulation.start_round(state).size(), 0, "no third round")


# --- standings -------------------------------------------------------------------------------------

func _tie_state(rows: Array) -> MatchState:
	var s := MatchState.new()
	for i: int in range(rows.size()):
		var t := TankState.new()
		t.id = i
		t.team = i
		t.round_wins = rows[i][0]
		t.damage_dealt = rows[i][1]
		t.kills = rows[i][2]
		s.tanks.append(t)
	return s


func test_standings_tiebreak_order_wins_then_damage_then_kills_then_lower_id() -> void:
	var s: MatchState = _tie_state([[1, 500, 0], [2, 100, 0], [1, 500, 2], [1, 900, 0], [2, 100, 0], [0, 9999, 9]])
	# wins desc: ids 1,4 (2 wins; tie on all -> lower id first), then 3 (900 dmg), then 2 (kills 2) before 0, then 5.
	assert_eq(Simulation.standings(s), [1, 4, 3, 2, 0, 5] as Array[int])
	var all_equal: MatchState = _tie_state([[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]])
	assert_eq(Simulation.standings(all_equal), [0, 1, 2, 3] as Array[int])


func test_standings_match_an_independent_sort_on_random_ties() -> void:
	var rng := Rng.new(0x57A0D)
	for round_i: int in range(600):
		var n: int = rng.range_int(2, 8)
		var rows: Array = []
		for _i: int in range(n):
			rows.append([rng.range_int(0, 2), rng.range_int(0, 2) * 50, rng.range_int(0, 2)])
		var s: MatchState = _tie_state(rows)
		var got: Array[int] = Simulation.standings(s)
		var keyed: Array = []
		for i: int in range(n):
			keyed.append([-rows[i][0], -rows[i][1], -rows[i][2], i])
		keyed.sort_custom(func(a: Array, b: Array) -> bool:
			for k: int in range(4):
				if a[k] != b[k]:
					return a[k] < b[k]
			return false)
		var want: Array[int] = []
		for k: Array in keyed:
			want.append(k[3])
		assert_eq(got, want, "round %d rows %s" % [round_i, str(rows)])
		assert_eq(M3.check_standings(s).size(), 0)
		if got != want:
			return


# --- shop arithmetic ----------------------------------------------------------------------------------

func test_buy_and_sell_arithmetic_for_every_catalog_entry() -> void:
	for id: String in Catalog.IDS:
		var def: Dictionary = Catalog.get_def(id)
		var s: MatchState = Simulation.new_match(QaUtil.settings(1, 2))
		s.tanks[0].money = 1_000_000
		if def.get("unlimited", false):
			assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": id, "qty": 1}), "not_buyable", id)
			assert_eq(Simulation.validate_action(s, {"kind": "sell", "tank": 0, "item": id, "qty": 1}), "out_of_stock", id)
			continue
		var price: int = def["price"]
		var bundle: int = def["bundle"]
		var qty: int = mini(3, SimConstants.INVENTORY_CAP / bundle)
		var ev: Array[Dictionary] = Simulation.apply_action(s, {"kind": "buy", "tank": 0, "item": id, "qty": qty})
		assert_eq(ev.size(), 1, "buy %s" % id)
		assert_eq(ev[0]["delta"], -price * qty, "buy %s cost" % id)
		assert_eq(s.tanks[0].stock_of(id), bundle * qty, "buy %s units" % id)
		assert_eq(s.tanks[0].money, 1_000_000 - price * qty)
		# Sell everything back one unit at a time: refunds follow price * units / bundle / 2 and never beat the cost.
		var refunded: int = 0
		var owned: int = bundle * qty
		for unit: int in range(owned):
			var sev: Array[Dictionary] = Simulation.apply_action(s, {"kind": "sell", "tank": 0, "item": id, "qty": 1})
			var want: int = price * 1 / bundle / 2
			if want == 0:
				assert_eq(sev.size(), 0, "a worthless refund emits no money event (%s)" % id)
			else:
				assert_eq(sev[0]["delta"], want, "sell %s unit %d" % [id, unit])
			refunded += want
		assert_eq(s.tanks[0].stock_of(id), 0)
		assert_lte(refunded, price * qty / 2, "selling back never profits (%s)" % id)
		assert_eq(s.tanks[0].money, 1_000_000 - price * qty + refunded)
		# Selling more than owned sells what is owned (here: nothing -> out_of_stock).
		assert_eq(Simulation.validate_action(s, {"kind": "sell", "tank": 0, "item": id, "qty": 5}), "out_of_stock")


func test_selling_more_than_owned_sells_only_what_is_owned() -> void:
	var s: MatchState = Simulation.new_match(QaUtil.settings(1, 2))
	Simulation.apply_action(s, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1})  # 5 units, 1500
	var before: int = s.tanks[0].money
	var ev: Array[Dictionary] = Simulation.apply_action(s, {"kind": "sell", "tank": 0, "item": "pulse_missile", "qty": 1000})
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 0)
	assert_eq(ev[0]["delta"], 1500 * 5 / 5 / 2, "refund for the 5 owned units, not for 1000")
	assert_eq(s.tanks[0].money, before + 750)


func test_inventory_cap_99_is_exact() -> void:
	var s: MatchState = Simulation.new_match(QaUtil.settings(1, 2))
	s.tanks[0].money = 1_000_000
	# fuel_cell has bundle 1: exactly 99 fit, the 100th is refused whole.
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 99}), "")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 100}), "inventory_full")
	Simulation.apply_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 99})
	assert_eq(s.tanks[0].stock_of("fuel_cell"), 99)
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "fuel_cell", "qty": 1}), "inventory_full")
	# bundle 5: 19 bundles = 95 units fit, 20 bundles = 100 is refused, and 95 + one more bundle (100) is refused.
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 20}), "inventory_full")
	Simulation.apply_action(s, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 19})
	assert_eq(s.tanks[0].stock_of("pulse_missile"), 95)
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}), "inventory_full")
	assert_eq(M3.check_state(s).size(), 0)
	# Huge quantities are rejected without overflow.
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 1, "item": "nova_core", "qty": 9223372036854775807}), "inventory_full")
	assert_eq(Simulation.validate_action(s, {"kind": "buy", "tank": 1, "item": "nova_core", "qty": 3037000500}), "inventory_full")
	assert_eq(Simulation.validate_action(s, {"kind": "sell", "tank": 0, "item": "fuel_cell", "qty": 9223372036854775807}), "")


# --- the auditor itself, and shop commutativity ----------------------------------------------------------

## Negative controls: the audit and the timeline check must actually notice a cooked ledger.
func test_the_auditor_flags_tampering() -> void:
	var s: MatchState = QaUtil.flat_state([300, 700, 1300] as Array[int])  # a third tank: the round goes on
	for t: TankState in s.tanks:
		t.money = 5000
	var action: Dictionary = {"kind": "fire", "tank": 0, "angle": 450, "power": 400, "weapon": "pulse_missile"}
	var p: int = WeaponTestUtil.power_for_landing(s, 450, 700)
	action["power"] = p
	var snap: Dictionary = M3.snapshot(s)
	var ev: Array[Dictionary] = Simulation.apply_action(s, action)
	assert_eq(M3.audit(snap, s, action, ev), [] as Array[String], "the honest books balance")
	assert_gt(QaUtil.find(ev, "damage").size(), 0, "the shot hit")
	var tweaks: Dictionary = {
		"money +1": func(st: MatchState) -> void: st.tanks[0].money += 1,
		"money -1": func(st: MatchState) -> void: st.tanks[0].money -= 1,
		"kills +1": func(st: MatchState) -> void: st.tanks[0].kills += 1,
		"damage_dealt +1": func(st: MatchState) -> void: st.tanks[0].damage_dealt += 1,
		"victim health +1": func(st: MatchState) -> void: st.tanks[1].health += 1,
		"stock +1": func(st: MatchState) -> void: st.tanks[0].inventory[Catalog.index_of("pulse_missile")] += 1,
		"turn_number +1": func(st: MatchState) -> void: st.turn_number += 1,
		"wrong tank to move": func(st: MatchState) -> void: st.current_tank = 0,
		"angle not recorded": func(st: MatchState) -> void: st.tanks[0].angle += 1,
		"round win from nowhere": func(st: MatchState) -> void: st.tanks[1].round_wins += 1,
	}
	for name: String in tweaks:
		var cooked: MatchState = s.duplicate_state()
		(tweaks[name] as Callable).call(cooked)
		assert_gt(M3.audit(snap, cooked, action, ev).size(), 0, "audit notices: %s" % name)
	# Cooked event streams.
	var dropped: Array[Dictionary] = ev.duplicate()
	for i: int in range(dropped.size()):
		if dropped[i]["type"] == "money":
			dropped.remove_at(i)
			break
	assert_gt(M3.audit(snap, s, action, dropped).size(), 0, "audit notices a missing money event")
	var doubled: Array[Dictionary] = ev.duplicate()
	for i: int in range(doubled.size()):
		if doubled[i]["type"] == "money":
			doubled.insert(i, doubled[i])
			break
	assert_gt(M3.audit(snap, s, action, doubled).size(), 0, "audit notices a duplicated money event")
	var reordered: Array[Dictionary] = ev.duplicate()
	var wi: int = QaUtil.types(reordered).find("wind")
	reordered.insert(0, reordered.pop_at(wi))
	assert_gt(M3.check_timeline(action, reordered).size(), 0, "timeline check notices a wind event moved to the front")
	var no_turn: Array[Dictionary] = ev.slice(0, ev.size() - 1)
	assert_gt(M3.check_timeline(action, no_turn).size(), 0, "timeline check notices a missing turn event")
	var bad_field: Array[Dictionary] = ev.duplicate(true)
	bad_field[0]["extra"] = 1
	assert_gt(M3.check_timeline(action, bad_field).size(), 0, "timeline check notices an undocumented field")
	# Standings check notices a wrong order.
	var st2: MatchState = _tie_state([[1, 0, 0], [2, 0, 0]])
	assert_eq(M3.check_standings(st2).size(), 0)
	st2.tanks[0].round_wins = 3
	assert_eq(M3.check_standings(st2).size(), 0, "standings are recomputed, not stored")


## Shop actions of different tanks commute: any interleaving gives the same state.
func test_shop_actions_of_different_tanks_commute() -> void:
	for m: int in range(8):
		var s := MatchSettings.new()
		s.seed = 90 + m
		s.num_tanks = 2 + m % 6
		s.rounds = 2
		s.start_money = [3000, 10000, 25000][m % 3]
		s.full_unlocked = m % 4 != 3
		var probe: MatchState = Simulation.new_match(s)
		var bot := Rng.new(m)
		var lists: Array[Array] = []
		for t: TankState in probe.tanks:
			var mine: Array[Dictionary] = []
			for other: TankState in probe.tanks:
				other.ready = other.id < t.id  # the bot shops for the first tank that is not ready: tank t
			for _i: int in range(60):
				var a: Dictionary = M3.next_action(probe, bot)
				assert_eq(a["tank"], t.id)
				mine.append(a)
				Simulation.apply_action(probe, a)
				if a["kind"] == "ready":
					break
			lists.append(mine)
		var finals: Array[String] = []
		for order: int in range(3):
			var st: MatchState = Simulation.new_match(s)
			var cursor: Array[int] = []
			var remaining: int = 0
			for l: Array in lists:
				cursor.append(0)
				remaining += l.size()
			var shuffle := Rng.new(m * 5 + order)
			var tank: int = 0
			while remaining > 0:
				var pick: int = tank
				if order == 2:
					pick = shuffle.range_int(0, lists.size() - 1)
				elif order == 1:
					tank = (tank + 1) % lists.size()
				if cursor[pick] >= lists[pick].size():
					if order == 0:
						tank = (tank + 1) % lists.size()
					continue
				var act: Dictionary = lists[pick][cursor[pick]]
				cursor[pick] += 1
				remaining -= 1
				assert_gt(Simulation.apply_action(st, act).size(), 0, "order %d: %s legal" % [order, str(act)])
			assert_true(Simulation.all_ready(st))
			finals.append(Simulation.fingerprint(st))
			Simulation.start_round(st)
			finals.append(Simulation.fingerprint(st))
		assert_eq(finals[0], finals[2], "match %d: sequential vs round-robin shop" % m)
		assert_eq(finals[0], finals[4], "match %d: sequential vs shuffled shop" % m)
		assert_eq(finals[1], finals[3], "match %d: and the round they start" % m)
		assert_eq(finals[1], finals[5])


## Buying every catalog entry one bundle at a time until the shop refuses: the stop reason and the totals follow
## from the 99-unit cap, the bundle size and the money (section 17, 19, 25).
func test_buying_each_entry_to_the_limit_stops_exactly_at_cap_or_money() -> void:
	for id: String in Catalog.IDS:
		var def: Dictionary = Catalog.get_def(id)
		if def.get("unlimited", false):
			continue
		var price: int = def["price"]
		var bundle: int = def["bundle"]
		var money: int = 250000
		var s: MatchState = Simulation.new_match(QaUtil.settings(1, 2))
		s.tanks[0].money = money
		var bundles: int = 0
		var reason: String = ""
		for _i: int in range(200):
			var a: Dictionary = {"kind": "buy", "tank": 0, "item": id, "qty": 1}
			reason = Simulation.validate_action(s, a)
			if reason != "":
				break
			assert_gt(Simulation.apply_action(s, a).size(), 0)
			bundles += 1
		var by_cap: int = SimConstants.INVENTORY_CAP / bundle
		var by_money: int = money / price
		assert_eq(bundles, mini(by_cap, by_money), "%s: bundles bought" % id)
		assert_eq(reason, "inventory_full" if by_cap <= by_money else "no_money", "%s: why the shop stopped" % id)
		assert_eq(s.tanks[0].stock_of(id), bundles * bundle)
		assert_eq(s.tanks[0].money, money - bundles * price, "%s: exact spend" % id)
		assert_lte(s.tanks[0].stock_of(id), SimConstants.INVENTORY_CAP)
		assert_eq(M3.check_state(s), [] as Array[String])
