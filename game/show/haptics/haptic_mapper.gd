class_name HapticMapper
extends RefCounted
## Timeline event -> vibration pattern (docs/ARCHITECTURE.md section 33a). Pure and static: no node, no
## device, so the mapping is unit-testable.
##
## It reads the same events the AudioDirector reads. An event first becomes a sound key through
## AudioDirector.sound_for_event(), then the key becomes a pattern, so a new sound never needs a second
## decision here: a key that is not in PATTERNS is silent for the hand, and a test makes sure every
## AudioDirector sound is listed either in PATTERNS or in NO_VIBRATION.
##
## A pattern is {"pri": int, "pulses": Array[Vector3]} where a pulse is
## Vector3(delay_ms from the start of the pattern, duration_ms, amplitude 0..1).
## `pri` (1..5) decides which pattern wins when two overlap and which are exempt from the rate limit.

## Rumble class: the pattern is allowed to overrule the rate limit (nuke blasts and a tank dying are rare).
const PRI_RUMBLE: int = 5

## Light pulses stay at 15-30 ms ("a tick"), impacts grow with the explosion size, and the two rumbles chain
## decaying pulses so the whole phone shakes for about half a second.
const PATTERNS: Dictionary = {
	"fire_light": {"pri": 1, "pulses": [Vector3(0, 15, 0.3)]},
	"fire_medium": {"pri": 1, "pulses": [Vector3(0, 22, 0.4)]},
	"fire_heavy": {"pri": 1, "pulses": [Vector3(0, 30, 0.5)]},
	"beam_zap": {"pri": 1, "pulses": [Vector3(0, 25, 0.4)]},
	"shield_hit": {"pri": 1, "pulses": [Vector3(0, 15, 0.3)]},
	"shield_break": {"pri": 2, "pulses": [Vector3(0, 35, 0.6)]},
	"explosion_small": {"pri": 2, "pulses": [Vector3(0, 25, 0.5)]},
	"explosion_medium": {"pri": 3, "pulses": [Vector3(0, 45, 0.7)]},
	"explosion_large": {"pri": 4, "pulses": [Vector3(0, 70, 0.85), Vector3(100, 45, 0.6)]},
	"explosion_nuke": {"pri": 5, "pulses": [
		Vector3(0, 100, 1.0), Vector3(120, 80, 0.95), Vector3(220, 70, 0.85), Vector3(310, 60, 0.7),
		Vector3(400, 50, 0.55), Vector3(480, 40, 0.4)]},
	"tank_destroyed": {"pri": 5, "pulses": [
		Vector3(0, 120, 1.0), Vector3(140, 90, 0.9), Vector3(250, 70, 0.75), Vector3(340, 55, 0.55),
		Vector3(420, 40, 0.4)]},
	# Sudden death begins: four hard pulses in the rhythm of the klaxon, rumble class so nothing cuts it short.
	"sudden_death": {"pri": 5, "pulses": [
		Vector3(0, 160, 1.0), Vector3(240, 110, 0.9), Vector3(480, 160, 1.0), Vector3(720, 90, 0.7)]},
	# Love Edition: only the win has a pulse, a gentle double heartbeat (lub-dub, twice).
	"love_win": {"pri": 3, "pulses": [
		Vector3(0, 40, 0.4), Vector3(150, 55, 0.3), Vector3(850, 40, 0.35), Vector3(1000, 55, 0.25)]},
}

## Sounds that deliberately do not vibrate (everything else the AudioDirector can play).
const NO_VIBRATION: PackedStringArray = [
	"terrain_crumble", "dirt_thud", "sludge_pour", "fire_crackle", "well_hum", "anchor_clank",
	"shield_up", "repulsor_pulse", "chute_pop", "repair_chime", "money_gain", "money_loss",
	"round_win", "match_win", "turn_blip", "cpu_think_tick",
	"ui_tap", "ui_back", "ui_purchase", "ui_locked",
	"love_fire", "heart_burst", "love_found",
]


## The pattern for a timeline event, or {} for none. `love` is true in a Love Edition match: there only the
## win vibrates (hearts never rumble, even if a standard event slipped in).
static func for_event(e: Dictionary, match_over: bool = false, love: bool = false) -> Dictionary:
	return for_sound(AudioDirector.sound_for_event(e, match_over, love), love)


## The pattern for an AudioDirector sound key, or {}.
static func for_sound(key: String, love: bool = false) -> Dictionary:
	if not PATTERNS.has(key):
		return {}
	if love and key != "love_win":
		return {}
	if not love and key == "love_win":
		return {}
	return PATTERNS[key] as Dictionary


## Total vibrating time of a pattern in ms (what the rate limit budgets).
static func on_time_ms(pattern: Dictionary) -> int:
	var total: int = 0
	for p: Vector3 in (pattern.get("pulses", []) as Array):
		total += int(p.y)
	return total


## When the last pulse of the pattern ends, in ms after its start.
static func length_ms(pattern: Dictionary) -> int:
	var end: int = 0
	for p: Vector3 in (pattern.get("pulses", []) as Array):
		end = maxi(end, int(p.x) + int(p.y))
	return end
