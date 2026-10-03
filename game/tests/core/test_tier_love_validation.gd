extends GutTest
## StateSerial.validate gaps closed in M5-QF-C: a finished love match must have exactly one full meter owned
## by the loser (section 37), and a free match can never hold a full-tier item (section 32).

const FULL_WEAPON: String = "supernova"
const FULL_ITEM: String = "fortress_field"


func _love_settings(seed_value: int = 5) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.mode = SimConstants.MODE_LOVE
	s.wind_max = 20
	return s


## A love match the way the heart resolver leaves it: tank 1's meter filled by tank 0, who holds the win.
func _love_over() -> MatchState:
	var s: MatchState = Simulation.new_match(_love_settings())
	s.tanks[1].love = SimConstants.LOVE_MAX
	s.tanks[0].round_wins = 1
	s.phase = SimConstants.PHASE_MATCH_OVER
	return s


func _free_settings(seed_value: int = 9) -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed_value
	s.num_tanks = 2
	s.rounds = 3
	s.full_unlocked = false
	return s


func _free_aim() -> MatchState:
	var s: MatchState = Simulation.new_match(_free_settings())
	SimTestUtil.begin_round(s)
	return s


func _decode_error(s: MatchState) -> String:
	var res: Dictionary = SaveCodec.decode(SaveCodec.encode(s, [] as Array[Dictionary]))
	return "" if res["ok"] else res["error"]


# --- love ---------------------------------------------------------------------------------------------

func test_honest_finished_love_match_validates() -> void:
	var s: MatchState = _love_over()
	assert_eq(StateSerial.validate(s), "")
	assert_eq(_decode_error(s), "")


func test_two_full_meters_are_invalid() -> void:
	var s: MatchState = _love_over()
	s.tanks[0].love = SimConstants.LOVE_MAX
	assert_ne(StateSerial.validate(s), "")
	assert_eq(_decode_error(s), "invalid_state")


func test_full_meter_tank_cannot_hold_the_win() -> void:
	var s: MatchState = _love_over()
	s.tanks[0].round_wins = 0
	s.tanks[1].round_wins = 1
	assert_ne(StateSerial.validate(s), "")
	assert_eq(_decode_error(s), "invalid_state")


func test_nobody_holding_the_win_is_invalid() -> void:
	var s: MatchState = _love_over()
	s.tanks[0].round_wins = 0
	assert_ne(StateSerial.validate(s), "")
	s = _love_over()
	s.tanks[1].love = 99
	assert_ne(StateSerial.validate(s), "", "no full meter at all")


func test_both_tanks_credited_is_invalid() -> void:
	var s: MatchState = _love_over()
	s.tanks[1].round_wins = 1
	assert_ne(StateSerial.validate(s), "")


func test_love_win_in_either_direction_validates() -> void:
	var s: MatchState = _love_over()
	s.tanks[0].love = SimConstants.LOVE_MAX
	s.tanks[1].love = 40
	s.tanks[0].round_wins = 0
	s.tanks[1].round_wins = 1
	assert_eq(StateSerial.validate(s), "")


func test_played_love_match_validates_at_every_step() -> void:
	var s: MatchState = Simulation.new_match(_love_settings(11))
	var guard: int = 0
	while s.phase == SimConstants.PHASE_AIM and guard < 200:
		guard += 1
		Simulation.apply_action(s, AiPlayer.next_action(s, s.current_tank))
		assert_eq(StateSerial.validate(s), "", "step %d" % guard)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)


# --- free tier ----------------------------------------------------------------------------------------

func test_free_state_with_free_items_validates() -> void:
	var s: MatchState = _free_aim()
	s.tanks[0].set_stock("pulse_missile", 4)
	s.tanks[1].set_stock("glow_shield", 2)
	assert_eq(StateSerial.validate(s), "")


func test_free_state_with_full_tier_stock_is_invalid() -> void:
	for id: String in [FULL_WEAPON, FULL_ITEM, "heavy_orb"]:
		var s: MatchState = _free_aim()
		s.tanks[1].set_stock(id, 1)
		assert_ne(StateSerial.validate(s), "", id)
		assert_eq(_decode_error(s), "invalid_state", id)


func test_full_match_may_hold_full_tier_stock() -> void:
	var s: MatchState = _free_aim()
	s.settings.full_unlocked = true
	s.tanks[0].set_stock(FULL_WEAPON, 3)
	s.tanks[1].set_stock(FULL_ITEM, 1)
	assert_eq(StateSerial.validate(s), "")


func test_every_full_tier_entry_is_rejected_in_a_free_match() -> void:
	var seen: int = 0
	for i: int in range(Catalog.count()):
		var id: String = Catalog.id_at(i)
		if Catalog.get_def(id)["tier"] != "full":
			continue
		seen += 1
		var s: MatchState = _free_aim()
		s.tanks[0].set_stock(id, 1)
		assert_ne(StateSerial.validate(s), "", id)
	assert_gt(seen, 0)


func test_free_state_with_a_full_tier_shield_is_invalid() -> void:
	var s: MatchState = _free_aim()
	s.tanks[0].shield_type = Catalog.index_of(FULL_ITEM)
	s.tanks[0].shield_hp = 1
	assert_ne(StateSerial.validate(s), "")


func test_free_state_remembering_a_full_tier_shot_is_invalid() -> void:
	var s: MatchState = _free_aim()
	var t: TankState = s.tanks[0]
	t.last_fire_weapon = Catalog.index_of(FULL_WEAPON)
	t.last_fire_angle = 45
	t.last_fire_power = 500
	t.last_fire_x = 100
	t.last_fire_y = 100
	t.last_fire_wind = 0
	t.last_fire_turn = 0
	assert_ne(StateSerial.validate(s), "")
	s.settings.full_unlocked = true
	assert_eq(StateSerial.validate(s), "")


func _fire_full(tank: int) -> Dictionary:
	var a: Dictionary = SimTestUtil.fire(tank, 45, 500)
	a["weapon"] = FULL_WEAPON
	return a


func test_free_actions_on_full_tier_entries_are_locked() -> void:
	var s: MatchState = _free_aim()
	s.tanks[s.current_tank].set_stock(FULL_WEAPON, 2)  # forced in behind the validator
	s.tanks[s.current_tank].set_stock(FULL_ITEM, 1)
	var cur: int = s.current_tank
	assert_eq(Simulation.validate_action(s, _fire_full(cur)), "locked_item")
	assert_eq(Simulation.validate_action(s, SimTestUtil.use_item(cur, FULL_ITEM)), "locked_item")
	s.settings.full_unlocked = true
	assert_eq(Simulation.validate_action(s, _fire_full(cur)), "")
	assert_eq(Simulation.validate_action(s, SimTestUtil.use_item(cur, FULL_ITEM)), "")


func test_free_shop_cannot_acquire_full_tier_items() -> void:
	var s: MatchState = Simulation.new_match(_free_settings())
	for t: TankState in s.tanks:
		t.money = SimConstants.INVENTORY_CAP * 1000
	assert_eq(Simulation.validate_action(s, SimTestUtil.buy(0, FULL_WEAPON, 1)), "locked_item")
	assert_eq(StateSerial.validate(s), "")


func test_free_ai_match_never_holds_full_tier_items() -> void:
	var settings: MatchSettings = _free_settings(21)
	settings.controllers = [SimConstants.CTRL_EASY, SimConstants.CTRL_NORMAL] as Array[int]
	settings.rounds = 3
	var s: MatchState = Simulation.new_match(settings)
	var guard: int = 0
	while s.phase != SimConstants.PHASE_MATCH_OVER and guard < 600:
		guard += 1
		if s.phase == SimConstants.PHASE_SHOP:
			for t: TankState in s.tanks:
				for a: Dictionary in AiPlayer.shop_actions(s, t.id):
					assert_eq(Simulation.validate_action(s, a), "", "shop step %d" % guard)
					Simulation.apply_action(s, a)
			Simulation.start_round(s)
		else:
			Simulation.apply_action(s, AiPlayer.next_action(s, s.current_tank))
		assert_eq(StateSerial.validate(s), "", "step %d" % guard)
	assert_eq(s.phase, SimConstants.PHASE_MATCH_OVER)
