@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 1b: directed friendly-fire and team-end scenarios on hand-built flat ground (sections 39 / 40). The fuzz
## covers breadth; this file aims every weapon at a teammate, strips shields next to one, drops teammates off
## pillars and cliffs (falls caused by a teammate's shot, Drift Chute kept), checks seekers, repulsors, the
## draw / mutual-kill endings, and the map edges, power extremes, max wind and straight-up shots with teams.
## Every shot goes through the spec audit in qa_m6.gd.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M3 = preload("res://tests/qa/qa_m3.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")
const QaAi = preload("res://tests/qa/qa_ai.gd")

const GROUND: int = SimTestUtil.GROUND_Y

var _base: MatchState = null
var _notes: Dictionary = {}


func before_all() -> void:
	_base = SimTestUtil.flat_state(8)


## A copy of the flat field with `xs.size()` tanks, their teams and the friendly-fire flag; tank 0 is to act and
## every tank owns 99 of everything (money enough for nothing: no shopping happens here).
func _world(xs: Array[int], teams: Array[int], ff: bool) -> MatchState:
	var s: MatchState = _base.duplicate_state()
	while s.tanks.size() > xs.size():
		s.tanks.pop_back()
	s.settings.num_tanks = xs.size()
	var ctrl := PackedInt32Array()
	var tl := PackedInt32Array()
	for i: int in range(xs.size()):
		var t: TankState = s.tanks[i]
		t.x = xs[i]
		t.y = TankState.rest_y(s.terrain, t.x)
		t.team = teams[i] if not teams.is_empty() else i
		QaAi.give_everything(t)
		t.set_stock("drift_chute", 0)
		t.money = 5000
		ctrl.append(SimConstants.CTRL_HUMAN)
		tl.append(teams[i] if not teams.is_empty() else i)
	s.settings.controllers = ctrl
	s.settings.teams = tl if not teams.is_empty() else PackedInt32Array()
	s.settings.friendly_fire = ff
	s.settings.rounds = 3
	s.current_tank = 0
	s.turn_number = 0
	s.wind = 0
	return s


func _shield(t: TankState, id: String) -> void:
	t.shield_type = Catalog.index_of(id)
	t.shield_hp = ItemDefs.get_def(id)["hp"]


## Applies `action`, runs the spec audit, returns {ev, errs, before}.
func _shot(state: MatchState, action: Dictionary, tag: String) -> Dictionary:
	assert_eq(Simulation.validate_action(state, action), "", "%s: legal action" % tag)
	var before: Dictionary = M6.snap(state)
	var ev: Array[Dictionary] = Simulation.apply_action(state, action)
	var errs: Array[String] = M6.audit(before, state, action, ev, _notes)
	errs.append_array(M3.check_state(state))
	assert_eq(errs.size(), 0, "%s:\n%s" % [tag, "\n".join(errs.slice(0, 8))])
	return {"ev": ev, "errs": errs, "before": before}


func _aim(state: MatchState, from: int, to: int, weapon: String) -> Dictionary:
	var me: TankState = state.tanks[from]
	var tgt: TankState = state.tanks[to]
	var angle: int = 450 if tgt.x >= me.x else 1350
	var power: int = M3._plain_power(state, me, tgt, angle)
	if (WeaponDefs.get_def(weapon)["behavior"] as String) == "beam":
		angle = M3._beam_angle(me, tgt, Rng.new(1))
	return {"kind": "fire", "tank": from, "angle": angle, "power": power, "weapon": weapon}


func _hp_lost(ev: Array[Dictionary], tank: int) -> int:
	var total: int = 0
	for e: Dictionary in ev:
		if e["type"] == "damage" and (e["tank"] as int) == tank:
			total += e["amount"] as int
	return total


# --- every weapon aimed at a teammate -----------------------------------------------------------

func test_every_weapon_aimed_at_a_teammate_with_and_without_friendly_fire() -> void:
	var hit_on: Array[String] = []
	var rows: PackedStringArray = PackedStringArray()
	for weapon: String in WeaponDefs.DEFS.keys():
		for variant: int in range(3):  # 0 bare, 1 ion shield, 2 shield + repulsor + chute
			var tag: String = "%s variant %d" % [weapon, variant]
			var lost_on: int = 0
			var shield_lost_on: int = 0
			var lost_off: int = -1
			for ff: bool in [true, false]:
				var s: MatchState = _world([300, 700, 1200], [0, 0, 1], ff)
				var mate: TankState = s.tanks[1]
				if variant >= 1:
					_shield(mate, "ion_shield")
				if variant == 2:
					mate.repulsor_charge = 100
					mate.set_stock("drift_chute", 3)
				var r: Dictionary = _shot(s, _aim(s, 0, 1, weapon), "%s ff=%s" % [tag, str(ff)])
				if ff:
					lost_on = _hp_lost(r["ev"], 1)
					shield_lost_on = 60 - mate.shield_hp if variant >= 1 else 0
				else:
					lost_off = _hp_lost(r["ev"], 1)
					assert_eq(mate.health, 100, "%s: teammate untouched with friendly fire off" % tag)
					assert_eq(lost_off, 0, "%s: no damage event for the teammate" % tag)
					if variant >= 1:
						assert_eq(mate.shield_hp, 60, "%s: teammate shield untouched" % tag)
			if lost_on > 0 or shield_lost_on > 0:
				hit_on.append(weapon)
			rows.append("%s/%d:%d+%d" % [weapon, variant, lost_on, shield_lost_on])
	gut.p("FRIENDLY FIRE directed: weapons that reached the teammate with friendly fire on (HP+shield lost): %s" % ", ".join(rows))
	assert_gt(hit_on.size(), 10, "enough weapon kinds really reached the teammate to make the off-case meaningful")


func test_friendly_fire_on_charges_the_penalty_and_gives_no_credit() -> void:
	var s: MatchState = _world([300, 700, 1200], [0, 0, 1], true)
	var r: Dictionary = _shot(s, _aim(s, 0, 1, "pulse_missile"), "ff on direct hit")
	var lost: int = _hp_lost(r["ev"], 1)
	assert_gt(lost, 0, "the missile reached the teammate")
	var shooter: TankState = s.tanks[0]
	assert_eq(shooter.kills, 0)
	assert_eq(shooter.damage_dealt, 0, "no damage credit for a teammate hit")
	assert_eq(shooter.money, 5000 - mini(5000, (100 - s.tanks[1].health) * 15), "exactly the self-damage penalty")
	var reasons: Array[String] = []
	for e: Dictionary in QaUtil.find(r["ev"], "money"):
		reasons.append(e["reason"])
	assert_gt(reasons.size(), 0)
	for reason: String in reasons:
		assert_eq(reason, "self_damage", "only the penalty is booked (a hit and a fall can book it twice)")


func test_killing_a_teammate_with_friendly_fire_on_gives_no_kill_bonus_or_kill() -> void:
	var s: MatchState = _world([300, 700, 1200], [0, 0, 1], true)
	s.tanks[1].health = 1
	var r: Dictionary = _shot(s, _aim(s, 0, 1, "pulse_missile"), "ff on teammate kill")
	assert_false(s.tanks[1].alive, "the teammate died")
	assert_eq(s.tanks[0].kills, 0, "no kill count")
	for e: Dictionary in QaUtil.find(r["ev"], "money"):
		assert_ne(e["reason"], "kill")
		assert_ne(e["reason"], "damage")


# --- strips, falls, drags -------------------------------------------------------------------------

func test_static_burst_strips_enemies_but_not_protected_teammates() -> void:
	for ff: bool in [false, true]:
		var s: MatchState = _world([300, 700, 720], [0, 0, 1], ff)
		for i: int in [1, 2]:
			_shield(s.tanks[i], "glow_shield")
		s.tanks[0].set_stock("static_burst", 5)
		var r: Dictionary = _shot(s, _aim(s, 0, 1, "static_burst"), "static burst ff=%s" % str(ff))
		var downs: Array[int] = []
		for e: Dictionary in QaUtil.find(r["ev"], "shield_down"):
			downs.append(e["tank"])
		if ff:
			assert_false(s.tanks[1].has_shield(), "ff on: the teammate was stripped")
		else:
			assert_true(s.tanks[1].has_shield(), "ff off: the teammate keeps the shield")
			assert_eq(s.tanks[1].shield_hp, 30)
			assert_false(downs.has(1))
			assert_eq(s.tanks[1].health, 100)
		# The enemy 20 cells away is inside the radius in both modes: stripped.
		assert_false(s.tanks[2].has_shield(), "ff=%s: the enemy beside the teammate is stripped" % str(ff))
		assert_true(downs.has(2))


## Searches impact offsets for a shot that makes tank 1 (on a pillar) fall; returns the first action found
## on the given world builder, or {}.
func _find_pillar_shot(weapon: String, pillar: int, ff: bool) -> Dictionary:
	for off: int in range(-60, 61, 4):
		var s: MatchState = _pillar_world(pillar, ff)
		var me: TankState = s.tanks[0]
		var tx: int = s.tanks[1].x + off
		var angle: int = 450
		var power: int = M3._plain_power(s, me, _fake_at(s, tx), angle)
		var a: Dictionary = {"kind": "fire", "tank": 0, "angle": angle, "power": power, "weapon": weapon}
		var ev: Array[Dictionary] = Simulation.apply_action(s, a)
		for e: Dictionary in ev:
			if e["type"] == "tank_fall" and (e["tank"] as int) == 1:
				return a
	return {}


func _fake_at(state: MatchState, x: int) -> TankState:
	var t := TankState.new()
	t.x = x
	t.y = GROUND
	return t


func _pillar_world(pillar: int, ff: bool) -> MatchState:
	var s: MatchState = _world([300, 800, 1300], [0, 0, 1], ff)
	s.terrain.flatten(800 - 14, 800 + 13, GROUND - pillar)
	s.tanks[1].y = TankState.rest_y(s.terrain, 800)
	return s


func test_a_fall_caused_by_a_teammates_shot_costs_nothing_with_friendly_fire_off() -> void:
	var found: int = 0
	for weapon: String in ["nova_core", "hyperpulse", "bore_shell", "deep_bore", "supernova", "mound_mortar", "landslide"]:
		var a: Dictionary = _find_pillar_shot(weapon, 90, true)
		if a.is_empty():
			gut.p("FRIENDLY FIRE falls: no pillar shot found for %s" % weapon)
			continue
		found += 1
		for with_chute: bool in [false, true]:
			var on: MatchState = _pillar_world(90, true)
			var off: MatchState = _pillar_world(90, false)
			if with_chute:
				on.tanks[1].set_stock("drift_chute", 2)
				off.tanks[1].set_stock("drift_chute", 2)
			var r_on: Dictionary = _shot(on, a, "%s fall ff on chute %s" % [weapon, str(with_chute)])
			var r_off: Dictionary = _shot(off, a, "%s fall ff off chute %s" % [weapon, str(with_chute)])
			var falls_off: int = QaUtil.find(r_off["ev"], "tank_fall").size()
			assert_gt(falls_off, 0, "the teammate still falls (terrain physics are not friendly-fire dependent)")
			assert_eq(off.tanks[1].health, 100, "%s: no fall damage with friendly fire off" % weapon)
			assert_eq(off.tanks[1].stock_of("drift_chute"), 2 if with_chute else 0, "%s: chute kept" % weapon)
			assert_eq(QaUtil.find(r_off["ev"], "chute").size(), 0)
			gut.p("FRIENDLY FIRE fall %-12s chute %-5s: ff on: HP %d, chutes %d | ff off: HP %d, chutes %d" % [weapon,
					str(with_chute), on.tanks[1].health, on.tanks[1].stock_of("drift_chute"), off.tanks[1].health,
					off.tanks[1].stock_of("drift_chute")])
			if not with_chute and (r_on["ev"] as Array).size() > 0:
				assert_lt(on.tanks[1].health, 100, "ff on: the same shot does hurt (control)")
	assert_gt(found, 2, "pillar shots exist for at least three weapons")


func test_an_anchor_drag_off_a_ledge_costs_a_teammate_nothing_with_friendly_fire_off() -> void:
	var found: int = 0
	for pull_from: int in [-120, -80, -50, 50, 80, 120]:
		var base: MatchState = _world([300, 900, 1400], [0, 0, 1], true)
		base.terrain.flatten(900 - 60, 900 + 60, GROUND - 100)
		base.tanks[1].y = TankState.rest_y(base.terrain, 900)
		var tx: int = 900 + pull_from
		var a: Dictionary = {"kind": "fire", "tank": 0, "angle": 450,
				"power": M3._plain_power(base, base.tanks[0], _fake_at(base, tx), 450), "weapon": "riptide_anchor"}
		var probe: MatchState = base.duplicate_state()
		var pev: Array[Dictionary] = Simulation.apply_action(probe, a)
		var dragged: bool = false
		var fell: bool = false
		for e: Dictionary in pev:
			dragged = dragged or (e["type"] == "tank_drag" and (e["tank"] as int) == 1)
			fell = fell or (e["type"] == "tank_fall" and (e["tank"] as int) == 1)
		if not dragged:
			continue
		found += 1
		var off: MatchState = base.duplicate_state()
		off.settings.friendly_fire = false
		var r: Dictionary = _shot(off, a, "anchor ff off pull %d" % pull_from)
		assert_eq(off.tanks[1].health, 100, "pull %d: no HP lost" % pull_from)
		gut.p("FRIENDLY FIRE anchor pull %4d: teammate dragged, fell=%s, ff on HP %d, ff off HP %d" % [pull_from, str(fell),
				probe.tanks[1].health, off.tanks[1].health])
		assert_eq(QaUtil.find(r["ev"], "tank_drag").size() > 0, true, "still dragged (movement is not damage)")
	assert_gt(found, 0, "some impact point drags the teammate")


# --- seekers, repulsors, beams --------------------------------------------------------------------

func test_a_seeker_homes_on_the_enemy_not_the_teammate() -> void:
	var worse: int = 0
	for off_x: int in [60, 100, 150]:
		var teamed: MatchState = _world([300, 800, 800 + off_x], [0, 0, 1], true)
		var ffa: MatchState = _world([300, 800, 800 + off_x], [], true)
		teamed.tanks[0].set_stock("seeker", 5)
		ffa.tanks[0].set_stock("seeker", 5)
		var angle: int = 520
		var power: int = 560
		var tr_team: Dictionary = Ballistics.trace(teamed, 0, angle, power, "seeker", SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
		var tr_ffa: Dictionary = Ballistics.trace(ffa, 0, angle, power, "seeker", SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
		var d_team: int = absi((tr_team["end_x"] as int) - 800)
		var d_ffa: int = absi((tr_ffa["end_x"] as int) - 800)
		var d_team_enemy: int = absi((tr_team["end_x"] as int) - (800 + off_x))
		gut.p("SEEKER off_x %d: ends at %d with teams (teammate at 800, enemy at %d), %d without teams" % [off_x,
				tr_team["end_x"], 800 + off_x, tr_ffa["end_x"]])
		# Without teams the nearest 'enemy' is tank 1 (x 800); with teams it must be tank 2.
		assert_lte(d_team_enemy, d_team + 1, "off_x %d: with teams the seeker is not pulled harder toward the teammate" % off_x)
		if d_team > d_ffa:
			worse += 1
		# The shell never ends INSIDE the teammate unless the plain arc does.
		var plain: Dictionary = Ballistics.trace(teamed, 0, angle, power, "pulse_missile", SimConstants.WIND_USE_STATE, SimConstants.MAX_FLIGHT_TICKS)
		if (plain["hit_tank"] as int if plain.has("hit_tank") else -1) != 1:
			assert_ne(tr_team.get("hit_tank", -1), 1, "off_x %d: the seeker did not curve into the teammate" % off_x)
	assert_gte(worse, 1, "the team makes a difference to homing in at least one layout")


func test_a_teammates_repulsor_with_friendly_fire_off_is_only_reported() -> void:
	# A shell flying through a teammate's repulsor field: HP / shield are never touched. Whether the field
	# still pushes the shell and burns its charge is a design question; the result is printed.
	var report: PackedStringArray = PackedStringArray()
	for ff: bool in [true, false]:
		var s: MatchState = _world([300, 700, 1200], [0, 0, 1], ff)
		s.tanks[1].repulsor_charge = 100
		var a: Dictionary = _aim(s, 0, 1, "pulse_missile")
		var r: Dictionary = _shot(s, a, "repulsor ff=%s" % str(ff))
		report.append("ff %s: charge 100 -> %d, teammate HP %d, shell ended near x=%s" % [str(ff), s.tanks[1].repulsor_charge,
				s.tanks[1].health, str(QaUtil.find(r["ev"], "projectile_end")[0]["x"])])
		if not ff:
			assert_eq(s.tanks[1].health, 100)
	gut.p("REPULSOR (teammate's field vs a teammate's shell): %s" % " | ".join(report))


func test_a_beam_stops_at_a_teammate_and_does_nothing_with_friendly_fire_off() -> void:
	var s: MatchState = _world([300, 700, 1200], [0, 0, 1], false)
	s.tanks[0].set_stock("photon_lance", 3)
	var tgt_angle: int = M3._beam_angle(s.tanks[0], s.tanks[2], Rng.new(1))
	var a: Dictionary = {"kind": "fire", "tank": 0, "angle": tgt_angle, "power": 500, "weapon": "photon_lance"}
	var r: Dictionary = _shot(s, a, "beam through a teammate")
	gut.p("BEAM ff off: aimed at the enemy at 1200 with a teammate at 700: enemy HP %d, teammate HP %d, events %s" % [
			s.tanks[2].health, s.tanks[1].health, ",".join(QaUtil.types(r["ev"]).slice(0, 8))])
	assert_eq(s.tanks[1].health, 100)


# --- endings ---------------------------------------------------------------------------------------

func test_two_tanks_destroying_each_other_at_once_is_a_draw_with_no_pay() -> void:
	for ff: bool in [true, false]:
		var s: MatchState = _world([700, 740], [0, 1], ff)
		s.tanks[0].health = 1
		s.tanks[1].health = 1
		var r: Dictionary = _shot(s, {"kind": "fire", "tank": 0, "angle": 450, "power": 90, "weapon": "nova_core"}, "mutual kill")
		var ends: Array[Dictionary] = QaUtil.find(r["ev"], "round_end")
		assert_eq(ends.size(), 1)
		if ends.size() == 1:
			assert_eq(ends[0]["winner"], -1)
			assert_eq(ends[0]["winner_team"], -1)
		assert_eq(s.tanks[0].round_wins + s.tanks[1].round_wins, 0, "no round wins on a draw")
		assert_false(s.tanks[0].alive or s.tanks[1].alive)
		assert_eq(QaUtil.find(r["ev"], "money").filter(func(e: Dictionary) -> bool: return e["reason"] == "survive" or e["reason"] == "win").size(), 0)


func test_a_dead_shooter_still_wins_with_the_team_when_a_teammate_survives() -> void:
	for ff: bool in [true, false]:
		var s: MatchState = _world([700, 1300, 740], [0, 0, 1], ff)
		s.tanks[0].health = 1
		s.tanks[2].health = 1
		var r: Dictionary = _shot(s, {"kind": "fire", "tank": 0, "angle": 450, "power": 90, "weapon": "nova_core"}, "shooter dies with its enemy")
		var ends: Array[Dictionary] = QaUtil.find(r["ev"], "round_end")
		assert_eq(ends.size(), 1, "ff=%s round ends" % str(ff))
		assert_false(s.tanks[0].alive)
		assert_false(s.tanks[2].alive)
		assert_true(s.tanks[1].alive)
		assert_eq(ends[0]["winner"], 1)
		assert_eq(ends[0]["winner_team"], 0)
		assert_eq(s.tanks[0].round_wins, 1, "the dead shooter's team won: it gets the round win")
		assert_eq(s.tanks[1].round_wins, 1)
		assert_eq(s.tanks[2].round_wins, 0)
		var pays: Dictionary = {}
		for e: Dictionary in QaUtil.find(r["ev"], "money"):
			if e["reason"] == "win" or e["reason"] == "survive":
				pays["%d:%s" % [e["tank"], e["reason"]]] = e["delta"]
		assert_eq(pays, {"0:win": 2500, "1:survive": 1000, "1:win": 2500})


func test_friendly_fire_on_one_shot_kills_enemy_teammate_and_shooter_is_a_draw() -> void:
	var s: MatchState = _world([700, 730, 760], [0, 0, 1], true)
	for t: TankState in s.tanks:
		t.health = 1
	var r: Dictionary = _shot(s, {"kind": "fire", "tank": 0, "angle": 450, "power": 90, "weapon": "nova_core"}, "everyone dies")
	var ends: Array[Dictionary] = QaUtil.find(r["ev"], "round_end")
	assert_eq(ends.size(), 1)
	assert_eq(ends[0]["winner"], -1)
	assert_eq(ends[0]["winner_team"], -1)
	assert_eq(QaUtil.find(r["ev"], "tank_destroyed").size(), 3)
	for t: TankState in s.tanks:
		assert_eq(t.round_wins, 0)


func test_friendly_fire_off_the_teammate_survives_and_wins_the_round() -> void:
	var s: MatchState = _world([700, 730, 760], [0, 0, 1], false)
	for t: TankState in s.tanks:
		t.health = 1
	var r: Dictionary = _shot(s, {"kind": "fire", "tank": 0, "angle": 450, "power": 90, "weapon": "nova_core"}, "ff off blast")
	assert_true(s.tanks[1].alive, "the protected teammate lives")
	assert_false(s.tanks[0].alive, "the shooter is not protected from itself")
	assert_false(s.tanks[2].alive)
	var ends: Array[Dictionary] = QaUtil.find(r["ev"], "round_end")
	assert_eq(ends.size(), 1)
	assert_eq(ends[0]["winner"], 1)
	assert_eq(ends[0]["winner_team"], 0)


# --- edges ------------------------------------------------------------------------------------------

func test_edges_power_extremes_max_wind_and_straight_up_shots_with_teams() -> void:
	var shots: int = 0
	var layouts: Array = [[[24, 800, 1576], [0, 0, 1]], [[13, 1587, 700], [0, 1, 1]]]
	for lay: Array in layouts:
		var xs: Array[int] = []
		for x: int in (lay[0] as Array):
			xs.append(x)
		var teams: Array[int] = []
		for t: int in (lay[1] as Array):
			teams.append(t)
		for ff: bool in [true, false]:
			for wind: int in [-100, 0, 100]:
				for angle: int in [0, 1, 899, 900, 901, 1799, 1800]:
					for power: int in [1, 1000]:
						for weapon: String in ["spark_dart", "supernova"]:
							var s: MatchState = _world(xs, teams, ff)
							s.wind = wind
							var a: Dictionary = {"kind": "fire", "tank": 0, "angle": angle, "power": power, "weapon": weapon}
							_shot(s, a, "edge xs %s ff %s wind %d angle %d power %d %s" % [str(xs), str(ff), wind, angle, power, weapon])
							shots += 1
	gut.p("EDGES: %d shots at map edges / extreme angles / power 1 and 1000 / wind +-100 with teams, all audited" % shots)
	assert_gt(shots, 300)
	# Out-of-range values are refused, never applied.
	var s2: MatchState = _world([300, 700, 1200], [0, 0, 1], true)
	for bad: Dictionary in [{"angle": -1, "power": 500}, {"angle": 1801, "power": 500}, {"angle": 450, "power": 0},
			{"angle": 450, "power": 1001}]:
		var act: Dictionary = {"kind": "fire", "tank": 0, "weapon": "spark_dart"}
		act.merge(bad)
		assert_ne(Simulation.validate_action(s2, act), "", "illegal %s" % str(bad))
		assert_eq(Simulation.apply_action(s2, act).size(), 0)


func test_dead_tanks_are_not_targets_victims_or_actors_in_team_games() -> void:
	var s: MatchState = _world([300, 700, 1200, 1500], [0, 0, 1, 1], true)
	s.tanks[1].health = 0
	s.tanks[1].alive = false
	var r: Dictionary = _shot(s, _aim(s, 0, 2, "pulse_missile"), "shot past a dead teammate")
	for e: Dictionary in r["ev"]:
		if e["type"] == "damage":
			assert_ne(e["tank"], 1, "nothing hits the dead tank")
	assert_eq(Simulation.validate_action(s, {"kind": "pass", "tank": 1}), "not_your_turn")
	# Wrap the turn order over the dead tank.
	var turns: Array[int] = []
	for _i: int in range(4):
		if s.phase != SimConstants.PHASE_AIM:
			break
		turns.append(s.current_tank)
		Simulation.apply_action(s, {"kind": "pass", "tank": s.current_tank})
	assert_false(turns.has(1), "the dead tank never gets a turn: %s" % str(turns))


# --- the audit has teeth -----------------------------------------------------------------------------------

## Plants violations into otherwise legal results and requires the audit in qa_m6.gd to notice each one: a
## green fuzz only means something if the oracle can fail.
func test_the_audit_catches_planted_violations() -> void:
	var caught: int = 0
	var planted: int = 0
	# 1. friendly fire off, but a teammate loses HP / shield / a chute anyway
	for variant: int in range(4):
		var s: MatchState = _world([300, 700, 1200], [0, 0, 1], false)
		var a: Dictionary = _aim(s, 0, 1, "pulse_missile")
		var before: Dictionary = M6.snap(s)
		var ev: Array[Dictionary] = Simulation.apply_action(s, a)
		assert_eq(M6.audit(before, s, a, ev).size(), 0, "the clean result passes")
		match variant:
			0:
				s.tanks[1].health -= 5
			1:
				s.tanks[1].shield_type = Catalog.index_of("glow_shield")
				s.tanks[1].shield_hp = 10
				before["tanks"][1]["sh"] = 30
				before["tanks"][1]["st"] = Catalog.index_of("glow_shield")
			2:
				s.tanks[1].set_stock("drift_chute", 1)
			3:
				var forged: Dictionary = {"type": "damage", "tick": 5, "tank": 1, "amount": 10, "health": 90, "cause": "explosion"}
				ev.insert(ev.size() - 2, forged)
		planted += 1
		if M6.audit(before, s, a, ev).size() > 0:
			caught += 1
	# 2. friendly fire on: credit or kill bonus for a teammate hit
	var s2: MatchState = _world([300, 700, 1200], [0, 0, 1], true)
	s2.tanks[1].health = 1
	var a2: Dictionary = _aim(s2, 0, 1, "pulse_missile")
	var b2: Dictionary = M6.snap(s2)
	var e2: Array[Dictionary] = Simulation.apply_action(s2, a2)
	assert_eq(M6.audit(b2, s2, a2, e2).size(), 0)
	s2.tanks[0].kills += 1
	planted += 1
	caught += 1 if M6.audit(b2, s2, a2, e2).size() > 0 else 0
	s2.tanks[0].kills -= 1
	s2.tanks[0].damage_dealt += 10
	planted += 1
	caught += 1 if M6.audit(b2, s2, a2, e2).size() > 0 else 0
	# 3. round end: wrong winner_team, missing pay, pay for a loser, no round win for a dead teammate
	var s3: MatchState = _world([700, 1300, 740], [0, 0, 1], true)
	s3.tanks[0].health = 1
	s3.tanks[2].health = 1
	var a3: Dictionary = {"kind": "fire", "tank": 0, "angle": 450, "power": 90, "weapon": "nova_core"}
	var b3: Dictionary = M6.snap(s3)
	var e3: Array[Dictionary] = Simulation.apply_action(s3, a3)
	assert_eq(M6.audit(b3, s3, a3, e3).size(), 0, "the clean team win passes")
	var forged_end: Array[Dictionary] = e3.duplicate(true)
	for e: Dictionary in forged_end:
		if e["type"] == "round_end":
			e["winner_team"] = 1
	planted += 1
	caught += 1 if M6.audit(b3, s3, a3, forged_end).size() > 0 else 0
	var no_pay: Array[Dictionary] = []
	for e: Dictionary in e3:
		if not (e["type"] == "money" and e["reason"] == "win" and e["tank"] == 0):
			no_pay.append(e)
	planted += 1
	caught += 1 if M6.audit(b3, s3, a3, no_pay).size() > 0 else 0
	s3.tanks[0].round_wins = 0
	planted += 1
	caught += 1 if M6.audit(b3, s3, a3, e3).size() > 0 else 0
	s3.tanks[0].round_wins = 1
	# 4. sudden death: a wrong amount, a missing event, a wrong cycle counter, a shield hit by the drain
	var s4: MatchState = _world([300, 700, 1200], [], true)
	s4.turn_number = 29
	s4.current_tank = 2
	var a4: Dictionary = {"kind": "pass", "tank": 2}
	var b4: Dictionary = M6.snap(s4)
	var e4: Array[Dictionary] = Simulation.apply_action(s4, a4)
	assert_eq(M6.audit(b4, s4, a4, e4).size(), 0, "the clean drain passes")
	var bad_amount: Array[Dictionary] = e4.duplicate(true)
	for e: Dictionary in bad_amount:
		if e["type"] == "damage":
			e["amount"] = 6
	planted += 1
	caught += 1 if M6.audit(b4, s4, a4, bad_amount).size() > 0 else 0
	var no_sd: Array[Dictionary] = []
	for e: Dictionary in e4:
		if e["type"] != "sudden_death":
			no_sd.append(e)
	planted += 1
	caught += 1 if M6.audit(b4, s4, a4, no_sd).size() > 0 else 0
	s4.sudden_death_cycles = 2
	planted += 1
	caught += 1 if M6.audit(b4, s4, a4, e4).size() > 0 else 0
	s4.sudden_death_cycles = 1
	s4.turn_number = 30 + 1
	planted += 1
	caught += 1 if M6.audit(b4, s4, a4, e4).size() > 0 else 0
	gut.p("AUDIT SELF-TEST: %d planted violations, %d caught" % [planted, caught])
	assert_eq(caught, planted, "every planted violation was reported")
