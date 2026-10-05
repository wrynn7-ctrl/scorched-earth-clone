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
## Team per tank (section 39): empty = no teams (every tank is its own team, team = id), otherwise
## num_tanks entries 0..3 with at least 2 distinct values. Not allowed in love mode.
var teams: PackedInt32Array = PackedInt32Array()
## Whether teammates can hurt each other. Only meaningful with teams (section 39).
var friendly_fire: bool = true


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
	s.teams = teams.duplicate()
	s.friendly_fire = friendly_fire
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
	s.teams = _clamped_teams(s)
	return s


## Section 39 clamp: teams that are not usable are dropped (no teams). A list longer than
## num_tanks (num_tanks was just capped) is cut to size first. The settings passed in already have
## their final num_tanks and mode.
static func _clamped_teams(s: MatchSettings) -> PackedInt32Array:
	if s.mode == SimConstants.MODE_LOVE or s.teams.size() < s.num_tanks:
		return PackedInt32Array()
	var t: PackedInt32Array = s.teams.slice(0, s.num_tanks)
	if teams_error(t, s.num_tanks) != "":
		return PackedInt32Array()
	return t


## "" if `t` is a legal team list for `n` tanks (empty, or n entries 0..3 with >= 2 distinct), else
## "invalid_settings".
static func teams_error(t: PackedInt32Array, n: int) -> String:
	if t.is_empty():
		return ""
	if t.size() != n:
		return "invalid_settings"
	var seen: int = 0
	for v: int in t:
		if v < 0 or v >= SimConstants.MAX_TEAMS:
			return "invalid_settings"
		seen |= 1 << v
	# at least two distinct teams: seen must not be a single bit
	if (seen & (seen - 1)) == 0:
		return "invalid_settings"
	return ""


## Strict check of the settings as they are (no clamping): "" or "invalid_settings" for a bad team
## list (wrong length, value outside 0..3, a single team) or teams in love mode.
func validate() -> String:
	if mode == SimConstants.MODE_LOVE and not teams.is_empty():
		return "invalid_settings"
	return teams_error(teams, num_tanks)


## True if teams are in use.
func has_teams() -> bool:
	return not teams.is_empty()


## The team of tank `id` under these settings (the id itself without teams).
func team_of(id: int) -> int:
	return teams[id] if id >= 0 and id < teams.size() else id
