@warning_ignore_start("integer_division")
class_name AimSolver
extends RefCounted
## Finds the launch angle and power that put a shell on a chosen x position.
##
## Plain-language summary of the approach:
##  1. Pick an angle, preferring a 30..70 degree lob towards the target (a little random
##     variety so tanks do not all fire at exactly 45).
##  2. Find the power that lands the shell on the aim point. A vacuum formula gives a first
##     guess, then a bracketing secant search refines it. The flights are flown by AiFlight, a
##     fast copy of the shell physics, with the wind the AI *believes* in.
##  3. If no power works at that angle (a hill is in the way, or the target is out of
##     range), try steeper angles, which clear hills. A plan only counts as good if it is
##     also robust: a hair more or less power must still land near the aim point.
##  4. When the cheap model could be wrong (a teammate in the line of fire), confirm the
##     winner with the real Ballistics.trace; if reality disagrees, shift the aim point by the
##     observed difference and search again, at most a few times (verify()).
## The human-like mistakes (bias, noise, correcting from the last miss) are NOT added here;
## AiPlayer adds them on top of the exact answer this class returns.
##
## Everything is integer maths. Real traces are counted in `trace_count` (reset per decision)
## and refused once TRACE_BUDGET is reached, and model flights are counted in `model_count`,
## so a decision always has bounded cost.

const TRACE_BUDGET: int = 48
## A search or verification flight is cut off after this many ticks (the longest real lob,
## 86 degrees at full power, is about 230); a shell caught orbiting a gravity well would
## otherwise burn the whole budget.
const MODEL_TICKS: int = 420
const VERIFY_TICKS: int = 420
## The model landing is "good enough" within this many cells of the aim point.
const TOL_ACCEPT: int = 14
const TOL_SEARCH: int = 3
const VERIFY_TOL: int = 6
const MAX_VERIFY: int = 2  # real traces to confirm one plan
const MAX_EVALS: int = 8
## A plan is only preferred if the shell still comes down near the aim point when the power is
## off by +-ROBUST_PM per-mille: this avoids shots that just clear a crest and would
## land far short if the power were a hair lower.
const ROBUST_PM: int = 8
## Model flights one angle search (solve_direct) may spend (about 0.3 ms each): a hopeless
## target (out of range, walled in) stops the search instead of grinding through every angle.
const MODEL_BUDGET: int = 32
const ROBUST_TOL: int = 45

## What the power search measures.
const MODE_LAND: int = 0  # where the shell comes down
const MODE_TUNNEL: int = 1  # where a tunneler's bore ends (extra = bore length)

## Steeper alternatives tried (tenths of a degree away from the horizontal) when the preferred
## angle cannot reach the aim point.
const FALLBACK_ANGLES: Array[int] = [640, 720, 800, 860, 340]
## Angles tried for a tunneler (flat enough that the bore runs on towards the target).
const TUNNEL_ANGLES: Array[int] = [200, 340]
## A coarse bore that ends farther than this from the target is not refined.
const TUNNEL_PROMISING: int = 90

## Debug counters, read by the tests.
static var trace_count: int = 0
static var model_count: int = 0


## Everything one aiming session needs. `sx`, `sy` is where the shooter stands (it can differ
## from the real tank when the AI is judging a walk), `wind` the believed wind, `dir` +1 when
## the target is to the right and -1 to the left.
class Ctx extends RefCounted:
	var state: MatchState
	var me: int = 0
	var sx: int = 0
	var sy: int = 0
	var wind: int = 0
	var dir: int = 1
	var flight: AiFlight = null
	## x where the model's last evaluated shot came down (not the tunnel end).
	var impact_x: int = 0
	## Row (y) a shot is also judged at: the model ends a flight when the shell, on its way
	## down, reaches it, if that happens before it hits the ground. -1 = judge by the ground
	## only. For a tank target this is the middle of its hit box, so craters and pits around
	## the target do not fool the aim (the shell is meant to pass through the box, not to dig in
	## below it).
	var row: int = -1


static func reset_budget() -> void:
	trace_count = 0
	model_count = 0


static func traces_left() -> int:
	return TRACE_BUDGET - trace_count


static func new_ctx(state: MatchState, me: int, sx: int, sy: int, wind: int, dir: int,
		flight: AiFlight) -> Ctx:
	var c := Ctx.new()
	c.state = state
	c.me = me
	c.sx = sx
	c.sy = sy
	c.wind = wind
	c.dir = dir
	c.flight = flight
	return c


## Real shell trace, counted against the budget. Returns {} when the budget is used up.
static func counted_trace(state: MatchState, me: int, angle: int, power: int, weapon_id: String,
		wind: int) -> Dictionary:
	if trace_count >= TRACE_BUDGET:
		return {}
	trace_count += 1
	return Ballistics.trace(state, me, angle, power, weapon_id, wind, VERIFY_TICKS)


## Real beam trace, counted against the budget. Returns {} when the budget is used up.
static func counted_beam(state: MatchState, me: int, angle: int, weapon_id: String) -> Dictionary:
	if trace_count >= TRACE_BUDGET:
		return {}
	trace_count += 1
	return Ballistics.trace_beam(state, me, angle, WeaponDefs.get_def(weapon_id))


## Actual launch angle (0..1800) for a "dir-space" angle 0..900 measured from the horizontal
## towards the target.
static func actual_angle(ctx: Ctx, a_dir: int) -> int:
	return a_dir if ctx.dir > 0 else SimConstants.MAX_ANGLE - a_dir


static func _objective(ctx: Ctx, angle: int, power: int, mode: int, extra: int) -> int:
	var fl: AiFlight = ctx.flight
	fl.fly_shot(ctx.sx, ctx.sy, angle, power, ctx.wind, MODEL_TICKS, -1 if mode == MODE_TUNNEL else ctx.row)
	model_count += 1
	ctx.impact_x = fl.r_x
	if mode == MODE_TUNNEL and fl.r_reason == AiFlight.REASON_TERRAIN:
		return TunnelerBehavior.bore_end(ctx.state, fl.r_px, fl.r_py, fl.r_vx, fl.r_vy, extra).x
	return fl.r_x


## Vacuum-flight estimate of the power needed to cover the distance to `aim_x` at `angle`.
static func _initial_power(ctx: Ctx, angle: int, aim_x: int) -> int:
	var a_dir: int = angle if ctx.dir > 0 else SimConstants.MAX_ANGLE - angle
	var reach: int = maxi(1, ctx.dir * (aim_x - ctx.sx))
	var sin2: int = maxi(6000, FixedMath.sin10(2 * a_dir))
	# range = v^2 sin(2a) / g with v = power * 17 / 1000  =>  power^2 = range * 1e6 * g / (289 sin2a)
	var p2: int = reach * 1_000_000 * SimConstants.GRAVITY / (289 * sin2)
	return clampi(FixedMath.isqrt(p2), 1, SimConstants.MAX_POWER)


## Searches the power that lands (or, in tunnel mode, bores) on `aim_x` at a fixed `angle`.
## Returns {power, err, land_x, impact_x, angle}; err is signed, positive = too far (in the
## direction of the target).
static func solve_power(ctx: Ctx, angle: int, aim_x: int, mode: int = MODE_LAND, extra: int = 0,
		max_evals: int = MAX_EVALS) -> Dictionary:
	var p: int = _initial_power(ctx, angle, aim_x)
	var lo_p: int = 0  # largest power known to land short
	var hi_p: int = SimConstants.MAX_POWER + 1  # smallest power known to land long
	var best_p: int = p
	var best_f: int = 1 << 30
	var best_land: int = 0
	var best_impact: int = 0
	var prev_p: int = -1
	var prev_f: int = 0
	for i: int in range(max_evals):
		var land: int = _objective(ctx, angle, p, mode, extra)
		var f: int = ctx.dir * (land - aim_x)
		if absi(f) < absi(best_f):
			best_p = p
			best_f = f
			best_land = land
			best_impact = ctx.impact_x
		if absi(f) <= TOL_SEARCH:
			break
		if f < 0:
			lo_p = maxi(lo_p, p)
		else:
			hi_p = mini(hi_p, p)
		if hi_p - lo_p <= 1:
			break
		var np: int
		if prev_p < 0 or prev_f == f:
			var reach: int = maxi(20, ctx.dir * (land - ctx.sx))
			np = p - f * p / (2 * reach)
			if np == p:
				np = p - (1 if f > 0 else -1)
		else:
			np = p - f * (p - prev_p) / (f - prev_f)
		np = clampi(np, 1, SimConstants.MAX_POWER)
		if np <= lo_p or np >= hi_p:
			np = (lo_p + hi_p) / 2
			if lo_p == 0 and hi_p > SimConstants.MAX_POWER:
				np = clampi(p - (1 if f > 0 else -1) * maxi(1, p / 4), 1, SimConstants.MAX_POWER)
		if np == p:
			break
		prev_p = p
		prev_f = f
		p = np
	return {"power": best_p, "err": best_f, "land_x": best_land, "impact_x": best_impact, "angle": angle}


## Tries the preferred angle first, then steeper ones, and returns the first plan whose model
## error is within `tol`; otherwise the best plan found with ok = false (blocked or out of
## range). `a0_dir` is the preferred angle in dir-space tenths of a degree.
static func solve_direct(ctx: Ctx, aim_x: int, a0_dir: int, mode: int = MODE_LAND, extra: int = 0,
		tol: int = TOL_ACCEPT) -> Dictionary:
	var start_count: int = model_count
	var best: Dictionary = {}
	var first_ok: Dictionary = {}
	var robust: bool = false
	var order: Array[int] = [a0_dir]
	for a: int in FALLBACK_ANGLES:
		if absi(a - a0_dir) >= 40:
			order.append(a)
	for a_dir: int in order:
		if not best.is_empty() and model_count - start_count >= MODEL_BUDGET:
			break
		var plan: Dictionary = solve_power(ctx, actual_angle(ctx, a_dir), aim_x, mode, extra,
				MAX_EVALS if best.is_empty() else MAX_EVALS - 2)
		if best.is_empty() or absi(plan["err"] as int) < absi(best["err"] as int):
			best = plan
		if absi(plan["err"] as int) <= tol:
			if first_ok.is_empty():
				first_ok = plan
			if _is_robust(ctx, plan, aim_x, mode, extra):
				best = plan
				robust = true
				break
	if not first_ok.is_empty() and not robust:
		best = first_ok  # nothing was robust: settle for the first one that works
	best["ok"] = absi(best["err"] as int) <= tol
	return best


## True if the same angle with the power a little lower and a little higher still lands within
## ROBUST_TOL of the aim point.
static func _is_robust(ctx: Ctx, plan: Dictionary, aim_x: int, mode: int, extra: int) -> bool:
	var p: int = plan["power"]
	var delta: int = maxi(2, p * ROBUST_PM / 1000)
	for q: int in [maxi(1, p - delta), mini(SimConstants.MAX_POWER, p + delta)]:
		var land: int = _objective(ctx, plan["angle"], q, mode, extra)
		if absi(land - aim_x) > ROBUST_TOL:
			return false
	return true


## Aim for a tunneler (Bore Shell / Deep Bore): it digs on along its flight direction after it
## hits the ground, so a good shot is one whose bore comes out at the target. The bore end
## depends on both the angle and the power, so this scans a few flat-to-medium angles with a
## coarse power sweep and then refines the best one. Returns {angle, power, err, tunnel_ok}: err is
## the distance from the bore end to the target's box (cells); tunnel_ok when <= blast_r - 2.
static func solve_tunnel(ctx: Ctx, tx: int, ty: int, length: int, blast_r: int,
		angles: Array[int] = TUNNEL_ANGLES) -> Dictionary:
	var best_d: int = 1 << 30
	var best_angle: int = 0
	var best_p: int = 1
	for a_dir: int in angles:
		var angle: int = actual_angle(ctx, a_dir)
		for p: int in range(250, SimConstants.MAX_POWER + 1, 125):
			var d: int = _bore_miss(ctx, angle, p, tx, ty, length)
			if d < best_d:
				best_d = d
				best_angle = angle
				best_p = p
	if best_d > TUNNEL_PROMISING:
		return {"angle": best_angle, "power": best_p, "err": best_d, "impact_x": 0, "land_x": 0,
				"tunnel_ok": false}  # not even close: skip the fine search
	var centre: int = best_p
	for p: int in range(maxi(1, centre - 125), mini(SimConstants.MAX_POWER, centre + 125) + 1, 14):
		var d: int = _bore_miss(ctx, best_angle, p, tx, ty, length)
		if d < best_d:
			best_d = d
			best_p = p
	return {"angle": best_angle, "power": best_p, "err": best_d, "impact_x": 0, "land_x": 0,
			"tunnel_ok": best_d <= blast_r - 2}


## Distance (cells) from where a bore would end to the target's hit box; huge if the shell
## never reaches the ground.
static func _bore_miss(ctx: Ctx, angle: int, power: int, tx: int, ty: int, length: int) -> int:
	var fl: AiFlight = ctx.flight
	fl.fly_shot(ctx.sx, ctx.sy, angle, power, ctx.wind, MODEL_TICKS)
	model_count += 1
	if fl.r_reason != AiFlight.REASON_TERRAIN:
		return 1 << 20
	var end: Vector2i = TunnelerBehavior.bore_end(ctx.state, fl.r_px, fl.r_py, fl.r_vx, fl.r_vy, length)
	var dx: int = maxi(absi(end.x - tx) - SimConstants.TANK_W / 2, 0)
	var dy: int = maxi(absi(end.y - (ty - SimConstants.TANK_H / 2)) - SimConstants.TANK_H / 2, 0)
	return FixedMath.isqrt(dx * dx + dy * dy)


## True when the cheap model could be wrong about this shot: a teammate stands in the line of
## fire (a real shell would stop there). Otherwise the model is exact (the same physics,
## gravity wells and repulsor fields included) and the real trace is skipped to save time.
## (An enemy standing in the way is not a reason: the shell would just hit that enemy instead.
## A Seeker is not traced either: it steers itself onto the target, so its plan only has to be
## close, and one real Seeker trace costs several milliseconds.)
static func needs_verify(ctx: Ctx, target_id: int, aim_x: int, _phys_weapon: String) -> bool:
	var state: MatchState = ctx.state
	var me_team: int = state.tanks[ctx.me].team
	var lo: int = mini(ctx.sx, aim_x) - 40
	var hi: int = maxi(ctx.sx, aim_x) + 40
	for t: TankState in state.tanks:
		if t.alive and t.id != ctx.me and t.id != target_id and t.team == me_team and t.x >= lo and t.x <= hi:
			return true
	return false


## Confirms `plan` with the real trace of `phys_weapon` (a weapon id whose flight matches the
## one being fired; "pulse_missile" for every plain-flight weapon). If reality lands somewhere
## else than the model said, the aim point is shifted by the difference and the power is
## searched again. A shell that reaches the target tank or its shield bubble counts as a hit.
## Returns the best plan with extra keys real_err, hit (bool) and verified (bool), plus
## ally_hit = true when the shell ran into a teammate.
static func verify(ctx: Ctx, plan: Dictionary, phys_weapon: String, target_id: int, aim_x: int,
		mode: int = MODE_LAND, extra: int = 0) -> Dictionary:
	var cur: Dictionary = plan
	var best: Dictionary = plan.duplicate()
	best["real_err"] = 1 << 30
	best["hit"] = false
	best["verified"] = false
	var shift: int = 0
	for _i: int in range(MAX_VERIFY):
		var tr: Dictionary = counted_trace(ctx.state, ctx.me, cur["angle"], cur["power"], phys_weapon, ctx.wind)
		if tr.is_empty():
			break
		var real_x: int = tr["end_x"]
		var hit_id: int = tr["hit_tank"]
		if hit_id >= 0 and hit_id != target_id and ctx.state.tanks[hit_id].team == ctx.state.tanks[ctx.me].team:
			# A teammate is in the way: this arc is no good, whatever else it does.
			best = cur.duplicate()
			best["ally_hit"] = true
			best["real_err"] = 1 << 20
			best["hit"] = false
			best["verified"] = true
			return best
		var hit: bool = hit_id == target_id
		var rerr: int = ctx.dir * (real_x - aim_x)
		if hit:
			rerr = 0
		if absi(rerr) < absi(best["real_err"] as int):
			best = cur.duplicate()
			best["real_err"] = rerr
			best["hit"] = hit
			best["verified"] = true
		if hit or absi(rerr) <= VERIFY_TOL:
			break
		shift += real_x - (cur["impact_x"] as int)
		var nxt: Dictionary = solve_power(ctx, cur["angle"], aim_x - shift, mode, extra)
		if (nxt["power"] as int) == (cur["power"] as int):
			break
		cur = nxt
	return best


## x (cells) where a past shot would have crossed row `y` according to the model with the
## wind the AI believed at that time. Used to read how far off an old shot was without being
## confused by the crater it left behind.
static func model_x_at_row(flight: AiFlight, sx: int, sy: int, angle: int, power: int, wind: int,
		y: int, split_dvx: int = 0) -> int:
	flight.fly_shot(sx, sy, angle, power, wind, MODEL_TICKS, y, split_dvx)
	model_count += 1
	return flight.r_x


## Angle (tenths of a degree, 0..1800) of the straight line from the muzzle to (tx, ty).
## Integer scan: the angle whose direction vector is most parallel to the line.
static func beam_angle(sx: int, sy: int, tx: int, ty: int) -> int:
	var best_a: int = 0
	var best_c: int = 1 << 60
	var mx: int = sx
	var my: int = sy - SimConstants.TANK_H
	for pass_i: int in range(3):
		var step: int = 20 if pass_i == 0 else 1
		var lo: int = 0 if pass_i == 0 else maxi(0, best_a - 20)
		var hi: int = SimConstants.MAX_ANGLE if pass_i == 0 else mini(SimConstants.MAX_ANGLE, best_a + 20)
		if pass_i == 2:
			# Second refinement: the muzzle moves with the angle, so redo it from there.
			mx = sx + FixedMath.to_cell(FixedMath.cos10(best_a) * SimConstants.BARREL_LEN)
			my = sy - SimConstants.TANK_H - FixedMath.to_cell(FixedMath.sin10(best_a) * SimConstants.BARREL_LEN)
			lo = maxi(0, best_a - 12)
			hi = mini(SimConstants.MAX_ANGLE, best_a + 12)
		var dx: int = tx - mx
		var dy: int = ty - my
		best_c = 1 << 60
		var a: int = lo
		while a <= hi:
			var c: int = FixedMath.cos10(a)
			var s: int = FixedMath.sin10(a)
			# direction (c, -s); cross with (dx, dy); dot must point at the target.
			var dot: int = c * dx - s * dy
			if dot > 0:
				var cross: int = absi(c * dy + s * dx)
				if cross < best_c:
					best_c = cross
					best_a = a
			a += step
	return best_a
