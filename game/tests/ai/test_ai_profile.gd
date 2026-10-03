extends GutTest
## The difficulty table (docs/ARCHITECTURE.md section 29) and the shop plans it carries.

const LEVELS: Array[int] = [
	SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL, SimConstants.CTRL_HARD, SimConstants.CTRL_EXPERT,
]


func test_the_table_matches_the_spec() -> void:
	var easy: Dictionary = AiProfile.for_level(SimConstants.CTRL_EASY)
	var normal: Dictionary = AiProfile.for_level(SimConstants.CTRL_NORMAL)
	var hard: Dictionary = AiProfile.for_level(SimConstants.CTRL_HARD)
	var expert: Dictionary = AiProfile.for_level(SimConstants.CTRL_EXPERT)
	assert_eq([easy["wind_use"], normal["wind_use"], hard["wind_use"], expert["wind_use"]], [0, 500, 900, 1000])
	assert_eq([easy["bias_min"], easy["bias_max"]], [80, 150])
	assert_eq([normal["bias_min"], normal["bias_max"]], [40, 80])
	assert_eq([hard["bias_min"], hard["bias_max"]], [15, 30])
	assert_eq([expert["bias_min"], expert["bias_max"]], [0, 0])
	assert_eq([easy["noise"], normal["noise"], hard["noise"], expert["noise"]], [40, 25, 10, 4])
	assert_eq([easy["correction"], normal["correction"], hard["correction"], expert["correction"]], [250, 500, 800, 1000])
	assert_eq([easy["target"], normal["target"], hard["target"], expert["target"]], [
			AiProfile.TARGET_NEAREST, AiProfile.TARGET_REVENGE, AiProfile.TARGET_WEAKEST, AiProfile.TARGET_VALUE])
	assert_eq([easy["shield"], normal["shield"], hard["shield"], expert["shield"]], [
			AiProfile.SHIELD_NEVER, AiProfile.SHIELD_WHEN_HURT, AiProfile.SHIELD_ALWAYS, AiProfile.SHIELD_ALWAYS])
	assert_eq(normal["shield_below"], 50)
	assert_eq([easy["move"], normal["move"], hard["move"], expert["move"]], [
			AiProfile.MOVE_NEVER, AiProfile.MOVE_NEVER, AiProfile.MOVE_OUT_OF_PIT, AiProfile.MOVE_TO_IMPROVE])
	assert_true(expert["repulsor"])
	assert_false(hard["repulsor"])


func test_every_level_is_better_than_the_one_below() -> void:
	for i: int in range(1, LEVELS.size()):
		var lo: Dictionary = AiProfile.for_level(LEVELS[i - 1])
		var hi: Dictionary = AiProfile.for_level(LEVELS[i])
		assert_gt(hi["wind_use"], lo["wind_use"])
		assert_lt(hi["bias_max"], lo["bias_max"] + 1)
		assert_lt(hi["noise"], lo["noise"])
		assert_gt(hi["correction"], lo["correction"])


func test_all_values_are_integers_in_range() -> void:
	for level: int in LEVELS:
		var p: Dictionary = AiProfile.for_level(level)
		for key: String in ["wind_use", "bias_min", "bias_max", "noise", "correction"]:
			assert_eq(typeof(p[key]), TYPE_INT, "%s of level %d is an integer" % [key, level])
			assert_between(p[key], 0, 1000)
		assert_lte(p["bias_min"], p["bias_max"])


func test_level_lookup() -> void:
	var state: MatchState = AiTestUtil.duel(1, SimConstants.CTRL_HARD, 600, 0)
	assert_eq(AiProfile.level_of(state, 0), SimConstants.CTRL_HARD)
	assert_eq(AiProfile.level_of(state, 1), SimConstants.CTRL_NORMAL, "a human slot plays as Normal if the AI is asked to")
	assert_eq(AiProfile.level_of(state, 77), SimConstants.CTRL_NORMAL, "an unknown tank id too")
	assert_eq(AiProfile.for_level(0)["name"], "easy", "out-of-range levels are clamped")
	assert_eq(AiProfile.for_level(9)["name"], "expert")


func test_shop_plans_name_real_catalog_entries_with_sane_quantities() -> void:
	var plans: Array = [AiProfile.SHOP_NORMAL, AiProfile.SHOP_HARD, AiProfile.SHOP_EXPERT]
	for plan: Array in plans:
		for wish: Array in plan:
			assert_true(Catalog.has(wish[0]), "%s is in the catalog" % wish[0])
			assert_ne(wish[0], Catalog.SPARK_DART, "the Spark Dart is not for sale")
			assert_between(wish[1], 1, SimConstants.INVENTORY_CAP)
	for id: String in AiProfile.SHOP_EASY_POOL:
		assert_true(Catalog.has(id))
		assert_eq(Catalog.get_def(id)["tier"], "free", "Easy only shops in the free tier")
		assert_lte(Catalog.get_def(id)["price"], 2000, "and cheaply")


func test_the_ai_never_names_the_original_games_items() -> void:
	# CLAUDE.md rule 7: only the names from PLAN.md section 3 (ids are checked by the catalog).
	var banned: Array[String] = ["scorched", "baby missile", "mirv", "napalm", "funky bomb", "death's head"]
	for f: String in ["ai_profile", "ai_player", "ai_weapons", "ai_shop", "ai_targets", "aim_solver", "ai_flight"]:
		var text: String = FileAccess.get_file_as_string("res://ai/%s.gd" % f).to_lower()
		for b: String in banned:
			assert_false(text.contains(b), "%s mentions '%s'" % [f, b])
