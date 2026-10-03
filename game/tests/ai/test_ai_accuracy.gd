extends GutTest
## Acceptance tests of docs/ARCHITECTURE.md section 30: how often each difficulty hits a
## stationary target, over 200 seeded scenarios each (distance 300..1200 cells, wind -100..100,
## random generated terrain). The measured rates are printed (see the GUT output) and asserted.

const N: int = 200
const SHOTS: int = 5


## Runs N duels at `level`; returns {hits: Array[int] (hits within k shots, index 0..SHOTS),
## first_miss: Array[int] (distance of each first shot's impact to the target box),
## later_miss: misses of shots 2..4 that landed, lost / fired: shell counts, max_lost_run: most
## lost shells in a row in one scenario}.
func _batch(level: int, tag: int, shots: int, wind_override: int = -999) -> Dictionary:
	var hits: Array[int] = []
	for _k: int in range(shots + 1):
		hits.append(0)
	var first_miss: Array[int] = []
	var later_miss: Array[int] = []  # impact distance of shots 2..4 that landed (lost shells excluded)
	var lost: int = 0
	var fired: int = 0
	var max_lost_run: int = 0
	for i: int in range(N):
		var p: Vector2i = AiTestUtil.params(i, tag)
		var wind: int = p.y if wind_override == -999 else wind_override
		var state: MatchState = AiTestUtil.duel(1000 + i, level, p.x, wind)
		var res: Dictionary = AiTestUtil.shoot_until_hit(state, shots)
		var first: int = res["first_hit"]
		for k: int in range(1, shots + 1):
			if first > 0 and first <= k:
				hits[k] += 1
		var misses: Array[int] = res["misses"]
		first_miss.append(misses[0])
		var run: int = 0
		for k: int in range(misses.size()):
			fired += 1
			run = run + 1 if misses[k] >= 100000 else 0
			max_lost_run = maxi(max_lost_run, run)
			if misses[k] >= 100000:
				lost += 1
			elif k >= 1 and k <= 3 and misses[k] > 0:
				later_miss.append(misses[k])
	return {"hits": hits, "first_miss": first_miss, "later_miss": later_miss, "lost": lost, "fired": fired,
			"max_lost_run": max_lost_run}


func _pct(count: int) -> String:
	return "%d/%d (%.1f%%)" % [count, N, 100.0 * count / N]


func test_expert_hits_within_two_shots() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_EXPERT, 4, 3)
	var h: Array[int] = r["hits"]
	gut.p("EXPERT   hit within 1: %s  within 2: %s  within 3: %s  median first miss %d cells" % [
			_pct(h[1]), _pct(h[2]), _pct(h[3]), AiTestUtil.median(r["first_miss"])])
	assert_gte(h[2] * 100, 90 * N, "Expert must hit within 2 shots in >= 90%%, got %s" % _pct(h[2]))
	assert_gte(h[3] * 100, 97 * N, "and within 3 in >= 97%%, got %s" % _pct(h[3]))
	# Not inhuman: even the Expert misses its first shot a quarter to 40% of the time.
	assert_between(h[1] * 100, 60 * N, 75 * N, "Expert's first shot hits in 60..75%%, got %s" % _pct(h[1]))
	assert_lt(h[2], N, "it does not hit every second shot either")


func test_hard_hits_within_three_shots() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_HARD, 3, 4)
	var h: Array[int] = r["hits"]
	gut.p("HARD     hit within 1: %s  within 2: %s  within 3: %s  within 4: %s  median first miss %d" % [
			_pct(h[1]), _pct(h[2]), _pct(h[3]), _pct(h[4]), AiTestUtil.median(r["first_miss"])])
	assert_gte(h[3] * 100, 80 * N, "Hard must hit within 3 shots in >= 80%%, got %s" % _pct(h[3]))
	assert_between(h[1] * 100, 35 * N, 55 * N, "Hard's first shot hits in 35..55%%, got %s" % _pct(h[1]))
	assert_gt(h[3], h[1], "Hard improves from shot to shot")
	var expert: Dictionary = _batch(SimConstants.CTRL_EXPERT, 4, 1)
	var e1: int = (expert["hits"] as Array[int])[1]
	assert_gt(e1 - h[1], N / 10, "Hard is clearly below Expert on first-shot rate (%s vs %s)" % [_pct(h[1]), _pct(e1)])


func test_normal_first_shot_and_improvement() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_NORMAL, 2, SHOTS)
	var h: Array[int] = r["hits"]
	gut.p("NORMAL   hit within 1: %s  2: %s  3: %s  4: %s  5: %s  median first miss %d" % [
			_pct(h[1]), _pct(h[2]), _pct(h[3]), _pct(h[4]), _pct(h[5]), AiTestUtil.median(r["first_miss"])])
	assert_between(h[1] * 100, 10 * N, 40 * N, "Normal's first shot hits in 10..40%%, got %s" % _pct(h[1]))
	assert_gte(h[5], h[1] + N / 4, "Normal improves within 5 shots: %s -> %s" % [_pct(h[1]), _pct(h[5])])
	assert_gte(h[3], h[1], "never gets worse")


## M4-T: Easy is a beginner who improves slowly and unevenly (owner: "dialing in way too quickly").
## Measured over 200 scenarios, 6 shots each. Bounds on both sides so it cannot drift back.
func test_easy_improves_slowly_and_unevenly() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_EASY, 1, 6)
	var h: Array[int] = r["hits"]
	var later: Array[int] = r["later_miss"]
	var median_first: int = AiTestUtil.median(r["first_miss"])
	var median_later: int = AiTestUtil.median(later)
	var plausible: int = later.filter(func(v: int) -> bool: return v >= 40 and v <= 300).size()
	gut.p("EASY     hit within 1: %s  3: %s  6: %s | median miss first %d, shots 2-4 %d, %d/%d of those in 40..300 | lost shells %d/%d, longest lost run %d" % [
			_pct(h[1]), _pct(h[3]), _pct(h[6]), median_first, median_later, plausible, later.size(),
			r["lost"], r["fired"], r["max_lost_run"]])
	assert_between(h[1] * 100, 1 * N, 8 * N, "Easy's first shot hits in 1..8%%, got %s" % _pct(h[1]))
	assert_between(h[3] * 100, 5 * N, 20 * N, "Easy hits within 3 shots in 5..20%%, got %s" % _pct(h[3]))
	assert_between(h[6] * 100, 20 * N, 40 * N, "Easy hits within 6 shots in 20..40%%, got %s" % _pct(h[6]))
	assert_gt(h[6], h[3], "it does improve, slowly")
	assert_gte(median_later, 60, "the median miss on shots 2-4 stays large (cells)")
	assert_lte(median_later, 300, "but believable")
	assert_between(median_first, 40, 250, "believable median first miss (cells)")
	assert_gte(plausible * 100, 60 * later.size(), "most later misses are in the plausible 40..300 cell range")
	assert_lte(r["max_lost_run"], 3, "no endless repeats of a lost shot")


func test_normal_is_clearly_better_than_easy_within_three_shots() -> void:
	var easy: Array[int] = (_batch(SimConstants.CTRL_EASY, 1, 3))["hits"]
	var normal: Array[int] = (_batch(SimConstants.CTRL_NORMAL, 1, 3))["hits"]
	gut.p("GAP      hit within 3 shots: easy %s vs normal %s" % [_pct(easy[3]), _pct(normal[3])])
	assert_gte((normal[3] - easy[3]) * 100, 20 * N, "Normal is at least 20 points ahead of Easy within 3 shots")
	assert_between(normal[3] * 100, 55 * N, 80 * N, "Normal within 3 shots stays in 55..80%%, got %s" % _pct(normal[3]))


## The correction dice: Easy mostly corrects 80..150 per-mille of the miss, about 25% of the time it
## over-corrects past the target, about 15% it barely corrects; the higher levels never roll.
func test_easy_correction_factors_follow_the_profile() -> void:
	var prof: Dictionary = AiProfile.for_level(SimConstants.CTRL_EASY)
	var rng: Rng = Rng.derive(5, 6)
	var weak: int = 0
	var over: int = 0
	var ignored: int = 0
	var draws: int = 2000
	for _i: int in range(draws):
		var f: int = AiPlayer.correction_factor(prof, rng, false)
		if f >= 1000:
			over += 1
			assert_between(f, prof["overshoot_min"], prof["overshoot_max"])
		elif f <= prof["ignore_max"]:
			ignored += 1
		else:
			weak += 1
			assert_between(f, prof["corr_min"], prof["corr_max"])
	gut.p("EASY     correction factors over %d draws: weak %d, over-correct %d (%.1f%%), barely %d (%.1f%%)" % [
			draws, weak, over, 100.0 * over / draws, ignored, 100.0 * ignored / draws])
	assert_between(over * 100, 20 * draws, 30 * draws, "about 25%% over-correct")
	assert_between(ignored * 100, 10 * draws, 20 * draws, "about 15%% barely correct")
	assert_gt(weak * 100, 50 * draws, "most corrections are weak")
	var normal: Dictionary = AiProfile.for_level(SimConstants.CTRL_NORMAL)
	var before: PackedInt64Array = rng.get_state()
	assert_eq(AiPlayer.correction_factor(normal, rng, false), 500, "Normal's correction is a fixed 50%")
	assert_eq(AiPlayer.correction_factor(normal, rng, true), 500, "also after a lost shell")
	assert_eq(rng.get_state(), before, "and rolls no dice (its stream is unchanged)")


## A beginner gets the hang of it in a long round: once an Easy tank has had ~8 turns of its own, it
## corrects harder and is steadier (stateless: estimated from the turn number). This is what keeps an
## Easy-vs-Easy round from lasting for hundreds of turns; shots 1-6 above are not affected.
func test_easy_gets_better_in_a_long_round_but_not_in_the_first_shots() -> void:
	var prof: Dictionary = AiProfile.for_level(SimConstants.CTRL_EASY)
	var state: MatchState = AiTestUtil.duel(3, SimConstants.CTRL_EASY, 800, 0)
	state.turn_number = 2 * (prof["veteran_shots"] as int) - 2
	assert_false(AiPlayer.is_veteran(state, prof), "not yet after veteran_shots - 1 own turns (2 tanks)")
	state.turn_number = 2 * (prof["veteran_shots"] as int)
	assert_true(AiPlayer.is_veteran(state, prof))
	for level: int in [SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		assert_false(AiPlayer.is_veteran(state, AiProfile.for_level(level)), "only Easy has a veteran phase")
	# Mean miss of the LANDED shots in shots 10..14 of a long duel (no hits are possible to stop it: the
	# target is revived), against shots 2..6.
	var early: Array[int] = []
	var late: Array[int] = []
	for i: int in range(60):
		var p: Vector2i = AiTestUtil.params(i, 21)
		var duel: MatchState = AiTestUtil.duel(8000 + i, SimConstants.CTRL_EASY, p.x, 0)
		for shot: int in range(1, 15):
			AiTestUtil.give_turn_back(duel)
			duel.tanks[AiTestUtil.TARGET].health = SimConstants.MAX_HEALTH
			var turn: Dictionary = AiTestUtil.play_turn(duel, AiTestUtil.SHOOTER)
			var m: int = AiTestUtil.impact_miss(duel, turn["events"])
			if m >= 100000:
				continue
			if shot >= 2 and shot <= 6:
				early.append(m)
			elif shot >= 10:
				late.append(m)
	var early_med: int = AiTestUtil.median(early)
	var late_med: int = AiTestUtil.median(late)
	gut.p("EASY     median miss, shots 2-6: %d cells; shots 10-14 (veteran): %d cells" % [early_med, late_med])
	assert_gte(early_med, 60, "early shots stay sloppy")
	assert_lt(late_med * 100, early_med * 70, "a long round makes it clearly better (at least 30%% closer)")


## After a lost shell Easy makes a big but crude adjustment (not an exact bracket), and the lost
## shots do not repeat: starting from a lost full-power shell, the shells land within a few shots.
func test_easy_reacts_to_a_lost_shell_crudely_and_does_not_repeat_it() -> void:
	var lands_after: Array[int] = []
	var next_hit: int = 0
	var cut: Array[int] = []
	for i: int in range(100):
		var p: Vector2i = AiTestUtil.params(i, 9)
		var state: MatchState = AiTestUtil.duel(7000 + i, SimConstants.CTRL_EASY, p.x, 0)
		var me: TankState = state.tanks[AiTestUtil.SHOOTER]
		me.last_fire_weapon = Catalog.index_of("pulse_missile")
		me.last_fire_x = -1
		me.last_fire_y = -1
		me.last_fire_angle = 450 if state.tanks[AiTestUtil.TARGET].x > me.x else 1350
		me.last_fire_power = 1000
		me.last_fire_turn = 0
		state.turn_number = 1
		var sit: AiSituation = AiPlayer.situation(state, me, SimConstants.CTRL_EASY,
				AiProfile.for_level(SimConstants.CTRL_EASY), AiTargets.enemies_of(state, me))
		var action: Dictionary = AiPlayer.finalize(sit, AiWeapons.choose_and_plan(sit))
		cut.append(1000 - (action["power"] as int))
		var res: Dictionary = AiTestUtil.shoot_until_hit(state, 6)
		var misses: Array[int] = res["misses"]
		var first_landed: int = 0
		while first_landed < misses.size() and misses[first_landed] >= 100000:
			first_landed += 1
		lands_after.append(first_landed)
		if res["first_hit"] == 1:
			next_hit += 1
	gut.p("EASY     after a lost full-power shell: lost shots before one lands: median %d, p95 %d, max %d; hit on the very next shot %d/100" % [
			AiTestUtil.median(lands_after), AiTestUtil.percentile(lands_after, 95), lands_after.max(), next_hit])
	assert_lte(lands_after.max(), 3, "a lost shot is never repeated more than 3 times in a row")
	assert_lte(next_hit, 15, "the reaction is crude: it rarely lands a hit straight away")
	assert_gt(AiTestUtil.median(cut), 50, "but it does cut the power by a clear amount")


func test_easy_ignores_wind_so_wind_moves_its_shells_but_it_still_misses_without_wind() -> void:
	var calm: Dictionary = _batch(SimConstants.CTRL_EASY, 11, 1, 0)
	var windy: Dictionary = _batch(SimConstants.CTRL_EASY, 11, 1, 100)
	var calm_hits: Array[int] = calm["hits"]
	var windy_hits: Array[int] = windy["hits"]
	var calm_median: int = AiTestUtil.median(calm["first_miss"])
	gut.p("EASY     no wind: median miss %d, misses %s | wind 100: median miss %d, misses %s" % [
			calm_median, _pct(N - calm_hits[1]), AiTestUtil.median(windy["first_miss"]), _pct(N - windy_hits[1])])
	assert_gte((N - calm_hits[1]) * 100, 90 * N, "without wind Easy still misses (consistent bias)")
	assert_gte(calm_median, 40, "the bias alone is a believable miss")
	# Easy believes the wind is zero: it fires the very same shot in any wind (so the wind, not the AI,
	# is what moves the shell and spoils or helps the aim).
	var same: int = 0
	var moved: int = 0
	var landed: int = 0
	for i: int in range(40):
		var p: Vector2i = AiTestUtil.params(i, 12)
		var a: MatchState = AiTestUtil.duel(2000 + i, SimConstants.CTRL_EASY, p.x, 0)
		var b: MatchState = AiTestUtil.duel(2000 + i, SimConstants.CTRL_EASY, p.x, 100)
		var ta: Dictionary = AiTestUtil.play_turn(a, AiTestUtil.SHOOTER)
		var tb: Dictionary = AiTestUtil.play_turn(b, AiTestUtil.SHOOTER)
		if ta["action"] == tb["action"]:
			same += 1
		if AiTestUtil.impact_miss(a, ta["events"]) < 100000 and AiTestUtil.impact_miss(b, tb["events"]) < 100000:
			landed += 1
			if _impact_x(ta["events"]) != _impact_x(tb["events"]):
				moved += 1
	gut.p("EASY     same shot in wind 0 and 100: %d/40; the wind moved the landing in %d of %d landed pairs" % [same, moved, landed])
	assert_eq(same, 40, "Easy ignores the wind in its aim")
	assert_gte(moved * 100, 80 * landed, "yet the real wind moves the shell")


func _impact_x(events: Array[Dictionary]) -> int:
	for e: Dictionary in events:
		if e["type"] == "projectile_end" and e["reason"] != "lost" and e["reason"] != "timeout":
			return e["x"]
	return -1


func test_levels_are_ordered_by_skill() -> void:
	var rates: Array[int] = []
	for level: int in [SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		rates.append((_batch(level, 77, 1)["hits"] as Array[int])[1])
	gut.p("SKILL    first-shot hits (of %d): easy %d  normal %d  hard %d  expert %d" % [N, rates[0], rates[1], rates[2], rates[3]])
	assert_lt(rates[0], rates[1])
	assert_lt(rates[1], rates[2])
	assert_lt(rates[2], rates[3])


## Misses are consistent, not random: with no wind, an Easy tank's shots fall short when the
## round's bias is negative and long when it is positive (the bias is picked once per round).
func test_easy_bias_decides_which_side_the_shots_land_on() -> void:
	var matching: int = 0
	var total: int = 0
	for i: int in range(100):
		var p: Vector2i = AiTestUtil.params(i, 5)
		var state: MatchState = AiTestUtil.duel(4000 + i, SimConstants.CTRL_EASY, p.x, 0)
		var bias: int = AiPlayer.round_bias(state, AiTestUtil.SHOOTER, AiProfile.for_level(SimConstants.CTRL_EASY))
		var target_x: int = state.tanks[AiTestUtil.TARGET].x
		var dir: int = 1 if target_x >= state.tanks[AiTestUtil.SHOOTER].x else -1
		var turn: Dictionary = AiTestUtil.play_turn(state, AiTestUtil.SHOOTER)
		for e: Dictionary in turn["events"]:
			if e["type"] == "projectile_end" and e["reason"] != "lost":
				total += 1
				if signi(dir * ((e["x"] as int) - target_x)) == signi(bias):
					matching += 1
	gut.p("EASY     first shot lands on the side the round bias predicts: %d/%d" % [matching, total])
	assert_gte(matching * 100, 80 * total, "Easy is 'always a bit short' (or long), not random")


func test_round_bias_is_constant_within_a_round_and_has_the_profiled_size() -> void:
	for level: int in [SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT]:
		var prof: Dictionary = AiProfile.for_level(level)
		var seen_pos: bool = false
		var seen_neg: bool = false
		for i: int in range(40):
			var state: MatchState = AiTestUtil.duel(100 + i, level, 600, 0)
			var b: int = AiPlayer.round_bias(state, 0, prof)
			state.turn_number += 5
			assert_eq(AiPlayer.round_bias(state, 0, prof), b, "same bias on every turn of the round")
			assert_between(absi(b), prof["bias_min"], prof["bias_max"], "bias magnitude")
			seen_pos = seen_pos or b > 0
			seen_neg = seen_neg or b < 0
		assert_true(seen_pos and seen_neg, "the sign is seeded: both occur across seeds")

