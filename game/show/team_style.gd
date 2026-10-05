class_name TeamStyle
extends RefCounted
## How a team looks (ARCHITECTURE section 42): A cyan, B magenta, C lime, D amber, always with its letter
## so colour is never the only cue. Team numbers are the core's 0..3 (SimConstants.MAX_TEAMS); `NONE` (-1)
## is "no team" (the setup chip's dash). Presentation only.

const NONE: int = -1
const COUNT: int = SimConstants.MAX_TEAMS
const LETTERS: PackedStringArray = ["A", "B", "C", "D"]
const COLORS: Array[Color] = [
	Color(0.0, 0.929, 1.0),     # A cyan
	Color(1.0, 0.18, 0.62),     # B magenta
	Color(0.62, 1.0, 0.2),      # C lime
	Color(1.0, 0.72, 0.1),      # D amber
]
## Text on a team-coloured badge: the dark backdrop colour reads on all four.
const INK: Color = NeonPalette.BG_DEEP
## Colour of the "no team" chip.
const NONE_COLOR: Color = NeonPalette.TEXT_DIM


static func is_team(team: int) -> bool:
	return team >= 0 and team < COUNT


static func letter(team: int) -> String:
	return LETTERS[team] if is_team(team) else "—"


static func color(team: int) -> Color:
	return COLORS[team] if is_team(team) else NONE_COLOR


## "TEAM A" (translated).
static func team_name(team: int) -> String:
	return TranslationServer.translate("TEAM_NAME_FMT") % letter(team)


## The next chip value when tapped: none, A, B, C, D, none, ...
static func next(team: int) -> int:
	return team + 1 if team + 1 < COUNT else NONE
