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


static func choose_and_plan(sit: AiSituation) -> Dictionary:
	for id: String in _candidates(sit):
		var plan: Dictionary = _plan_for(sit, id)
		if not plan.is_empty() and plan["ok"]:
			return plan
	# Nothing aimed cleanly: shoot the best-effort plain solution with a basic missile.
	var basic: String = "pulse_missile" if sit.owns("pulse_missile") else "spark_dart"
	var fallback: Dictionary = _plain_plan(sit, basic, sit.target.x, "pulse_missile", false)
	fallback["ok"] = false
	return fallback


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
	out.append("spark_dart")
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
	if not _has_damage_weapon(sit):
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


## True when the target sits in a hollow: the ground 50 cells towards us is clearly higher.
static func _in_pit(sit: AiSituation) -> bool:
	var rim_x: int = clampi(sit.target.x - sit.ctx.dir * 50, 0, sit.state.terrain.width - 1)
	return sit.flight.surface(rim_x) <= sit.target.y - PIT_DEPTH


# --- planning per weapon ------------------------------------------------------------------------------

static func _plan_for(sit: AiSituation, id: String) -> Dictionary:
	var def: Dictionary = WeaponDefs.get_def(id)
	var behavior: String = def.get("behavior", "")
	match behavior:
		"explode", "splitter", "dirt":
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


static func _plan(id: String, base: Dictionary, corrected: bool, prev_power: int) -> Dictionary:
	var ok: bool = false
	if base.get("verified", false):
		ok = base["hit"] or absi(base["real_err"] as int) <= AimSolver.TOL_ACCEPT
	else:
		ok = absi(base["err"] as int) <= AimSolver.TOL_ACCEPT
	return {"weapon": id, "angle": base["angle"], "power": base["power"], "ok": ok,
			"corrected": corrected, "prev_power": prev_power}


## Ordinary arc onto `aim_x`. With `use_corr` the aim is shifted by the last miss at this
## target (when there is one and the weapon's flight matches).
static func _plain_plan(sit: AiSituation, id: String, aim_x: int, phys: String, use_corr: bool) -> Dictionary:
	if use_corr and not sit.corr.is_empty():
		var corrected: Dictionary = _corrected_plan(sit, id, phys)
		if not corrected.is_empty():
			return corrected
	var base: Dictionary = sit.direct if aim_x == sit.target.x else \
			AimSolver.solve_direct(sit.ctx, aim_x, sit.a0)
	var checked: Dictionary = AimSolver.verify(sit.ctx, base, phys, sit.target.id, aim_x)
	return _plan(id, checked, false, 0)


## Same angle as the last shot, aimed so that last shot's observed error is cancelled.
static func _corrected_plan(sit: AiSituation, id: String, phys: String) -> Dictionary:
	var aim_x: int = sit.target.x - (sit.corr["d"] as int)
	var plan: Dictionary = AimSolver.solve_power(sit.ctx, sit.corr["angle"], aim_x)
	if absi(plan["err"] as int) > AimSolver.TOL_ACCEPT:
		return {}
	var checked: Dictionary = AimSolver.verify(sit.ctx, plan, phys, sit.target.id, aim_x)
	var out: Dictionary = _plan(id, checked, true, sit.corr["power"])
	if not out["ok"]:
		return {}
	return out


static func _plan_well(sit: AiSituation, id: String) -> Dictionary:
	# Land on the target itself: the well then bends our later shells in onto it.
	var base: Dictionary = AimSolver.verify(sit.ctx, sit.direct, "pulse_missile", sit.target.id, sit.target.x)
	return _plan(id, base, false, 0)


static func _plan_roller(sit: AiSituation, id: String, def: Dictionary) -> Dictionary:
	if not _in_pit(sit):
		return {}
	for off: int in [35, 60]:
		var aim_x: int = clampi(sit.target.x - sit.ctx.dir * off, 0, sit.state.terrain.width - 1)
		var plan: Dictionary = AimSolver.solve_direct(sit.ctx, aim_x, sit.a0)
		if not plan["ok"]:
			continue
		var rolled: Dictionary = RollerBehavior.roll(sit.state, plan["impact_x"], def["speed"], def["max_roll"],
				PackedInt32Array())
		if not rolled["started"]:
			continue
		if rolled["contact"] or absi((rolled["x"] as int) - sit.target.x) <= 14:
			var checked: Dictionary = AimSolver.verify(sit.ctx, plan, "pulse_missile", sit.target.id, aim_x)
			return _plan(id, checked, false, 0)
	return {}


## Only for a target no lob reaches: bore into the hill and let the tunnel carry on.
static func _plan_tunneler(sit: AiSituation, id: String, def: Dictionary) -> Dictionary:
	if sit.direct["ok"]:
		return {}
	var plan: Dictionary = AimSolver.solve_direct(sit.ctx, sit.target.x, sit.a0, AimSolver.MODE_TUNNEL,
			def["length"], AimSolver.TOL_ACCEPT + 6)
	if not plan["ok"]:
		return {}
	var checked: Dictionary = AimSolver.verify(sit.ctx, plan, "pulse_missile", sit.target.id, sit.target.x,
			AimSolver.MODE_TUNNEL, def["length"])
	return _plan(id, checked, false, 0)


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
	var plan: Dictionary = AimSolver.solve_direct(sit.ctx, best_x, sit.a0)
	if not plan["ok"]:
		return {}
	var checked: Dictionary = AimSolver.verify(sit.ctx, plan, "pulse_missile", sit.target.id, best_x)
	return _plan(id, checked, false, 0)


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
