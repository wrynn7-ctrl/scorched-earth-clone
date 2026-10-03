extends GutTest
## Acceptance tests of docs/ARCHITECTURE.md section 30: how often each difficulty hits a
## stationary target, over 200 seeded scenarios each (distance 300..1200 cells, wind -100..100,
## random generated terrain). The measured rates are printed (see the GUT output) and asserted.

const N: int = 200
const SHOTS: int = 5


## Runs N duels at `level`; returns {hits: Array[int] (hits within k shots, index 0..SHOTS),
## first_miss: Array[int] (distance of each first shot's impact to the target box),
## later_miss: misses of shots 2..4 that landed, lost / fired: shell counts}.
func _batch(level: int, tag: int, shots: int, wind_override: int = -999) -> Dictionary:
	var hits: Array[int] = []
	for _k: int in range(shots + 1):
		hits.append(0)
	var first_miss: Array[int] = []
	var later_miss: Array[int] = []  # impact distance of shots 2..4 that landed (lost shells excluded)
	var lost: int = 0
	var fired: int = 0
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
		for k: int in range(misses.size()):
			fired += 1
			if misses[k] >= 100000:
				lost += 1
			elif k >= 1 and k <= 3 and misses[k] > 0:
				later_miss.append(misses[k])
	return {"hits": hits, "first_miss": first_miss, "later_miss": later_miss, "lost": lost, "fired": fired}


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


func test_easy_first_shot_misses_by_a_believable_distance() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_EASY, 1, 1)
	var h: Array[int] = r["hits"]
	var median: int = AiTestUtil.median(r["first_miss"])
	gut.p("EASY     first shot misses: %s  (hits %s)  median miss %d cells" % [
			_pct(N - h[1]), _pct(h[1]), median])
	assert_gte((N - h[1]) * 100, 85 * N, "Easy's first shot misses in >= 85%%")
	assert_between(median, 40, 250, "believable median miss (cells)")


func test_easy_misses_more_in_strong_wind_but_still_misses_without_wind() -> void:
	var calm: Dictionary = _batch(SimConstants.CTRL_EASY, 11, 1, 0)
	var windy: Dictionary = _batch(SimConstants.CTRL_EASY, 11, 1, 100)
	var calm_hits: Array[int] = calm["hits"]
	var windy_hits: Array[int] = windy["hits"]
	var calm_median: int = AiTestUtil.median(calm["first_miss"])
	var windy_median: int = AiTestUtil.median(windy["first_miss"])
	gut.p("EASY     no wind: median miss %d, misses %s | wind 100: median miss %d, misses %s" % [
			calm_median, _pct(N - calm_hits[1]), windy_median, _pct(N - windy_hits[1])])
	assert_gt(windy_median, calm_median, "wind (which Easy ignores) makes it miss by more")
	assert_gte((N - calm_hits[1]) * 100, 80 * N, "without wind Easy still misses (consistent bias)")
	assert_gte(calm_median, 40, "the bias alone is a believable miss")


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


func test_probe_easy() -> void:
	var r: Dictionary = _batch(SimConstants.CTRL_EASY, 1, 6)
	var h: Array[int] = r["hits"]
	var lm: Array[int] = r["later_miss"]
	gut.p("PROBE easy 1..6: %s %s %s %s %s %s  later median %d p10 %d p90 %d  in40-300 %d/%d lost %d/%d" % [
			_pct(h[1]), _pct(h[2]), _pct(h[3]), _pct(h[4]), _pct(h[5]), _pct(h[6]),
			AiTestUtil.median(lm), AiTestUtil.percentile(lm, 10), AiTestUtil.percentile(lm, 90),
			lm.filter(func(v: int) -> bool: return v >= 40 and v <= 300).size(), lm.size(), r["lost"], r["fired"]])
	var n: Dictionary = _batch(SimConstants.CTRL_NORMAL, 1, 6)
	var nh: Array[int] = n["hits"]
	gut.p("PROBE normal 1..6: %s %s %s %s %s %s" % [_pct(nh[1]), _pct(nh[2]), _pct(nh[3]), _pct(nh[4]), _pct(nh[5]), _pct(nh[6])])
	assert_true(true)
