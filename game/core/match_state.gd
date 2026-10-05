class_name MatchState
extends RefCounted
## Complete mutable state of a match. Only Simulation mutates it.

var settings: MatchSettings = MatchSettings.new()
@warning_ignore("shadowed_global_identifier")
var seed: int = 0
var round_index: int = 0
var terrain: Terrain = null
var tanks: Array[TankState] = []
var wind: int = 0
## State of the round's wind stream (4 words), so wind drift survives save/load.
var wind_rng_state: PackedInt64Array = PackedInt64Array([0, 0, 0, 0])
var current_tank: int = 0
var turn_number: int = 0
var phase: String = SimConstants.PHASE_AIM
## Active gravity wells {owner, x, y, expires_turn}, kept in owner order (section 21).
var wells: Array[Dictionary] = []
## Turn-order cycles completed since sudden death began this round (section 40); reset at round start.
var sudden_death_cycles: int = 0


## Deep copy (terrain bytes included).
func duplicate_state() -> MatchState:
	var s := MatchState.new()
	s.settings = settings.duplicate_settings()
	s.seed = seed
	s.round_index = round_index
	s.terrain = null if terrain == null else terrain.duplicate_terrain()
	for t: TankState in tanks:
		s.tanks.append(t.duplicate_tank())
	s.wind = wind
	s.wind_rng_state = wind_rng_state.duplicate()
	s.current_tank = current_tank
	s.turn_number = turn_number
	s.phase = phase
	for w: Dictionary in wells:
		s.wells.append(w.duplicate())
	s.sudden_death_cycles = sudden_death_cycles
	return s
