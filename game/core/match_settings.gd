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


func duplicate_settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed
	s.num_tanks = num_tanks
	s.rounds = rounds
	s.wind_max = wind_max
	s.start_money = start_money
	s.full_unlocked = full_unlocked
	return s


## A copy with every value forced into its legal range (section 23).
func clamped() -> MatchSettings:
	var s: MatchSettings = duplicate_settings()
	s.num_tanks = clampi(num_tanks, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	s.rounds = clampi(rounds, SimConstants.MIN_ROUNDS, SimConstants.MAX_ROUNDS)
	s.wind_max = clampi(wind_max, 0, SimConstants.WIND_MAX)
	s.start_money = clampi(start_money, 0, SimConstants.MAX_START_MONEY)
	return s
