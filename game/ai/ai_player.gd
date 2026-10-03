@warning_ignore_start("integer_division")
class_name AiPlayer
extends RefCounted
## The computer opponents (docs/ARCHITECTURE.md sections 27-30). Pure and deterministic: the
## same MatchState always gives the same action, on any device, because
##  * all randomness comes from the Rng stream derived from the match seed, the round, the
##    turn number and the tank id (never the global RNG, never the clock),
##  * everything that influences an action is integer maths,
##  * the only "memory" is what the simulation stores in the state (TankState.last_fire_*).
##
## One decision, in plain words:
##  1. Maybe prepare: heal, raise a shield, switch on a repulsor, or (rarely) walk out of a
##     pit. These actions do not fire (repair ends the turn), and the AI caps them so a turn
##     is never longer than 3 calls: shield, repulsor, fire; or move, fire.
##  2. Pick a target for the level (AiTargets) and a weapon (AiWeapons).
##  3. Solve for the exact angle and power with the physics (AimSolver).
##  4. Make it human: add the round's consistent power bias and a little noise (AiProfile), or
##     -- if the last shot was at this same target -- correct from where it landed, only as
##     strongly as the level's correction allows. That gives the "short, short, closer,
##     bracketed" pattern of a person, and an Expert that usually hits on the second shot.
## Whatever happens, the result is validated and replaced by a legal Spark Dart shot if
## anything is off.

const SHIELDS: Array[String] = ["fortress_field", "ion_shield", "glow_shield"]
## Last-shot weapon behaviours whose landing point is a fair reading of the aim error.
const CORRECTABLE_LAST: PackedStringArray = ["explode", "tunneler", "dirt", "splitter"]
const MAX_CORRECTION: int = 1000
## Model flights a decision may spend judging possible walks (it stops looking after that).
const MOVE_SEARCH_FLIGHTS: int = 60
## Largest damage to itself an Easy tank will still accept for a shot that is not worth it.
const EASY_SELF_HIT: int = 10
## At or below this health a Hard or Expert tank with a repair kit heals instead of gambling.
const CRITICAL_HEALTH: int = 20
## When nothing can reach any enemy, a walk is only chosen if all the fuel in hand fits in ONE
## move (max dx is 200): the walk then burns the lot, so a second walk in the same turn cannot
## follow and the turn stays within 3 calls (a shield, the walk, the shot).
const OUT_OF_REACH_FUEL: int = 200
## Extra launch angles (tenths of a degree above the horizontal) a full-power best-effort shot tries.
## A last shot at or above this power counts as "full power"; one that landed this far short of the target
## (cells) proves the target is out of reach from here (the AI's wind model may be wrong, the shell is not).
const FULL_POWER: int = 985
const SPENT_SHORT_BY: int = 150
const BEST_EFFORT_ANGLES: Array[int] = [300, 450, 600, 750]


## One action for the tank whose turn it is. May return a non-turn-ending action
## (use_item shield/repulsor, move); call again after applying it. A turn-ending action
## (fire, pass, use_item repair) always comes within 3 calls.
static func next_action(state: MatchState, tank_id: int) -> Dictionary:
	AimSolver.reset_budget()
	var fallback: Dictionary = _spark_fire(state, tank_id)
	if state.phase != SimConstants.PHASE_AIM or tank_id < 0 or tank_id >= state.tanks.size():
		return fallback
	var me: TankState = state.tanks[tank_id]
	if not me.alive or state.current_tank != tank_id:
		return fallback
	var action: Dictionary = _decide(state, me)
	if action.is_empty() or Simulation.validate_action(state, action) != "":
		return fallback
	return action


## Buys, then `ready`, for a tank in the shop phase. Every action is legal when applied in
## order. Empty if the tank is already ready.
static func shop_actions(state: MatchState, tank_id: int) -> Array[Dictionary]:
	return AiShop.actions(state, tank_id)


## The Rng stream of one decision: the same for every call within a turn.
static func turn_rng(state: MatchState, tank_id: int) -> Rng:
	return Rng.derive(state.seed, SimConstants.TAG_AI + tank_id).fork(
			state.round_index * 100000 + state.turn_number * 16 + tank_id)


## The round's persistent power bias in per-mille (signed). Same for every shot of the round.
static func round_bias(state: MatchState, tank_id: int, prof: Dictionary) -> int:
	var lo: int = prof["bias_min"]
	var hi: int = prof["bias_max"]
	if hi <= 0:
		return 0
	var r: Rng = Rng.derive(state.seed, SimConstants.TAG_AI + tank_id).fork(state.round_index * 100000 + 99999)
	var mag: int = r.range_int(lo, hi)
	return -mag if (r.next_u32() & 1) == 1 else mag


## Shot-to-shot jitter in per-mille: two uniform draws, so about `sigma` standard deviation.
static func _noise(rng: Rng, sigma: int) -> int:
	if sigma <= 0:
		return 0
	return rng.range_int(-sigma, sigma) + rng.range_int(-sigma, sigma)


static func _spark_fire(state: MatchState, tank_id: int) -> Dictionary:
	var angle: int = SimConstants.DEFAULT_ANGLE_LEFT
	if tank_id >= 0 and tank_id < state.tanks.size():
		var me: TankState = state.tanks[tank_id]
		var foe: TankState = AiTargets.nearest(me, AiTargets.enemies_of(state, me))
		if foe != null and foe.x < me.x:
			angle = SimConstants.DEFAULT_ANGLE_RIGHT
	return {"kind": "fire", "tank": tank_id, "angle": angle, "power": SimConstants.DEFAULT_POWER,
			"weapon": "spark_dart"}


static func _decide(state: MatchState, me: TankState) -> Dictionary:
	var level: int = AiProfile.level_of(state, me.id)
	var prof: Dictionary = AiProfile.for_level(level)
	var enemies: Array[TankState] = AiTargets.enemies_of(state, me)
	if enemies.is_empty():
		return {"kind": "pass", "tank": me.id}
	var prep: Dictionary = _prepare(state, me, prof, level, enemies)
	if not prep.is_empty():
		return prep
	var primary: TankState = AiTargets.pick(state, me, level)
	var best_plan: Dictionary = {}
	var best_sit: AiSituation = null
	var best_score: int = 0
	var far: Array[AiSituation] = []  # targets no weapon reaches from here
	for target: TankState in _target_order(me, enemies, primary):
		var sit: AiSituation = situation(state, me, level, prof, enemies, target)
		if target == primary:
			var walk: Dictionary = _maybe_move(sit)
			if not walk.is_empty():
				return walk
		var plan: Dictionary = AiWeapons.choose_and_plan(sit)
		if is_hopeless(sit, plan):
			far.append(sit)
			continue
		if plan["self_dmg"] == 0:
			return finalize(sit, plan)
		# Every option at this target would hurt us: remember the least bad one and look at
		# the next target (one farther away may be safe to shoot at).
		var score: int = (plan["enemy_dmg"] as int) - 3 * (plan["self_dmg"] as int) / 2
		if best_sit == null or score > best_score:
			best_plan = plan
			best_sit = sit
			best_score = score
	if best_sit == null:
		if far.is_empty():
			return {"kind": "pass", "tank": me.id}
		return _out_of_reach(me, far)
	# Worth the self-inflicted damage? Easy may still take a small hit (<= EASY_SELF_HIT), never a big one.
	if best_score > 0 or (level == SimConstants.CTRL_EASY and (best_plan["self_dmg"] as int) <= EASY_SELF_HIT
			and (best_plan["enemy_dmg"] as int) > 0):
		return finalize(best_sit, best_plan)
	return {"kind": "pass", "tank": me.id}


# --- nothing reaches ----------------------------------------------------------------------------------------

## True when nothing reaches this target from here: the plan found no hit and the best the solver managed
## still comes down SHORT (too far for the power, or a hill in the way; a shot that flies past the target is
## not out of range, less power fixes that), or the last full-power shot proved it (spent_short).
static func is_hopeless(sit: AiSituation, plan: Dictionary) -> bool:
	if not plan["ok"]:
		return is_out_of_range(sit) or sit.spent_short
	# A plan that looks fine on paper but whose kind of shot already fell short at full power.
	return sit.spent_short and ["explode", "splitter", "dirt"].has(WeaponDefs.get_def(plan["weapon"]).get("behavior", ""))


static func is_out_of_range(sit: AiSituation) -> bool:
	var d: Dictionary = sit.direct
	return not d["ok"] and (d["err"] as int) < -AimSolver.TOL_ACCEPT


## The last shot (same direction as the one now needed) was fired at full power and landed
## SPENT_SHORT_BY or more short of the target. Pure observation of the state, so it also holds after a walk
## and for an Easy tank that believes there is no wind.
static func spent_short(sit: AiSituation) -> bool:
	var me: TankState = sit.me
	if me.last_fire_weapon < 0 or me.last_fire_x < 0 or me.last_fire_power < FULL_POWER:
		return false
	var last_dir: int = 1 if me.last_fire_angle < 900 else -1
	if me.last_fire_angle != 900 and last_dir != sit.ctx.dir:
		return false
	return sit.ctx.dir * (me.last_fire_x - sit.target.x) < -SPENT_SHORT_BY


## Every enemy considered is out of reach. Walk towards the nearest one if the fuel allows, else send
## the full-power shot that comes down closest to an enemy (the wind may turn in our favour).
## All levels do this; it is not part of the accuracy model, so no bias or noise is added.
static func _out_of_reach(me: TankState, far: Array[AiSituation]) -> Dictionary:
	var near: AiSituation = far[0]
	var closest: AiSituation = far[0]
	for sit: AiSituation in far:
		if sit.dist < near.dist or (sit.dist == near.dist and sit.target.id < near.target.id):
			near = sit
		if absi(sit.direct["err"] as int) < absi(closest.direct["err"] as int):
			closest = sit
	var walk: Dictionary = _approach(near)
	if not walk.is_empty():
		return walk
	return _best_effort_shot(closest)


## The shot that lands closest to the target: the solver's best plan (at full power when the target is
## out of range), also trying a few more angles at full power. Spark Dart because it is always owned and the
## shot is not going to hurt anybody anyway.
static func _best_effort_shot(sit: AiSituation) -> Dictionary:
	var best_angle: int = sit.direct["angle"]
	var best_power: int = sit.direct["power"]
	var best_err: int = absi(sit.direct["err"] as int)
	if best_power >= SimConstants.MAX_POWER or sit.spent_short:
		best_power = SimConstants.MAX_POWER
		best_err = absi(sit.ctx.dir * (_model_land(sit, best_angle) - sit.target.x))
		for a_dir: int in BEST_EFFORT_ANGLES:
			var angle: int = AimSolver.actual_angle(sit.ctx, a_dir)
			var err: int = absi(sit.ctx.dir * (_model_land(sit, angle) - sit.target.x))
			if err < best_err:
				best_err = err
				best_angle = angle
	return {"kind": "fire", "tank": sit.me.id, "angle": best_angle, "power": best_power,
			"weapon": "spark_dart"}


static func _model_land(sit: AiSituation, angle: int) -> int:
	sit.flight.fly_shot(sit.me.x, sit.me.y, angle, SimConstants.MAX_POWER, sit.ctx.wind,
			AimSolver.MODEL_TICKS, sit.ctx.row)
	AimSolver.model_count += 1
	return sit.flight.r_x


## A walk of up to 200 cells towards `sit.target` (the longest the fuel and the ground allow), or {}.
static func _approach(sit: AiSituation) -> Dictionary:
	var me: TankState = sit.me
	var units: int = me.fuel + me.stock_of("fuel_cell") * (ItemDefs.get_def("fuel_cell")["amount"] as int)
	if units <= 0 or units > OUT_OF_REACH_FUEL:
		return {}
	# Shield and repulsor both up while shells are falling: a walk would be a fourth call.
	if me.has_shield() and me.repulsor_charge > 0 and AiTargets.recent_threat(sit.state, me, 250):
		return {}
	var dir: int = 1 if sit.target.x >= me.x else -1
	for amount: int in [200, 100, 50, 25]:
		var dx: int = dir * mini(amount, units)
		if _walk_dest(sit, dx).x != me.x:
			return {"kind": "move", "tank": me.id, "dx": dx}
	return {}


## The preferred target first, then (at most) the two nearest others: used when every shot at the
## preferred target would blow up in our own face.
static func _target_order(me: TankState, enemies: Array[TankState], primary: TankState) -> Array[TankState]:
	var order: Array[TankState] = [primary]
	var rest: Array[TankState] = []
	for e: TankState in enemies:
		if e.id != primary.id:
			rest.append(e)
	rest.sort_custom(func(a: TankState, b: TankState) -> bool:
		var da: int = absi(a.x - me.x)
		var db: int = absi(b.x - me.x)
		return da < db or (da == db and a.id < b.id))
	for i: int in range(mini(2, rest.size())):
		order.append(rest[i])
	return order


# --- items ---------------------------------------------------------------------------------------------

static func _use(me: TankState, item: String) -> Dictionary:
	return {"kind": "use_item", "tank": me.id, "item": item}


## Repair, shield or repulsor if the level wants one now. Never more than one per call.
static func _prepare(state: MatchState, me: TankState, prof: Dictionary, level: int,
		enemies: Array[TankState]) -> Dictionary:
	var repair_below: int = prof["repair_below"]
	if repair_below > 0 and me.health <= repair_below and me.stock_of("nanorepair_kit") > 0:
		var skip: bool = false
		if me.health <= CRITICAL_HEALTH:
			# Nearly dead: heal, unless one shot is all but certain to end the round.
			skip = _near_certain_last_kill(state, me, enemies)
		elif level == SimConstants.CTRL_EXPERT:
			for e: TankState in enemies:
				skip = skip or AiTargets.hp_eff(e) <= 55
		if not skip:
			return _use(me, "nanorepair_kit")
	if not me.has_shield():
		var mode: int = prof["shield"]
		var wants: bool = mode == AiProfile.SHIELD_ALWAYS or \
				(mode == AiProfile.SHIELD_WHEN_HURT and me.health < (prof["shield_below"] as int))
		if wants:
			for id: String in SHIELDS:
				if me.stock_of(id) > 0:
					return _use(me, id)
	if prof["repulsor"] and me.repulsor_charge < 30 and me.stock_of("repulsor_field") > 0 \
			and AiTargets.recent_threat(state, me, 250):
		return _use(me, "repulsor_field")
	return {}


## True if the one enemy left can be finished by a shot that cannot really miss: a Photon Lance
## with a clear first hit, or a short-range shot from a bracket that already landed on it.
static func _near_certain_last_kill(state: MatchState, me: TankState, enemies: Array[TankState]) -> bool:
	if enemies.size() != 1:
		return false
	var e: TankState = enemies[0]
	var hp: int = AiTargets.hp_eff(e)
	if hp > AiTargets.best_damage(me):
		return false
	var lance: Dictionary = WeaponDefs.get_def("photon_lance")
	if me.stock_of("photon_lance") > 0 and hp <= (lance["dmg"] as int):
		var angle: int = AimSolver.beam_angle(me.x, me.y, e.x, e.y - SimConstants.TANK_H / 2)
		var tr: Dictionary = AimSolver.counted_beam(state, me.id, angle, "photon_lance")
		if not tr.is_empty() and (tr["hit_tank"] as int) == e.id:
			return true
	return absi(e.x - me.x) <= 150 and me.last_fire_weapon >= 0 and me.last_fire_x >= 0 \
			and absi(me.last_fire_x - e.x) <= 40 and AiTargets.nearest_tank_to_x(state, me, me.last_fire_x) == e.id


# --- aiming ----------------------------------------------------------------------------------------------

static func situation(state: MatchState, me: TankState, level: int, prof: Dictionary,
		enemies: Array[TankState], forced_target: TankState = null) -> AiSituation:
	var sit := AiSituation.new()
	sit.state = state
	sit.me = me
	sit.level = level
	sit.prof = prof
	sit.rng = turn_rng(state, me.id)
	sit.enemies = enemies
	sit.target = forced_target if forced_target != null else AiTargets.pick(state, me, level)
	sit.nearest_id = AiTargets.nearest(me, enemies).id
	sit.dist = absi(sit.target.x - me.x)
	var dir: int = 1 if sit.target.x >= me.x else -1
	var wind: int = state.wind * (prof["wind_use"] as int) / 1000
	sit.flight = AiFlight.new(state.terrain, state.wells, others_with_repulsors(state, me))
	sit.ctx = AimSolver.new_ctx(state, me.id, me.x, me.y, wind, dir, sit.flight)
	sit.ctx.row = sit.target.y - SimConstants.TANK_H / 2
	sit.a0 = 450 + sit.rng.range_int(-70, 70)
	sit.direct = AimSolver.solve_direct(sit.ctx, sit.target.x, sit.a0)
	sit.corr = correction_for(sit)
	sit.spent_short = spent_short(sit)
	return sit


## The other alive tanks whose repulsor field is charged (the shooter's own never pushes its shell).
static func others_with_repulsors(state: MatchState, me: TankState) -> Array[TankState]:
	var out: Array[TankState] = []
	for t: TankState in state.tanks:
		if t.alive and t.id != me.id and t.repulsor_charge > 0:
			out.append(t)
	return out


## How far the last shot at this target landed from where the AI's model says it should have
## (cells, signed), together with that shot's angle and power. {} if the last shot was not at
## this target, was a weapon whose landing says little, or was lost.
static func correction_for(sit: AiSituation) -> Dictionary:
	var me: TankState = sit.me
	if me.last_fire_weapon < 0:
		return {}
	var last_def: Dictionary = WeaponDefs.get_def(Catalog.id_at(me.last_fire_weapon))
	var behavior: String = last_def.get("behavior", "")
	if not CORRECTABLE_LAST.has(behavior):
		return {}
	# A splitter reports where its first child landed; the model flies that child.
	var split_dvx: int = 0
	if behavior == "splitter":
		split_dvx = Ballistics.child_vx(0, 0, last_def["children"], last_def["spread"])
	var last_dir: int = 1 if me.last_fire_angle < 900 else -1
	if me.last_fire_angle != 900 and last_dir != sit.ctx.dir:
		return {}
	if me.last_fire_x < 0 or me.last_fire_y < 0:
		# The shell was lost off the map: no impact to read, but it told us the power was far too
		# much; correcting towards the exact solution from that power still brackets the target
		# (otherwise a biased tank would repeat the same lost shot for ever).
		return {"angle": me.last_fire_angle, "power": me.last_fire_power, "d": 0, "lost": true}
	if AiTargets.nearest_tank_to_x(sit.state, me, me.last_fire_x) != sit.target.id:
		return {}
	var wind_then: int = me.last_fire_wind * (sit.prof["wind_use"] as int) / 1000
	var model_x: int = AimSolver.model_x_at_row(sit.flight, me.x, me.y, me.last_fire_angle,
			me.last_fire_power, wind_then, me.last_fire_y, split_dvx)
	if not sit.flight.r_row_stop:
		return {}
	var d: int = me.last_fire_x - model_x
	if absi(d) > MAX_CORRECTION:
		return {}
	return {"angle": me.last_fire_angle, "power": me.last_fire_power, "d": d}


## Turns the exact plan into the shot the AI actually fires: bias and noise on the first shot
## at a target, a partial correction on later ones.
static func finalize(sit: AiSituation, plan: Dictionary) -> Dictionary:
	var me: TankState = sit.me
	var prof: Dictionary = sit.prof
	var bias: int = round_bias(sit.state, me.id, prof)
	var vet: bool = is_veteran(sit.state, prof)
	var noise: int = _noise(sit.rng, prof["veteran_noise"] if vet else prof["noise"])
	var angle: int = plan["angle"]
	var power: int = plan["power"]
	if plan.get("beam", false):
		# A straight beam has no power: the same inner error shows up as a small angle error.
		var err: int = (bias + noise) / 8
		var flat: bool = angle < 12 or angle > SimConstants.MAX_ANGLE - 12
		if flat:
			# Level with the target the beam can only err away from the box's top edge; a
			# human would aim along the ground, so the error is folded towards the horizontal.
			err = -absi(err) if angle < 900 else absi(err)
		angle = clampi(angle + err, 0, SimConstants.MAX_ANGLE)
	else:
		var factor: int = -1
		var lost: bool = sit.corr.get("lost", false)
		if plan["corrected"]:
			factor = correction_factor(prof, sit.rng, lost, false, vet)
		power = clampi(_with_error(plan, prof, bias, noise, factor, crude_lost(prof, lost)),
				SimConstants.MIN_POWER, SimConstants.MAX_POWER)
	return {"kind": "fire", "tank": me.id, "angle": angle, "power": power, "weapon": plan["weapon"]}


## True once the shooter has (about) had `veteran_shots` turns of its own this round. The turn number
## counts everybody's turns, so the share of it that is "mine" is turn_number / number of tanks.
static func is_veteran(state: MatchState, prof: Dictionary) -> bool:
	var need: int = prof["veteran_shots"]
	return need > 0 and state.turn_number / maxi(1, state.tanks.size()) >= need


## True if the next shot follows a lost shell and this level reacts to that crudely (see
## correction_factor) instead of bracketing.
static func crude_lost(prof: Dictionary, lost: bool) -> bool:
	return lost and (prof["lost_cut_max"] as int) > 0


## How far (per-mille) one correction moves the power from the last shot's towards the exact solution.
## 1000 is a full fix. Hard and Expert always use their fixed value (no random draw, so their streams
## are unchanged). Easy is a beginner: usually a weak, varying fraction, sometimes it overshoots
## to the other side of the target ("over-corrects"), sometimes it barely moves ("didn't notice").
## After a LOST shell (crude_lost) the number is instead how much of the lost shot's power is cut:
## big, but blind to where the target is. A `veteran` (see is_veteran) corrects harder. `nominal`
## skips the dice (used for safety checks).
static func correction_factor(prof: Dictionary, rng: Rng, lost: bool, nominal: bool = false, veteran: bool = false) -> int:
	if crude_lost(prof, lost):
		if nominal:
			return ((prof["lost_cut_min"] as int) + (prof["lost_cut_max"] as int)) / 2
		return rng.range_int(prof["lost_cut_min"], prof["lost_cut_max"])
	var over: int = prof["overshoot"]
	var ignore: int = prof["ignore"]
	if nominal or (over == 0 and ignore == 0 and prof["corr_min"] == prof["corr_max"]):
		return prof["correction"]
	var roll: int = rng.range_int(0, 999)
	if roll < over:
		return rng.range_int(prof["overshoot_min"], prof["overshoot_max"])
	if roll < over + ignore:
		return rng.range_int(0, prof["ignore_max"])
	if veteran:
		return rng.range_int(prof["veteran_corr_min"], prof["veteran_corr_max"])
	return rng.range_int(prof["corr_min"], prof["corr_max"])


## The power the AI will really send for `plan`: the exact solution with the round's bias and
## `noise` (per-mille) added, or, after an earlier shot at the same target, moved from that
## shot's power by `factor` (see correction_factor; -1 = the level's nominal correction).
## `cut` is true after a lost shell on a level with a crude reaction: `factor` is then a power cut.
static func _with_error(plan: Dictionary, prof: Dictionary, bias: int, noise: int, factor: int = -1,
		cut: bool = false) -> int:
	var power: int = plan["power"]
	if plan["corrected"]:
		var prev: int = plan["prev_power"]
		if cut:
			return prev * (1000 - factor) / 1000 * (1000 + noise) / 1000
		var f: int = factor if factor >= 0 else (prof["correction"] as int)
		power = prev + (power - prev) * f / 1000
		return power * (1000 + noise) / 1000
	return power * (1000 + bias + noise) / 1000


## The power finalize() sends before the random jitter (what the shot is "centred" on).
static func expected_power(sit: AiSituation, plan: Dictionary) -> int:
	var bias: int = round_bias(sit.state, sit.me.id, sit.prof)
	var factor: int = -1
	var lost: bool = sit.corr.get("lost", false)
	if plan["corrected"]:
		factor = correction_factor(sit.prof, null, lost, true)
	return clampi(_with_error(plan, sit.prof, bias, 0, factor, crude_lost(sit.prof, lost)),
			SimConstants.MIN_POWER, SimConstants.MAX_POWER)


# --- moving ----------------------------------------------------------------------------------------------

## Walks out of a spot from which no shot reaches the target, if a short walk fixes that.
## The candidate is judged with the same solver the next call will use from the new spot,
## so a move is never repeated. (Capped so a turn stays within 3 calls: see _prepare.)
static func _maybe_move(sit: AiSituation) -> Dictionary:
	var me: TankState = sit.me
	if sit.prof["move"] == AiProfile.MOVE_NEVER or sit.direct["ok"]:
		return {}
	if me.fuel <= 0 and me.stock_of("fuel_cell") <= 0:
		return {}
	if me.has_shield() and me.repulsor_charge > 0:
		return {}
	var steps: Array[int] = [-40, 40, -80, 80]
	if sit.prof["move"] == AiProfile.MOVE_TO_IMPROVE:
		steps = [-40, 40, -80, 80, -130, 130]
	var spent_from: int = AimSolver.model_count
	for dx: int in steps:
		if AimSolver.model_count - spent_from > MOVE_SEARCH_FLIGHTS:
			break
		var dest: Vector2i = _walk_dest(sit, dx)
		if dest.x == me.x:
			continue
		var dir: int = 1 if sit.target.x >= dest.x else -1
		var ctx: AimSolver.Ctx = AimSolver.new_ctx(sit.state, me.id, dest.x, dest.y, sit.ctx.wind, dir, sit.flight)
		ctx.row = sit.ctx.row
		var plan: Dictionary = AimSolver.solve_direct(ctx, sit.target.x, sit.a0)
		if plan["ok"]:
			return {"kind": "move", "tank": me.id, "dx": dx}
	return {}


## Where a walk of `dx` cells would end, following the rules of Simulation._apply_move (fuel,
## map edge, other tanks, climbs over MAX_CLIMB). A walk with a drop that could hurt is
## treated as not moving.
static func _walk_dest(sit: AiSituation, dx: int) -> Vector2i:
	var me: TankState = sit.me
	var dir: int = 1 if dx > 0 else -1
	var fuel_units: int = me.fuel + me.stock_of("fuel_cell") * (ItemDefs.get_def("fuel_cell")["amount"] as int)
	var x: int = me.x
	var y: int = me.y
	var drop: int = 0
	var half: int = SimConstants.TANK_W / 2
	for _i: int in range(absi(dx)):
		var nx: int = x + dir
		if nx - half < 0 or nx + half > sit.state.terrain.width or fuel_units <= 0:
			break
		var blocked: bool = false
		for o: TankState in sit.state.tanks:
			if o.alive and o.id != me.id and absi(o.x - nx) < SimConstants.TANK_W:
				blocked = true
		if blocked:
			break
		var ny: int = sit.flight.rest_y(nx)
		if y - ny > SimConstants.MAX_CLIMB:
			break
		if ny > y:
			drop += ny - y
		fuel_units -= 1
		x = nx
		y = ny
	if drop > SimConstants.FALL_SAFE:
		return Vector2i(me.x, me.y)
	return Vector2i(x, y)
