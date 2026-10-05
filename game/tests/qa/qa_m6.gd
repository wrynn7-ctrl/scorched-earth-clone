@warning_ignore_start("integer_division")
extends RefCounted
## M6 QA helpers (not a test file). Load with `const M6 = preload("res://tests/qa/qa_m6.gd")`.
##
## Holds: random team layouts, a scripted "human" bot that also shoots at teammates, per-action AUDIT of
## sections 39 and 40 written from the spec (not from the code under test): round end, winner_team, round
## pay, the friendly-fire immunity, the teammate penalty, standings, the sudden-death threshold and drain;
## snapshots, labels and small statistics helpers.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")

const SURVIVE_PAY: int = 1000
const WIN_PAY: int = 2500
const CREDIT_PER_HP: int = 15
const KILL_BONUS: int = 1500
const SD_PER_TANK: int = 10
const SD_BASE: int = 5
const SD_MAX: int = 25


# --- layouts ------------------------------------------------------------------------------------

## A team list for `n` tanks (>= 2 distinct values). `kind` picks the family; team ids are a random
## permutation of A..D so that "team 0" is not always the first one.
static func team_layout(rng: Rng, n: int, kind: int) -> PackedInt32Array:
	var raw: Array[int] = []
	var k: int = kind % 7
	if n < 4 and k == 4:
		k = 1
	match k:
		0:  # contiguous halves
			for i: int in range(n):
				raw.append(0 if i < (n + 1) / 2 else 1)
		1:  # interleaved
			for i: int in range(n):
				raw.append(i % 2)
		2:  # one against the rest (7v1 with 8 tanks), the lone tank anywhere
			var lone: int = rng.range_int(0, n - 1)
			for i: int in range(n):
				raw.append(1 if i == lone else 0)
		3:  # three teams (2v2v2 with 6)
			for i: int in range(n):
				raw.append(i % 3 if n >= 3 else i % 2)
		4:  # four teams
			for i: int in range(n):
				raw.append(i % 4)
		5:  # uneven random
			for i: int in range(n):
				raw.append(rng.range_int(0, mini(3, n - 1)))
		_:  # first tank alone, the others split
			for i: int in range(n):
				raw.append(0 if i == 0 else 1 + (i % 2))
	var distinct: Dictionary = {}
	for v: int in raw:
		distinct[v] = true
	if distinct.size() < 2:
		raw[n - 1] = (raw[0] + 1) % 4
	return relabel(rng, raw)


## The same split with the team numbers randomly permuted (so "team 0" is not always the first one).
static func relabel(rng: Rng, raw: Array[int]) -> PackedInt32Array:
	var perm: Array[int] = [0, 1, 2, 3]
	for i: int in range(3, 0, -1):
		var j: int = rng.range_int(0, i)
		var tmp: int = perm[i]
		perm[i] = perm[j]
		perm[j] = tmp
	var out := PackedInt32Array()
	for v: int in raw:
		out.append(perm[v])
	return out


## "4v4", "7v1", "2v2v2", "3v2v1" ... (team sizes, biggest first), or "FFA" without teams.
static func label(teams: PackedInt32Array, n: int) -> String:
	if teams.is_empty():
		return "FFA%d" % n
	var counts: Dictionary = {}
	for t: int in teams:
		counts[t] = (counts.get(t, 0) as int) + 1
	var sizes: Array[int] = []
	for t: int in range(4):
		if counts.has(t):
			sizes.append(counts[t] as int)
	sizes.sort()
	sizes.reverse()
	var parts: PackedStringArray = PackedStringArray()
	for s: int in sizes:
		parts.append(str(s))
	return "v".join(parts)


# --- scripted human ------------------------------------------------------------------------------

## Shop for every tank: CPU seats use the AI's shop, human seats a random shopper. Applies real actions
## (appended to `log`), then every tank is ready.
static func shop_phase(state: MatchState, rng: Rng, log: Array[Dictionary]) -> void:
	for t: TankState in state.tanks:
		if t.ready:
			continue
		if state.settings.controllers[t.id] != SimConstants.CTRL_HUMAN:
			for a: Dictionary in AiPlayer.shop_actions(state, t.id):
				Simulation.apply_action(state, a)
				log.append(a)
			continue
		var guard: int = 0
		while not t.ready and guard < 80:
			guard += 1
			var a: Dictionary = M3.next_action(state, rng)
			if a.get("kind", "") == M3.START_ROUND or a.is_empty():
				break
			if Simulation.validate_action(state, a) != "":
				continue
			Simulation.apply_action(state, a)
			log.append(a)
		if not t.ready:
			var r: Dictionary = {"kind": "ready", "tank": t.id}
			Simulation.apply_action(state, r)
			log.append(r)


## One action for the current tank, as a (not very smart) person would: mostly shots with random owned
## weapons, `mate_pct` percent of them aimed at a teammate when there is one, some passes, items and walks.
static func human_action(state: MatchState, rng: Rng, pass_pct: int, mate_pct: int) -> Dictionary:
	var me: TankState = state.tanks[state.current_tank]
	var roll: int = rng.range_int(0, 99)
	if roll < pass_pct:
		return {"kind": "pass", "tank": me.id}
	roll = rng.range_int(0, 99)
	if roll < 10 and not me.has_shield():
		for id: String in M3.SHIELDS:
			if me.stock_of(id) > 0:
				return {"kind": "use_item", "tank": me.id, "item": id}
	if roll < 16 and me.repulsor_charge == 0 and me.stock_of("repulsor_field") > 0:
		return {"kind": "use_item", "tank": me.id, "item": "repulsor_field"}
	if roll < 20 and me.stock_of("nanorepair_kit") > 0 and me.health < 80:
		return {"kind": "use_item", "tank": me.id, "item": "nanorepair_kit"}
	if roll < 32 and (me.fuel > 0 or me.stock_of("fuel_cell") > 0):
		var dx: int = rng.range_int(1, 120)
		return {"kind": "move", "tank": me.id, "dx": dx if rng.range_int(0, 1) == 0 else -dx}
	return fire_action(state, me, rng, mate_pct)


static func fire_action(state: MatchState, me: TankState, rng: Rng, mate_pct: int) -> Dictionary:
	var owned: Array[String] = []
	for id: String in Catalog.IDS:
		if Catalog.is_weapon(id) and id != Catalog.SPARK_DART and me.stock_of(id) > 0:
			owned.append(id)
	var weapon: String = Catalog.SPARK_DART
	if not owned.is_empty() and rng.range_int(0, 9) != 0:
		weapon = owned[rng.range_int(0, owned.size() - 1)]
	var mates: Array[TankState] = []
	var foes: Array[TankState] = []
	for t: TankState in state.tanks:
		if not t.alive or t.id == me.id:
			continue
		if t.team == me.team:
			mates.append(t)
		else:
			foes.append(t)
	if (mates.is_empty() and foes.is_empty()) or rng.range_int(0, 9) == 0:
		return {"kind": "fire", "tank": me.id, "angle": rng.range_int(0, SimConstants.MAX_ANGLE),
				"power": rng.range_int(1, SimConstants.MAX_POWER), "weapon": weapon}
	var pool: Array[TankState] = foes
	if not mates.is_empty() and (foes.is_empty() or rng.range_int(0, 99) < mate_pct):
		pool = mates
	var tgt: TankState = pool[rng.range_int(0, pool.size() - 1)]
	var angle: int = rng.range_int(300, 700) if tgt.x >= me.x else rng.range_int(1100, 1500)
	var power: int = M3._plain_power(state, me, tgt, angle)
	if (Catalog.get_def(weapon)["behavior"] as String) == "beam":
		angle = M3._beam_angle(me, tgt, rng)
	power = clampi(power + rng.range_int(-15, 15), SimConstants.MIN_POWER, SimConstants.MAX_POWER)
	return {"kind": "fire", "tank": me.id, "angle": angle, "power": power, "weapon": weapon}


# --- snapshots -------------------------------------------------------------------------------------

static func snap(state: MatchState) -> Dictionary:
	var chute: int = Catalog.index_of("drift_chute")
	var tanks: Array[Dictionary] = []
	for t: TankState in state.tanks:
		tanks.append({"id": t.id, "team": t.team, "alive": t.alive, "health": t.health, "st": t.shield_type,
				"sh": t.shield_hp, "money": t.money, "kills": t.kills, "dd": t.damage_dealt, "wins": t.round_wins,
				"rc": t.repulsor_charge, "chutes": t.inventory[chute], "x": t.x, "y": t.y})
	return {"tanks": tanks, "cur": state.current_tank, "turn": state.turn_number,
			"cycles": state.sudden_death_cycles, "phase": state.phase, "round": state.round_index}


static func threshold(settings: MatchSettings) -> int:
	return SD_PER_TANK * settings.num_tanks


static func teams_alive(alive: Array[bool], state: MatchState) -> int:
	var seen: Dictionary = {}
	for i: int in range(alive.size()):
		if alive[i]:
			seen[state.tanks[i].team] = true
	return seen.size()


## First living tank after `cur` in the cyclic order (cur itself is the last candidate); -1 if nobody lives.
static func next_alive(alive: Array[bool], cur: int) -> int:
	var n: int = alive.size()
	for step: int in range(1, n + 1):
		var c: int = (cur + step) % n
		if alive[c]:
			return c
	return -1


# --- standings (brute force from the definition) ------------------------------------------------------

## Tank ids best first: wins, damage_dealt, kills desc, then id asc (selection sort, no shared code).
static func expected_standings(state: MatchState) -> Array[int]:
	var left: Array[int] = []
	for t: TankState in state.tanks:
		left.append(t.id)
	var out: Array[int] = []
	while not left.is_empty():
		var best: int = 0
		for i: int in range(1, left.size()):
			var a: TankState = state.tanks[left[i]]
			var b: TankState = state.tanks[left[best]]
			var better: bool = false
			if a.round_wins != b.round_wins:
				better = a.round_wins > b.round_wins
			elif a.damage_dealt != b.damage_dealt:
				better = a.damage_dealt > b.damage_dealt
			elif a.kills != b.kills:
				better = a.kills > b.kills
			else:
				better = a.id < b.id
			if better:
				best = i
		out.append(left[best])
		left.remove_at(best)
	return out


## Team ids best first per section 39: wins (members share them), summed damage_dealt, summed kills, lowest id.
static func expected_team_standings(state: MatchState) -> Array[int]:
	var out: Array[int] = []
	if not state.settings.has_teams():
		return out
	var wins: Array[int] = [0, 0, 0, 0]
	var dmg: Array[int] = [0, 0, 0, 0]
	var kills: Array[int] = [0, 0, 0, 0]
	var used: Array[bool] = [false, false, false, false]
	for t: TankState in state.tanks:
		used[t.team] = true
		wins[t.team] = maxi(wins[t.team], t.round_wins)
		dmg[t.team] += t.damage_dealt
		kills[t.team] += t.kills
	var left: Array[int] = []
	for tm: int in range(4):
		if used[tm]:
			left.append(tm)
	while not left.is_empty():
		var best: int = 0
		for i: int in range(1, left.size()):
			var a: int = left[i]
			var b: int = left[best]
			var better: bool = false
			if wins[a] != wins[b]:
				better = wins[a] > wins[b]
			elif dmg[a] != dmg[b]:
				better = dmg[a] > dmg[b]
			elif kills[a] != kills[b]:
				better = kills[a] > kills[b]
			else:
				better = a < b
			if better:
				best = i
		out.append(left[best])
		left.remove_at(best)
	return out


# --- the audit -------------------------------------------------------------------------------------------

## Checks one aim-phase action against sections 10, 39 and 40. `before` is snap() taken before the action.
## Returns violations (empty = fine). `notes` (optional) receives counters for the report.
static func audit(before: Dictionary, state: MatchState, action: Dictionary, ev: Array[Dictionary],
		notes: Dictionary = {}) -> Array[String]:
	var errs: Array[String] = []
	var st: MatchSettings = state.settings
	var n: int = state.tanks.size()
	var bt: Array = before["tanks"]
	var kind: String = action["kind"]
	var actor: int = action["tank"]
	var attacker: int = actor if kind == "fire" else -1
	var ff: bool = st.friendly_fire
	var teams_on: bool = st.has_teams()
	errs.append_array(M3.check_timeline(action, ev))
	var health: Array[int] = []
	var alive: Array[bool] = []
	var money: Array[int] = []
	var money_sum: Array[int] = []
	for i: int in range(n):
		var b: Dictionary = bt[i]
		health.append(b["health"] as int)
		alive.append(b["alive"] as bool)
		money.append(b["money"] as int)
		money_sum.append(0)
	var re_idx: int = -1
	var re_count: int = 0
	var sd_events: int = 0
	var drain_seen: bool = false
	var alive_pre_drain: Array[bool] = []
	var drain_ids: Array[int] = []
	var dd_exp: int = 0
	var kills_exp: int = 0
	var pending: Array[Dictionary] = []  # money events expected next
	var exploded: bool = false
	for i: int in range(ev.size()):
		var e: Dictionary = ev[i]
		var type: String = e["type"]
		if type != "money" and not pending.is_empty():
			errs.append("expected money %s before %s" % [str(pending), type])
			pending.clear()
		match type:
			"round_end":
				re_count += 1
				re_idx = i
			"sudden_death":
				sd_events += 1
			"tank_destroyed":
				var d: int = e["tank"]
				if not alive[d]:
					errs.append("tank_destroyed for tank %d twice or for a dead tank" % d)
				alive[d] = false
				if health[d] != 0:
					errs.append("tank_destroyed for tank %d with health %d" % [d, health[d]])
			"damage":
				var tid: int = e["tank"]
				var cause: String = e["cause"]
				var after: int = e["health"]
				var prev: int = health[tid]
				var removed: int = prev - after
				if removed < 0 or after < 0:
					errs.append("damage event raises health of tank %d (%d -> %d)" % [tid, health[tid], after])
				if not alive[tid]:
					errs.append("damage to dead tank %d" % tid)
				if (e["amount"] as int) < removed or (e["amount"] as int) <= 0:
					errs.append("damage amount %d vs removed %d" % [e["amount"], removed])
				health[tid] = after
				if cause == "sudden_death":
					if not drain_seen:
						drain_seen = true
						alive_pre_drain = alive.duplicate()
					drain_ids.append(tid)
					if removed != mini(e["amount"] as int, prev) or removed <= 0:
						errs.append("drain removed %d of %d (health was %d)" % [removed, e["amount"], prev])
					continue
				if drain_seen:
					errs.append("shot damage after the drain started")
				if re_idx >= 0:
					errs.append("damage after round_end")
				if attacker < 0:
					continue  # a walking fall: nobody's credit (and no money)
				var same_team: bool = state.tanks[attacker].team == state.tanks[tid].team
				if same_team:
					var pen: int = maxi(-removed * CREDIT_PER_HP, -money[attacker])
					if pen != 0:
						pending.append({"tank": attacker, "reason": "self_damage", "delta": pen})
					if tid != attacker and not ff:
						errs.append("teammate %d damaged (cause %s) with friendly fire off" % [tid, cause])
				else:
					dd_exp += removed
					pending.append({"tank": attacker, "reason": "damage", "delta": removed * CREDIT_PER_HP})
					if after == 0:
						kills_exp += 1
						pending.append({"tank": attacker, "reason": "kill", "delta": KILL_BONUS})
			"money":
				var mt: int = e["tank"]
				var delta: int = e["delta"]
				money[mt] += delta
				money_sum[mt] += delta
				if money[mt] != (e["money"] as int):
					errs.append("money event of tank %d shows %d, running total %d" % [mt, e["money"], money[mt]])
				if money[mt] < 0:
					errs.append("tank %d money below 0" % mt)
				if re_idx < 0:
					if pending.is_empty():
						errs.append("unexpected money event %s" % str(e))
					else:
						var want: Dictionary = pending.pop_front()
						if want["tank"] != mt or want["reason"] != e["reason"] or want["delta"] != delta:
							errs.append("money event %s, expected %s" % [str(e), str(want)])
			"shield_hit", "shield_down":
				if drain_seen:
					errs.append("%s during the drain (it must bypass shields)" % type)
				if not ff and teams_on and attacker >= 0:
					var sv: int = e["tank"]
					if sv != attacker and state.tanks[sv].team == state.tanks[attacker].team:
						errs.append("%s on teammate %d with friendly fire off" % [type, sv])
			"explosion":
				exploded = true
			"repair":
				health[e["tank"] as int] = e["health"]
			"repulsor_down":
				var rv: int = e["tank"]
				# After the blast = stripped (Static Burst); before it = the field ran dry in flight.
				if exploded and not ff and teams_on and attacker >= 0 and rv != attacker \
						and state.tanks[rv].team == state.tanks[attacker].team:
					errs.append("repulsor of teammate %d stripped with friendly fire off" % rv)
			"chute":
				var cv: int = e["tank"]
				if not ff and teams_on and attacker >= 0 and cv != attacker \
						and state.tanks[cv].team == state.tanks[attacker].team:
					errs.append("teammate %d spent a chute from a teammate's shot with friendly fire off" % cv)
	if not pending.is_empty():
		errs.append("money events missing at the end: %s" % str(pending))
	# --- end state vs the event walk -------------------------------------------------------------
	var alive_final: Array[bool] = []
	for t: TankState in state.tanks:
		alive_final.append(t.alive)
		if t.health != health[t.id]:
			errs.append("tank %d health %d, events say %d" % [t.id, t.health, health[t.id]])
		if t.alive != alive[t.id]:
			errs.append("tank %d alive=%s, events say %s" % [t.id, str(t.alive), str(alive[t.id])])
		if t.money != money[t.id]:
			errs.append("tank %d money %d, events say %d" % [t.id, t.money, money[t.id]])
		var b: Dictionary = bt[t.id]
		var kd: int = t.kills - (b["kills"] as int)
		var dd: int = t.damage_dealt - (b["dd"] as int)
		var want_k: int = kills_exp if t.id == attacker else 0
		var want_d: int = dd_exp if t.id == attacker else 0
		if kd != want_k:
			errs.append("tank %d kills +%d, expected +%d" % [t.id, kd, want_k])
		if dd != want_d:
			errs.append("tank %d damage_dealt +%d, expected +%d" % [t.id, dd, want_d])
	# --- turn / round flow, from the spec -------------------------------------------------------
	var item: String = action.get("item", "")
	var ends_turn: bool = kind == "fire" or kind == "pass" or (kind == "use_item" and item == "nanorepair_kit") \
			or (kind == "move" and not state.tanks[actor].alive)
	var alive_pre: Array[bool] = alive_pre_drain if drain_seen else alive_final
	var over_pre: bool = teams_alive(alive_pre, state) <= 1
	var turn_after: int = (before["turn"] as int) + 1
	var cur: int = before["cur"]
	var standard: bool = st.mode == SimConstants.MODE_STANDARD
	var sudden_active: bool = standard and turn_after >= threshold(st)
	var wrapped: bool = false
	var nx: int = next_alive(alive_pre, cur)
	if nx >= 0:
		wrapped = nx <= cur
	var exp_sd: int = 1 if (ends_turn and not over_pre and standard and turn_after == threshold(st)) else 0
	var exp_drain: bool = ends_turn and not over_pre and sudden_active and wrapped
	if sd_events != exp_sd:
		errs.append("%d sudden_death event(s), expected %d (turn %d -> %d, threshold %d)" % [sd_events, exp_sd,
				before["turn"], turn_after, threshold(st)])
	if drain_seen != exp_drain:
		errs.append("drain %s, expected %s (turn %d -> %d, cur %d, next %d, threshold %d)" % [str(drain_seen),
				str(exp_drain), before["turn"], turn_after, cur, nx, threshold(st)])
	if drain_seen:
		var cycles_after: int = (before["cycles"] as int) + 1
		if state.sudden_death_cycles != cycles_after:
			errs.append("sudden_death_cycles %d, expected %d" % [state.sudden_death_cycles, cycles_after])
		var amount: int = mini(SD_BASE * cycles_after, SD_MAX)
		var want_ids: Array[int] = []
		for i: int in range(n):
			if alive_pre_drain[i]:
				want_ids.append(i)
		if drain_ids != want_ids:
			errs.append("drain hit tanks %s, expected the living %s in id order" % [str(drain_ids), str(want_ids)])
		for e: Dictionary in ev:
			if e["type"] == "damage" and e["cause"] == "sudden_death" and (e["amount"] as int) != amount:
				errs.append("drain amount %d, expected %d (cycle %d)" % [e["amount"], amount, cycles_after])
		# shields are untouched by the drain
		for t: TankState in state.tanks:
			var b2: Dictionary = bt[t.id]
			if alive_pre_drain[t.id] and not (b2["sh"] == t.shield_hp and b2["st"] == t.shield_type) \
					and not _shield_events_for(ev, t.id):
				errs.append("tank %d shield changed during the drain without an event" % t.id)
	elif state.sudden_death_cycles != (before["cycles"] as int):
		errs.append("sudden_death_cycles changed without a drain")
	var over_post: bool = teams_alive(alive_final, state) <= 1
	var exp_end: bool = ends_turn and (over_pre or over_post)
	if (re_count == 1) != exp_end or re_count > 1:
		errs.append("%d round_end event(s), expected %s (over_pre %s, over_post %s)" % [re_count, str(exp_end),
				str(over_pre), str(over_post)])
	if not ends_turn and (QaUtil.find(ev, "turn").size() > 0):
		errs.append("a turn event after a non-ending action")
	var exp_turn_no: int = before["turn"]
	if ends_turn and not over_pre:
		exp_turn_no = turn_after
	if state.turn_number != exp_turn_no:
		errs.append("turn_number %d, expected %d" % [state.turn_number, exp_turn_no])
	if ends_turn and not exp_end:
		var nxt: int = next_alive(alive_final, cur)
		if state.current_tank != nxt:
			errs.append("current_tank %d, expected %d" % [state.current_tank, nxt])
		var turns: Array[Dictionary] = QaUtil.find(ev, "turn")
		if turns.size() != 1 or (turns[0]["tank"] as int) != nxt:
			errs.append("turn event %s, expected tank %d" % [str(turns), nxt])
		if state.phase != SimConstants.PHASE_AIM:
			errs.append("phase %s after a turn change" % state.phase)
	if not ends_turn and state.current_tank != cur:
		errs.append("current_tank changed by a non-ending action")
	if re_count == 1:
		errs.append_array(_audit_round_end(before, state, ev, re_idx, alive_final))
	# --- friendly fire off: nothing happens to a teammate -------------------------------------------
	if teams_on and not ff and kind == "fire":
		for t: TankState in state.tanks:
			var b3: Dictionary = bt[t.id]
			if t.id == actor or t.team != state.tanks[actor].team or not (b3["alive"] as bool):
				continue
			var drained: int = 0
			for e: Dictionary in ev:
				if e["type"] == "damage" and (e["tank"] as int) == t.id and e["cause"] == "sudden_death":
					drained += e["amount"] as int
			if t.health != maxi(0, (b3["health"] as int) - drained):
				errs.append("teammate %d health %d -> %d with %d drained, friendly fire off" % [t.id, b3["health"],
						t.health, drained])
			if t.alive and (t.shield_hp != (b3["sh"] as int) or t.shield_type != (b3["st"] as int)):
				errs.append("teammate %d shield changed (%d/%d -> %d/%d), friendly fire off" % [t.id, b3["st"], b3["sh"],
						t.shield_type, t.shield_hp])
			var chute_now: int = t.inventory[Catalog.index_of("drift_chute")]
			if chute_now != (b3["chutes"] as int):
				errs.append("teammate %d chutes %d -> %d, friendly fire off" % [t.id, b3["chutes"], chute_now])
			if t.repulsor_charge != (b3["rc"] as int):
				notes["mate_repulsor_changed"] = (notes.get("mate_repulsor_changed", 0) as int) + 1
			var pre_end: int = re_idx if re_idx >= 0 else ev.size()
			for i: int in range(pre_end):
				if ev[i]["type"] == "money" and (ev[i]["tank"] as int) == t.id:
					errs.append("teammate %d got a money event before round_end, friendly fire off" % t.id)
	if kind == "fire" and teams_on:
		var mate_events: int = 0
		for e: Dictionary in ev:
			if e["type"] == "damage" and e["cause"] != "sudden_death" and (e["tank"] as int) != actor \
					and state.tanks[e["tank"] as int].team == state.tanks[actor].team:
				mate_events += 1
		notes["mate_hits"] = (notes.get("mate_hits", 0) as int) + (1 if mate_events > 0 else 0)
	return errs


static func _shield_events_for(ev: Array[Dictionary], tank: int) -> bool:
	for e: Dictionary in ev:
		if (e["type"] == "shield_hit" or e["type"] == "shield_down") and (e["tank"] as int) == tank:
			return true
	return false


## Round end: winner, winner_team, pay and standings against the section 39 definition.
static func _audit_round_end(before: Dictionary, state: MatchState, ev: Array[Dictionary], re_idx: int,
		alive_final: Array[bool]) -> Array[String]:
	var errs: Array[String] = []
	var bt: Array = before["tanks"]
	var re: Dictionary = ev[re_idx]
	var winner: int = -1
	for i: int in range(alive_final.size()):
		if alive_final[i]:
			winner = i
			break
	var wteam: int = state.tanks[winner].team if winner >= 0 else -1
	if re["winner"] != winner or re["winner_team"] != wteam:
		errs.append("round_end winner %s/%s, expected %d/%d" % [str(re["winner"]), str(re["winner_team"]), winner, wteam])
	if wteam >= 0:
		for i: int in range(alive_final.size()):
			if alive_final[i] and state.tanks[i].team != wteam:
				errs.append("living tank %d is not on the winning team" % i)
	var want: Array[Dictionary] = []
	for t: TankState in state.tanks:
		if alive_final[t.id]:
			want.append({"tank": t.id, "reason": "survive", "delta": SURVIVE_PAY})
		if wteam >= 0 and t.team == wteam:
			want.append({"tank": t.id, "reason": "win", "delta": WIN_PAY})
	var got: Array[Dictionary] = []
	for i: int in range(re_idx + 1, ev.size()):
		var e: Dictionary = ev[i]
		if e["type"] != "money":
			errs.append("%s after round_end" % e["type"])
			continue
		got.append({"tank": e["tank"], "reason": e["reason"], "delta": e["delta"]})
	if got != want:
		errs.append("round pay %s, expected %s" % [str(got), str(want)])
	for t: TankState in state.tanks:
		var b: Dictionary = bt[t.id]
		var win_exp: int = (b["wins"] as int) + (1 if (wteam >= 0 and t.team == wteam) else 0)
		if t.round_wins != win_exp:
			errs.append("tank %d round_wins %d, expected %d" % [t.id, t.round_wins, win_exp])
	var last: bool = state.round_index + 1 >= state.settings.rounds
	var want_phase: String = SimConstants.PHASE_MATCH_OVER if last else SimConstants.PHASE_SHOP
	if state.phase != want_phase:
		errs.append("phase %s after round_end, expected %s" % [state.phase, want_phase])
	if Simulation.standings(state) != expected_standings(state):
		errs.append("standings %s, expected %s" % [str(Simulation.standings(state)), str(expected_standings(state))])
	if Simulation.team_standings(state) != expected_team_standings(state):
		errs.append("team_standings %s, expected %s" % [str(Simulation.team_standings(state)),
				str(expected_team_standings(state))])
	return errs


# --- stats ------------------------------------------------------------------------------------------------

static func scale() -> int:
	var v: String = OS.get_environment("QA_M6_SCALE")
	return maxi(1, int(v)) if v.is_valid_int() else 1


static func pct10(num: int, den: int) -> String:
	if den <= 0:
		return "n/a"
	return "%d.%d%%" % [num * 100 / den, (num * 1000 / den) % 10]
