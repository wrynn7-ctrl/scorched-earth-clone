@warning_ignore_start("integer_division")
extends GutTest
## M4 QA: the free version. With full_unlocked = false, Hard (3) and Expert (4) controllers are
## clamped to Normal (2) by new_match, the CPUs play as Normal, and their shops never try a
## full-tier item. A state that bypasses the clamp (hand-built, never reachable through new_match
## or a save, which StateSerial.validate rejects) must still never produce a locked purchase.

const QA_AI = preload("res://tests/qa/qa_ai.gd")


func _locked(ctrl: Array[int], seed_value: int, money: int = 10000) -> MatchState:
	var st := MatchSettings.new()
	st.seed = seed_value
	st.num_tanks = ctrl.size()
	st.rounds = 2
	st.start_money = money
	st.full_unlocked = false
	st.controllers = PackedInt32Array(ctrl)
	return Simulation.new_match(st)


func test_hard_and_expert_are_clamped_to_normal_by_new_match() -> void:
	var s: MatchState = _locked([3, 4], 1)
	assert_eq(s.settings.controllers, PackedInt32Array([2, 2]))
	assert_eq(AiProfile.level_of(s, 0), SimConstants.CTRL_NORMAL)
	assert_eq(AiProfile.level_of(s, 1), SimConstants.CTRL_NORMAL)
	var mixed: MatchState = _locked([3, 4, 0, 1], 2)
	assert_eq(mixed.settings.controllers, PackedInt32Array([2, 2, 0, 1]), "only 3 and 4 are lowered")
	# The free version also caps a match at 4 tanks (ARCHITECTURE §32), trimming extra controllers.
	var six: MatchState = _locked([3, 4, 0, 1, 4, 2], 2)
	assert_eq(six.settings.controllers, PackedInt32Array([2, 2, 0, 1]), "free matches are capped at 4 tanks")
	# The unlocked game keeps them.
	var st := MatchSettings.new()
	st.seed = 3
	st.controllers = PackedInt32Array([3, 4])
	var full: MatchState = Simulation.new_match(st)
	assert_eq(full.settings.controllers, PackedInt32Array([3, 4]))


func test_free_version_cpus_shop_exactly_like_normal_cpus() -> void:
	for money: int in [0, 3000, 10000, 25000, 1_000_000]:
		for seed_value: int in range(1, 6):
			var locked: MatchState = _locked([3, 4], seed_value, money)
			var normal: MatchState = _locked([2, 2], seed_value, money)
			for id: int in [0, 1]:
				assert_eq(AiPlayer.shop_actions(locked, id), AiPlayer.shop_actions(normal, id),
						"free-tier [3,4] shops like [2,2] (money %d seed %d tank %d)" % [money, seed_value, id])


func test_free_version_cpus_never_buy_full_tier_items() -> void:
	var bought: int = 0
	for seed_value: int in range(1, 9):
		var s: MatchState = _locked([3, 4, 4, 3], seed_value, 25000)
		for t: TankState in s.tanks:
			for a: Dictionary in AiPlayer.shop_actions(s, t.id):
				assert_eq(Simulation.validate_action(s, a), "", "legal shop action")
				if a["kind"] == "buy":
					bought += 1
					assert_eq(Catalog.get_def(a["item"])["tier"], "free", "bought %s while locked" % a["item"])
				Simulation.apply_action(s, a)
	assert_gt(bought, 20, "the CPUs really bought things")


func test_bypassed_clamp_still_never_buys_locked_items() -> void:
	# Hard and Expert profiles with full_unlocked = false (the clamp bypassed by hand).
	var offered_full: int = 0
	for seed_value: int in range(1, 6):
		var s: MatchState = _locked([2, 2], seed_value, 500_000)
		s.settings.controllers = PackedInt32Array([3, 4])
		for id: int in [0, 1]:
			var acts: Array[Dictionary] = AiPlayer.shop_actions(s, id)
			for a: Dictionary in acts:
				assert_eq(Simulation.validate_action(s, a), "")
				if a["kind"] == "buy" and Catalog.get_def(a["item"])["tier"] == "full":
					offered_full += 1
			assert_eq(acts[acts.size() - 1]["kind"], "ready")
			assert_gt(acts.size(), 3, "still shops for free-tier items")
	assert_eq(offered_full, 0)


func test_unlocked_expert_with_money_does_buy_full_tier_items() -> void:
	# Positive control for the tests above: the same shop in the full version does use full-tier items.
	var full_buys: int = 0
	for seed_value: int in range(1, 6):
		var st := MatchSettings.new()
		st.seed = seed_value
		st.num_tanks = 2
		st.start_money = 500_000
		st.controllers = PackedInt32Array([4, 2])
		var s: MatchState = Simulation.new_match(st)
		# Give the opponent a shield so the counter shopping kicks in too.
		s.tanks[1].set_stock("ion_shield", 1)
		for a: Dictionary in AiPlayer.shop_actions(s, 0):
			if a["kind"] == "buy" and Catalog.get_def(a["item"])["tier"] == "full":
				full_buys += 1
	assert_gt(full_buys, 0, "the unlocked Expert buys at least one full-tier item (e.g. Static Burst, Singularity Seed)")


func test_free_version_match_plays_as_normal_and_uses_only_free_weapons() -> void:
	for seed_value: int in [11, 12, 13]:
		var s: MatchState = _locked([3, 4, 3], seed_value, 25000)
		var log: Array[Dictionary] = []
		var guard: int = 0
		while s.phase != SimConstants.PHASE_MATCH_OVER and guard < 3000:
			guard += 1
			if s.phase == SimConstants.PHASE_SHOP:
				for t: TankState in s.tanks:
					for a: Dictionary in AiPlayer.shop_actions(s, t.id):
						if a["kind"] == "buy":
							assert_eq(Catalog.get_def(a["item"])["tier"], "free", "bought %s while locked" % a["item"])
						Simulation.apply_action(s, a)
				Simulation.start_round(s)
				continue
			var a2: Dictionary = AiPlayer.next_action(s, s.current_tank)
			assert_eq(Simulation.validate_action(s, a2), "")
			log.append(a2)
			Simulation.apply_action(s, a2)
		assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
		var fired: Dictionary = {}
		for a3: Dictionary in log:
			var id: String = ""
			if a3["kind"] == "fire":
				id = a3["weapon"]
			elif a3["kind"] == "use_item":
				id = a3["item"]
			if id != "":
				fired[id] = true
				assert_eq(Catalog.get_def(id)["tier"], "free", "%s used in the free version" % id)
		assert_gt(log.size(), 10)
		# Normal's profile, not Expert's: no wells, static bursts, lances or repulsors.
		for banned: String in ["singularity_seed", "static_burst", "photon_lance", "repulsor_field", "riptide_anchor"]:
			assert_false(fired.has(banned), "free version CPU used %s" % banned)
