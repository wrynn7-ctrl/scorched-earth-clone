class_name MatchSettings
extends RefCounted
## Parameters chosen before a match starts. Later milestones add fields here.

@warning_ignore("shadowed_global_identifier")
var seed: int = 0
var num_tanks: int = 2
var rounds: int = 1
var wind_max: int = SimConstants.WIND_MAX


func duplicate_settings() -> MatchSettings:
	var s := MatchSettings.new()
	s.seed = seed
	s.num_tanks = num_tanks
	s.rounds = rounds
	s.wind_max = wind_max
	return s
