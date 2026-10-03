@warning_ignore_start("integer_division")
class_name AiWeapons
extends RefCounted
## Weapon choice and the aim for each kind of weapon.
##
## choose_and_plan() builds an ordered list of weapons the level would like to use right now
## (see _candidates) and returns the plan of the first one whose aim works out:
##   Easy    a random basic missile.
##   Normal  the biggest blast it owns (forgiving of its own misses); a Seeker in strong
##           wind; a Prism Splitter at long range.
##   Hard    the right tool: Bore Shell when a hill blocks every lob, a roller for a target in
##           a pit, a Seeker in strong wind, otherwise the cheapest missile that does the job.
##   Expert  all of that plus: Static Burst on a shielded target, Photon Lance against a
##           repulsor or in a gale, Singularity Seed to bend shells onto a far target, Riptide
##           Anchor to drag a target off a ledge, a Splitter against clustered enemies, and
##           the cheapest weapon that actually kills.
## A plan is {weapon, angle, power, ok, corrected, prev_power, [beam]}; AiPlayer then adds the
## human-like error. Plain-flight weapons share one aim solution (a splitter's centre child
## and a roller or bore shell all fly the ordinary arc until they hit the ground).

## Weapons that fly the ordinary arc and whose impact point is a good "last miss" reading.
const CORRECTABLE: PackedStringArray = ["explode", "splitter", "dirt"]
const PIT_DEPTH: int = 25
const CLUSTER_RADIUS: int = 110
## Ticks a roller is followed when judging whether it reaches the target.
const ROLL_LOOKAHEAD: int = 100
## Beyond this many real traces in one decision, plans are no longer confirmed by a trace
## (the hard limit is AimSolver.TRACE_BUDGET).
const SOFT_TRACE_CAP: int = 8
## A Seeker steers itself onto the target, so its aim may be this far off (cells).
const SEEKER_TOL: int = 40
## Launch angle (tenths of a degree) tried first when a teammate blocks the usual arc.
const ALLY_LOB_ANGLE: int = 780


static func choose_and_plan(sit: AiSituation) -> Dictionary:
	# The first weapon (in the level's order of preference) whose aim works out AND whose blast
	# does not reach the shooter or a teammate wins. If every option hurts us, the best
	# "enemy damage - 1.5 x own damage" is returned (with self_dmg > 0); the caller decides
	# whether that is still worth firing.
	var best: Dictionary = {}
	var best_score: int = 0
	for id: String in _candidates(sit):
		var plan: Dictionary = plan_for(sit, id)
		if plan.is_empty() or not plan["ok"]:
			continue
		var score: int = _rate(sit, plan, id)
		if plan["self_dmg"] == 0:
			return plan
		if best.is_empty() or score > best_score:
			best = plan
			best_score = score
	if not best.is_empty():
		return best
	# Nothing aimed cleanly: shoot the best-effort plain solution with a basic missile.
	var basic: String = "pulse_missile" if sit.owns("pulse_missile") else "spark_dart"
	var fallback: Dictionary = _plain_plan(sit, basic, sit.target.x, "pulse_missile", false)
	fallback["ok"] = false
	_rate(sit, fallback, basic)
	return fallback


# --- self harm ---------------------------------------------------------------------------------------------

## Fills plan["self_dmg"] (damage to the shooter and its teammates), plan["enemy_dmg"] and
## returns enemy_dmg - 1.5 x self_dmg. The blast is judged at the planned impact point with the
## same Damage formula as the simulation, widened by the error this level will add to the shot.
static func _rate(sit: AiSituation, plan: Dictionary, id: String) -> int:
	var h: Dictionary = estimate_harm(sit, plan, id)
	plan["self_dmg"] = h["self"]
	plan["enemy_dmg"] = h["enemy"]
	return (h["enemy"] as int) - 3 * (h["self"] as int) / 2


static func estimate_harm(sit: AiSituation, plan: Dictionary, id: String) -> Dictionary:
	var def: Dictionary = WeaponDefs.get_def(id)
	var behavior: String = def.get("behavior", "")
	var out: Dictionary = {"self": 0, "enemy": 0}
	var radius: int = def.get("r", 0)
	var dmg: int = def.get("dmg", 0)
	var spread: int = 0
	var impact: Vector2i = Vector2i(-1, -1)
	match behavior:
		"explode", "seeker", "static":
			impact = _impact(sit, plan, true)
		"splitter":
			impact = _impact(sit, plan, true)
			spread = 48  # the children fan out around the middle one
		"roller":
			impact = _impact(sit, plan, false)
			spread = 30
		"tunneler":
			# The bore comes out beside the target (that is what the plan was searched for).
			var t: TankState = sit.target
			impact = Vector2i(t.x - sit.ctx.dir * (SimConstants.TANK_W / 2), t.y - SimConstants.TANK_H / 2)
		"beam":
			out["enemy"] = def["dmg"]
			return out
		_:
			out["enemy"] = 1  # dirt, wells, anchors: no blast worth counting
			return out
	if impact.x < 0:
		return out  # the shell flies off the map: nothing explodes
	var prof: Dictionary = sit.prof
	var err_pm: int = 2 * ((prof["bias_max"] as int) + 2 * (prof["noise"] as int))
	var reach: int = absi(impact.x - sit.me.x)
	var margin: int = reach * err_pm / 1000 + spread
	if sit.target.has_shield():
		margin += SimConstants.SHIELD_RADIUS  # the shell stops at the bubble, nearer than the box
	for t: TankState in sit.state.tanks:
		if not t.alive:
			continue
		var d: int = Damage.distance_to_tank(impact.x, impact.y, t)
		if t.id == sit.me.id or t.team == sit.me.team:
			out["self"] = (out["self"] as int) + Damage.amount(maxi(0, d - margin), radius, dmg)
		else:
			out["enemy"] = (out["enemy"] as int) + Damage.amount(d, radius, dmg)
	return out


## Where the planned shell explodes: its model flight, ending (when `at_target`) as it reaches the
## top of the target's hit box, like the real shell would. (-1, -1) if it leaves the map.
static func _impact(sit: AiSituation, plan: Dictionary, at_target: bool) -> Vector2i:
	var row: int = sit.target.y - SimConstants.TANK_H if at_target else -1
	# The shot actually sent carries the level's bias (and any partial correction): judge that one.
	var power: int = AiPlayer.expected_power(sit, plan)
	# Safety is judged against the real wind, not the wind the level believes in.
	sit.flight.fly_shot(sit.me.x, sit.me.y, plan["angle"], power, sit.state.wind, AimSolver.MODEL_TICKS, row)
	AimSolver.model_count += 1
	# A muzzle inside somebody else's shield bubble: the shell bursts on the spot.
	var mx: int = FixedMath.to_cell(sit.flight.muzzle_px)
	var my: int = FixedMath.to_cell(sit.flight.muzzle_py)
	for t: TankState in sit.state.tanks:
		if t.alive and t.id != sit.me.id and t.has_shield():
			var dx: int = mx - t.x
			var dy: int = my - (t.y - SimConstants.SHIELD_CENTER_DY)
			if dx * dx + dy * dy <= SimConstants.SHIELD_RADIUS * SimConstants.SHIELD_RADIUS:
				return Vector2i(mx, my)
	if sit.flight.r_reason != AiFlight.REASON_TERRAIN:
		return Vector2i(-1, -1)
	return Vector2i(sit.flight.r_x, sit.flight.r_y)


# --- weapon preferences -----------------------------------------------------------------------------

static func _candidates(sit: AiSituation) -> Array[String]:
	var out: Array[String] = []
	match sit.level:
		SimConstants.CTRL_EASY:
			_easy(sit, out)
		SimConstants.CTRL_NORMAL:
			_normal(sit, out)
		_:
			_expert_or_hard(sit, out)
	if not out.has("spark_dart"):
		out.append("spark_dart")  # the small blast: the last resort when the others would hurt us
	return out


static func _add_if_owned(sit: AiSituation, out: Array[String], id: String) -> void:
	if sit.owns(id) and not out.has(id):
		out.append(id)


static func _easy(sit: AiSituation, out: Array[String]) -> void:
	var pool: Array[String] = []
	for id: String in ["pulse_missile", "hyperpulse"]:
		if sit.owns(id):
			pool.append(id)
	if not pool.is_empty():
		out.append(pool[sit.rng.range_int(0, pool.size() - 1)])


static func _normal(sit: AiSituation, out: Array[String]) -> void:
	var hp: int = AiTargets.hp_eff(sit.target)
	if hp >= 70 and sit.dist >= 400:
		_add_if_owned(sit, out, "nova_core")
	if absi(sit.state.wind) >= 50 and sit.target.id == sit.nearest_id:
		_add_if_owned(sit, out, "seeker")
	# At long range a spread of shells forgives some of its own error.
	if sit.dist >= 700:
		_add_if_owned(sit, out, "prism_splitter")
	if hp > 55:
		_add_if_owned(sit, out, "hyperpulse")
	_add_if_owned(sit, out, "pulse_missile")
	_add_if_owned(sit, out, "hyperpulse")


static func _expert_or_hard(sit: AiSituation, out: Array[String]) -> void:
	var expert: bool = sit.level == SimConstants.CTRL_EXPERT
	var t: TankState = sit.target
	if expert:
		if t.has_shield() and t.shield_hp >= 15:
			_add_if_owned(sit, out, "static_burst")
		if t.repulsor_charge > 20:
			_add_if_owned(sit, out, "photon_lance")
		if sit.state.wells.is_empty() and sit.dist >= 350 and t.health >= 60:
			_add_if_owned(sit, out, "singularity_seed")
		if sit.dist > 220:
			_add_if_owned(sit, out, "riptide_anchor")
	if absi(sit.state.wind) >= 90:
		_add_if_owned(sit, out, "photon_lance")
	if not sit.direct["ok"]:
		_add_if_owned(sit, out, "deep_bore")
		_add_if_owned(sit, out, "bore_shell")
	if _in_pit(sit):
		_add_if_owned(sit, out, "heavy_orb")
		_add_if_owned(sit, out, "glide_orb")
	if absi(sit.state.wind) >= 60 and t.id == sit.nearest_id:
		_add_if_owned(sit, out, "seeker")
	if expert and _clustered(sit):
		_add_if_owned(sit, out, "prism_cascade")
		_add_if_owned(sit, out, "prism_splitter")
	_plain_by_health(sit, out, expert)
	# Burying a tank makes its next shot explode in its own barrel; worth a try when there is
	# no real missile in the rack (a Spark Dart only scratches a healthy target).
	if not _has_damage_weapon(sit) and t.health >= 60 and sit.rng.chance(1, 3):
		_add_if_owned(sit, out, "landslide")
		_add_if_owned(sit, out, "mound_mortar")


## Explosive missiles ordered by what the target's health calls for.
static func _plain_by_health(sit: AiSituation, out: Array[String], expert: bool) -> void:
	var hp: int = AiTargets.hp_eff(sit.target)
	# Cheapest first; the first one that kills leads. Hard does not bother with the spark dart.
	var ladder: Array[String] = ["spark_dart", "pulse_missile", "hyperpulse", "nova_core", "supernova"]
	if not expert:
		ladder.remove_at(0)
	for id: String in ladder:
		if sit.owns(id) and (WeaponDefs.get_def(id)["dmg"] as int) >= hp:
			_add_if_owned(sit, out, id)
			break
	# No kill available: the strongest cheap missile.
	if hp > 55:
		_add_if_owned(sit, out, "hyperpulse")
	_add_if_owned(sit, out, "pulse_missile")
	_add_if_owned(sit, out, "hyperpulse")
	_add_if_owned(sit, out, "nova_core")


static func _has_damage_weapon(sit: AiSituation) -> bool:
	for id: String in ["pulse_missile", "hyperpulse", "nova_core", "supernova", "prism_splitter", "seeker"]:
		if sit.owns(id):
			return true
	return false


static func _clustered(sit: AiSituation) -> bool:
	for e: TankState in sit.enemies:
		if e.id != sit.target.id and absi(e.x - sit.target.x) <= CLUSTER_RADIUS:
			return true
	return false


## True when the target sits in a hollow: the ground 70 cells towards us is clearly higher.
static func _in_pit(sit: AiSituation) -> bool:
	var rim_x: int = clampi(sit.target.x - sit.ctx.dir * 70, 0, sit.state.terrain.width - 1)
	return sit.flight.surface(rim_x) <= sit.target.y - PIT_DEPTH


# --- planning per weapon ------------------------------------------------------------------------------

static func plan_for(sit: AiSituation, id: String) -> Dictionary:
	var def: Dictionary = WeaponDefs.get_def(id)
	var behavior: String = def.get("behavior", "")
	match behavior:
		"explode", "splitter", "dirt", "love":
			return _plain_plan(sit, id, sit.target.x, "pulse_missile", true)
		"static":
			return _plain_plan(sit, id, sit.target.x, "pulse_missile", false)
		"well":
			return _plan_well(sit, id)
		"seeker":
			return _plain_plan(sit, id, sit.target.x, id, false)
		"roller":
			return _plan_roller(sit, id, def)
		"tunneler":
			return _plan_tunneler(sit, id, def)
		"beam":
			return _plan_beam(sit, id)
		"anchor":
			return _plan_anchor(sit, id, def)
	return {}


## Confirms a plan with the real trace when the model might be wrong (AimSolver.needs_verify).
static func _check(sit: AiSituation, plan: Dictionary, phys: String, aim_x: int,
		mode: int = AimSolver.MODE_LAND, extra: int = 0) -> Dictionary:
	if AimSolver.trace_count >= SOFT_TRACE_CAP or not AimSolver.needs_verify(sit.ctx, sit.target.id, aim_x, phys):
		return plan
	return AimSolver.verify(sit.ctx, plan, phys, sit.target.id, aim_x, mode, extra)


static func _plan(id: String, base: Dictionary, corrected: bool, prev_power: int,
		tol: int = AimSolver.TOL_ACCEPT) -> Dictionary:
	var ok: bool = false
	if base.get("ally_hit", false):
		ok = false
	elif base.has("tunnel_ok"):
		ok = base["tunnel_ok"]
	elif base.get("verified", false):
		ok = base["hit"] or absi(base["real_err"] as int) <= tol
	else:
		ok = absi(base["err"] as int) <= tol
	return {"weapon": id, "angle": base["angle"], "power": base["power"], "ok": ok,
			"corrected": corrected, "prev_power": prev_power}


## Ordinary arc onto `aim_x`. With `use_corr` the aim is shifted by the last miss at this
## target (when there is one and the weapon's flight matches).
static func _plain_plan(sit: AiSituation, id: String, aim_x: int, phys: String, use_corr: bool) -> Dictionary:
	var tol: int = SEEKER_TOL if phys == "seeker" else AimSolver.TOL_ACCEPT
	if use_corr and not sit.corr.is_empty():
		var corrected: Dictionary = _corrected_plan(sit, id, phys)
		if not corrected.is_empty():
			return corrected
	var key: String = "%d/%s" % [aim_x, phys]
	if not sit.memo.has(key):
		var base: Dictionary = sit.direct if aim_x == sit.target.x else \
				AimSolver.solve_direct(sit.ctx, aim_x, sit.a0)
		var checked: Dictionary = _check(sit, base, phys, aim_x)
		if checked.get("ally_hit", false):
			# A teammate stands in that arc: try a high lob over it.
			var lob: Dictionary = AimSolver.solve_direct(sit.ctx, aim_x, ALLY_LOB_ANGLE)
			checked = _check(sit, lob, phys, aim_x)
		sit.memo[key] = checked
	return _plan(id, sit.memo[key], false, 0, tol)


## Same angle as the last shot, aimed so that last shot's observed error is cancelled.
static func _corrected_plan(sit: AiSituation, id: String, phys: String) -> Dictionary:
	var key: String = "corr/%s" % phys
	if not sit.memo.has(key):
		var aim_x: int = sit.target.x - (sit.corr["d"] as int)
		var plan: Dictionary = AimSolver.solve_power(sit.ctx, sit.corr["angle"], aim_x)
		var checked: Dictionary = {}
		if absi(plan["err"] as int) <= AimSolver.TOL_ACCEPT:
			checked = _check(sit, plan, phys, aim_x)
		sit.memo[key] = checked
	var cached: Dictionary = sit.memo[key]
	if cached.is_empty():
		return {}
	var out: Dictionary = _plan(id, cached, true, sit.corr["power"])
	return out if out["ok"] else {}


static func _plan_well(sit: AiSituation, id: String) -> Dictionary:
	# Land on the target itself: the well then bends our later shells in onto it.
	var base: Dictionary = _check(sit, sit.direct, "pulse_missile", sit.target.x)
	return _plan(id, base, false, 0)


static func _plan_roller(sit: AiSituation, id: String, def: Dictionary) -> Dictionary:
	if not _in_pit(sit):
		return {}
	var saved_row: int = sit.ctx.row
	sit.ctx.row = -1  # a roller is judged by where it touches the ground
	var result: Dictionary = {}
	for off: int in [25, 45, 75]:
		var aim_x: int = clampi(sit.target.x - sit.ctx.dir * off, 0, sit.state.terrain.width - 1)
		# Would a roller put down on this column roll into the target? (cheap: no flight yet)
		var rolled: Dictionary = RollerBehavior.roll(sit.state, aim_x, def["speed"],
				mini(def["max_roll"] as int, ROLL_LOOKAHEAD), PackedInt32Array())
		if not rolled["started"]:
			continue
		if not (rolled["contact"] or absi((rolled["x"] as int) - sit.target.x) <= 14):
			continue
		var plan: Dictionary = AimSolver.solve_direct(sit.ctx, aim_x, sit.a0)
		if plan["ok"]:
			result = _plan(id, _check(sit, plan, "pulse_missile", aim_x), false, 0)
			break
	sit.ctx.row = saved_row
	return result


## Only for a target no lob reaches: bore into the hill and let the tunnel carry on. After a
## first bore at this target the same angle is kept and the power corrected, like any bracket.
static func _plan_tunneler(sit: AiSituation, id: String, def: Dictionary) -> Dictionary:
	if sit.direct["ok"]:
		return {}
	if not sit.corr.is_empty() and _last_was_tunneler(sit):
		var a_dir: int = sit.corr["angle"] if sit.ctx.dir > 0 else SimConstants.MAX_ANGLE - (sit.corr["angle"] as int)
		var same: Dictionary = AimSolver.solve_tunnel(sit.ctx, sit.target.x, sit.target.y, def["length"],
				def["r"], [a_dir] as Array[int])
		if same["tunnel_ok"]:
			return _plan(id, same, true, sit.corr["power"], def["r"])
	var plan: Dictionary = AimSolver.solve_tunnel(sit.ctx, sit.target.x, sit.target.y, def["length"], def["r"])
	if not plan["tunnel_ok"]:
		return {}
	return _plan(id, plan, false, 0, def["r"])


static func _last_was_tunneler(sit: AiSituation) -> bool:
	var last: Dictionary = WeaponDefs.get_def(Catalog.id_at(sit.me.last_fire_weapon))
	return last.get("behavior", "") == "tunneler"


## Photon Lance: aim the straight line at the target's middle; it only counts if the first
## thing the beam meets is that tank.
static func _plan_beam(sit: AiSituation, id: String) -> Dictionary:
	var t: TankState = sit.target
	var angle: int = AimSolver.beam_angle(sit.me.x, sit.me.y, t.x, t.y - SimConstants.TANK_H / 2)
	var tr: Dictionary = AimSolver.counted_beam(sit.state, sit.me.id, angle, id)
	if tr.is_empty() or (tr["hit_tank"] as int) != t.id:
		return {}
	return {"weapon": id, "angle": angle, "power": SimConstants.DEFAULT_POWER, "ok": true,
			"corrected": false, "prev_power": 0, "beam": true}


## Riptide Anchor: find an impact column that drags the target far enough downhill to hurt.
static func _plan_anchor(sit: AiSituation, id: String, def: Dictionary) -> Dictionary:
	var t: TankState = sit.target
	if absi(sit.me.x - t.x) <= (def["pull_r"] as int) + 40:
		return {}
	var best_x: int = -1
	var best_dmg: int = 19
	for off: int in [-120, -80, -40, 40, 80, 120]:
		var ix: int = clampi(t.x + off, 20, sit.state.terrain.width - 20)
		if absi(sit.me.x - ix) <= (def["pull_r"] as int) + 20:
			continue
		var dmg: int = _drag_fall_damage(sit, t, ix, def["max_pull"])
		if dmg > best_dmg:
			best_dmg = dmg
			best_x = ix
	if best_x < 0:
		return {}
	var saved_row: int = sit.ctx.row
	sit.ctx.row = -1  # the anchor needs a ground impact at that column
	var plan: Dictionary = AimSolver.solve_direct(sit.ctx, best_x, sit.a0)
	var result: Dictionary = {}
	if plan["ok"]:
		result = _plan(id, _check(sit, plan, "pulse_missile", best_x), false, 0)
	sit.ctx.row = saved_row
	return result


## Fall damage the target would take if it were dragged towards column `ix` (mirrors
## AnchorBehavior: one cell per step, climbs of more than 6 stop it, drops add up).
static func _drag_fall_damage(sit: AiSituation, t: TankState, ix: int, max_pull: int) -> int:
	var dir: int = 1 if ix > t.x else -1
	var x: int = t.x
	var y: int = t.y
	var drop: int = 0
	var half: int = SimConstants.TANK_W / 2
	for _i: int in range(mini(absi(ix - t.x), max_pull)):
		var nx: int = x + dir
		if nx - half < 0 or nx + half > sit.state.terrain.width:
			break
		var ny: int = sit.flight.rest_y(nx)
		if y - ny > 6:
			break
		if ny > y:
			drop += ny - y
		x = nx
		y = ny
	if drop <= SimConstants.FALL_SAFE or t.stock_of("drift_chute") > 0:
		return 0
	return (drop - SimConstants.FALL_SAFE) / SimConstants.FALL_DMG_DIV
