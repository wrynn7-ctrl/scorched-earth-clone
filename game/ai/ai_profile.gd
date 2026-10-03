class_name AiProfile
extends RefCounted
## Difficulty table of the computer opponents (docs/ARCHITECTURE.md section 29).
##
## Every number that makes one level different from another lives here, in integers
## (per-mille, i.e. 1000 = 100 %). The AI code reads a profile Dictionary and never hard-codes
## a difficulty, so balancing is a matter of editing this file.
##
## How the numbers are used when aiming:
##   wind_use    share of the real wind the AI "believes" when it plans a shot.
##   bias_min/max  a power error (per-mille of the power) that is picked once per round, with a
##               random sign, and then stays the same for every shot of that round. That is
##               what makes Easy "always a bit short" instead of random.
##   noise       extra shot-to-shot jitter of the power (per-mille, roughly a standard deviation).
##   correction  how much of the last miss on the same target is corrected on the next shot (the
##               nominal value; corr_min..corr_max is what a single shot draws from).
##   overshoot / ignore  per-mille chance that a correction goes the wrong way: past the target by
##               about the size of the miss (factor overshoot_min..max), or hardly at all
##               (factor 0..ignore_max, "didn't notice"). Only Easy has them.
##   lost_cut_min/max  after a LOST shell (off the map) the next shot's power is simply cut by this
##               much of the lost shot's power, per-mille, with no look at the exact solution (a
##               big but crude reaction). 0 means "use the ordinary correction" (the M4-F bracketing).
## Levels are the SimConstants.CTRL_* values (1 easy .. 4 expert). A human slot (0) that is
## handed to the AI anyway plays as Normal.

## How a level picks its target.
const TARGET_NEAREST: int = 0
const TARGET_REVENGE: int = 1  # nearest, unless somebody just shot at us
const TARGET_WEAKEST: int = 2
const TARGET_VALUE: int = 3

## When a level raises a shield.
const SHIELD_NEVER: int = 0
const SHIELD_WHEN_HURT: int = 1
const SHIELD_ALWAYS: int = 2

## When a level walks (needs fuel).
const MOVE_NEVER: int = 0
const MOVE_OUT_OF_PIT: int = 1  # only if no shot can reach the target from here
const MOVE_TO_IMPROVE: int = 2

const PROFILES: Dictionary = {
	SimConstants.CTRL_EASY: {
		"name": "easy",
		"wind_use": 0,
		"bias_min": 120, "bias_max": 190,
		"noise": 55,
		"correction": 115, "corr_min": 80, "corr_max": 150,
		"overshoot": 250, "overshoot_min": 1700, "overshoot_max": 2300,
		"ignore": 150, "ignore_max": 30,
		"lost_cut_min": 150, "lost_cut_max": 400,
		"target": TARGET_NEAREST,
		"shield": SHIELD_NEVER, "shield_below": 0,
		"repulsor": false,
		"repair_below": 0,
		"move": MOVE_NEVER,
		"special_weapons": false,
	},
	SimConstants.CTRL_NORMAL: {
		"name": "normal",
		"wind_use": 500,
		"bias_min": 40, "bias_max": 80,
		"noise": 25,
		"correction": 500, "corr_min": 500, "corr_max": 500,
		"overshoot": 0, "overshoot_min": 0, "overshoot_max": 0,
		"ignore": 0, "ignore_max": 0,
		"lost_cut_min": 0, "lost_cut_max": 0,
		"target": TARGET_REVENGE,
		"shield": SHIELD_WHEN_HURT, "shield_below": 50,
		"repulsor": false,
		"repair_below": 0,
		"move": MOVE_NEVER,
		"special_weapons": false,
	},
	SimConstants.CTRL_HARD: {
		"name": "hard",
		"wind_use": 900,
		"bias_min": 20, "bias_max": 36,
		"noise": 14,
		"correction": 800, "corr_min": 800, "corr_max": 800,
		"overshoot": 0, "overshoot_min": 0, "overshoot_max": 0,
		"ignore": 0, "ignore_max": 0,
		"lost_cut_min": 0, "lost_cut_max": 0,
		"target": TARGET_WEAKEST,
		"shield": SHIELD_ALWAYS, "shield_below": 101,
		"repulsor": false,
		"repair_below": 30,
		"move": MOVE_OUT_OF_PIT,
		"special_weapons": true,
	},
	SimConstants.CTRL_EXPERT: {
		"name": "expert",
		"wind_use": 950,
		"bias_min": 12, "bias_max": 24,
		"noise": 12,
		"correction": 1000, "corr_min": 1000, "corr_max": 1000,
		"overshoot": 0, "overshoot_min": 0, "overshoot_max": 0,
		"ignore": 0, "ignore_max": 0,
		"lost_cut_min": 0, "lost_cut_max": 0,
		"target": TARGET_VALUE,
		"shield": SHIELD_ALWAYS, "shield_below": 101,
		"repulsor": true,
		"repair_below": 45,
		"move": MOVE_TO_IMPROVE,
		"special_weapons": true,
	},
}

## Shop wish lists: [catalog id, units to own], bought in this order while the money lasts.
## Easy has no list: it buys a few random cheap things (see AiShop).
const SHOP_NORMAL: Array = [
	["pulse_missile", 10], ["glow_shield", 1], ["hyperpulse", 3], ["drift_chute", 2],
	["prism_splitter", 2], ["nanorepair_kit", 1], ["pulse_missile", 20],
]
const SHOP_HARD: Array = [
	["pulse_missile", 10], ["ion_shield", 1], ["hyperpulse", 6], ["drift_chute", 2],
	["seeker", 2], ["nanorepair_kit", 1], ["glide_orb", 3], ["nova_core", 1],
	["bore_shell", 3], ["fuel_cell", 1], ["pulse_missile", 25],
]
## Expert keeps `reserve` credits back and buys counters on top of this list (AiShop).
const SHOP_EXPERT: Array = [
	["pulse_missile", 10], ["ion_shield", 1], ["hyperpulse", 3], ["drift_chute", 2],
	["nanorepair_kit", 1], ["seeker", 2], ["prism_splitter", 2], ["nova_core", 1],
]
const EXPERT_RESERVE: int = 1500

## Items a random Easy shopper picks from (all cheap, free tier).
const SHOP_EASY_POOL: PackedStringArray = [
	"pulse_missile", "pulse_missile", "pulse_missile", "mound_mortar", "glide_orb",
	"drift_chute", "fuel_cell", "glow_shield", "bore_shell",
]


## The AI level (1..4) that plays tank `tank_id`.
static func level_of(state: MatchState, tank_id: int) -> int:
	var ctrl: PackedInt32Array = state.settings.controllers
	var c: int = SimConstants.CTRL_HUMAN
	if tank_id >= 0 and tank_id < ctrl.size():
		c = ctrl[tank_id]
	if c <= SimConstants.CTRL_HUMAN:
		return SimConstants.CTRL_NORMAL
	return mini(c, SimConstants.CTRL_MAX)


static func for_level(level: int) -> Dictionary:
	return PROFILES[clampi(level, SimConstants.CTRL_EASY, SimConstants.CTRL_EXPERT)]
