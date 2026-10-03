class_name MatchSettings
extends RefCounted
## Parameters chosen before a match starts. Later milestones add fields here.

@warning_ignore("shadowed_global_identifier")
var seed: int = 0
var num_tanks: int = 2
var rounds: int = 1
var wind_max: int = SimConstants.WIND_MAX
## Credits every tank starts the match with (clamped 0..1,000,000 by new_match).
var start_money: int = SimConstants.DEFAULT_START_MONEY
## False locks every "full" tier catalog entry in the shop (section 17).
var full_unlocked: bool = true
## One controller per tank (SimConstants.CTRL_*, section 27). Defaults to all human; new_match
## resizes it to num_tanks (padding with human) and clamps the values.
var controllers: PackedInt32Array = _all_human()
## SimConstants.MODE_STANDARD or MODE_LOVE (section 37).
var mode: int = SimConstants.MODE_STANDARD


static func _all_human() -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(SimConstants.MAX_TANKS)
	c.fill(SimConstants.CTRL_HUMAN)
	return c


func duplicate_settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed
	s.num_tanks = num_tanks
	s.rounds = rounds
	s.wind_max = wind_max
	s.start_money = start_money
	s.full_unlocked = full_unlocked
	s.controllers = controllers.duplicate()
	s.mode = mode
	return s


## A copy with every value forced into its legal range (section 23).
func clamped() -> MatchSettings:
	var s: MatchSettings = duplicate_settings()
	s.num_tanks = clampi(num_tanks, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	s.rounds = clampi(rounds, SimConstants.MIN_ROUNDS, SimConstants.MAX_ROUNDS)
	s.wind_max = clampi(wind_max, 0, SimConstants.WIND_MAX)
	s.start_money = clampi(start_money, 0, SimConstants.MAX_START_MONEY)
	s.mode = clampi(mode, SimConstants.MODE_STANDARD, SimConstants.MODE_MAX)
	# Love mode (section 37): a fixed duel. Applied before the free caps and the controller resize.
	if s.mode == SimConstants.MODE_LOVE:
		s.num_tanks = 2
		s.rounds = 1
		s.wind_max = mini(s.wind_max, SimConstants.LOVE_WIND_MAX)
		s.start_money = 0
	# Free version: at most 4 tanks and 5 rounds (section 32). Applied before the controller resize.
	if not s.full_unlocked:
		s.num_tanks = mini(s.num_tanks, SimConstants.FREE_MAX_TANKS)
		s.rounds = mini(s.rounds, SimConstants.FREE_MAX_ROUNDS)
	# Hard/Expert are full-version only (section 27).
	var top: int = SimConstants.CTRL_MAX if s.full_unlocked else SimConstants.CTRL_FREE_MAX
	var c := PackedInt32Array()
	c.resize(s.num_tanks)
	for i: int in range(s.num_tanks):
		var v: int = controllers[i] if i < controllers.size() else SimConstants.CTRL_HUMAN
		c[i] = clampi(v, SimConstants.CTRL_HUMAN, top)
	s.controllers = c
	return s
