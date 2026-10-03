class_name CpuDriver
extends RefCounted
## Book-keeping and timing for one computer-controlled turn, so the battle controller only has to
## ask "what next?". The decision itself is AiPlayer's (pure and deterministic); everything here
## is presentation, so floats are fine.
##
## A turn is a few steps, each one frame apart at least:
##   COMPUTE  one frame after the turn starts (so the "thinking" banner is on screen), ask the AI
##   THINK    a short pause, 0.5-1.2 s, as if a person were looking at the field
##   SWEEP    turret and power readout glide to the chosen values, 0.6-1.0 s (fire actions only)
##   ACT      submit the action through the normal path
## A non-turn-ending action (shield, repulsor, move) is followed by a new COMPUTE for the same
## turn. The pauses are "seeded from the turn": the same match shows the same pauses.

enum Stage { IDLE, COMPUTE, THINK, SWEEP, ACT }

const THINK_MIN: float = 0.5
const THINK_MAX: float = 1.2
const SWEEP_MIN: float = 0.6
const SWEEP_MAX: float = 1.0
## Follow-up actions in the same turn (the shot after a shield) wait a little less.
const FOLLOW_UP: float = 0.6
## The AI promises a turn-ending action within 3 calls; the 4th call forces a pass.
const MAX_CALLS: int = 4
## Rng tag of the visual dice: never shared with the AI's own streams.
const VISUAL_TAG: int = 0x5E7A

var stage: Stage = Stage.IDLE
var tank: int = -1
var key: int = -1
## How many times the AI was asked in this turn.
var calls: int = 0
## Frames to wait before the next stage (the "frame yield").
var wait_frames: int = 0
## Seconds at normal speed: what is left of a THINK, how far a SWEEP has come.
var timer: float = 0.0
var duration: float = 0.0
## The AI's pending action.
var action: Dictionary = {}
var from_angle: int = 0
var from_power: int = 0


func is_active() -> bool:
	return stage != Stage.IDLE


## Starts (or restarts, after a non-turn-ending action) the computer's turn for `id`.
func begin(id: int, turn_key: int) -> void:
	if id != tank or turn_key != key:
		calls = 0
	tank = id
	key = turn_key
	stage = Stage.COMPUTE
	wait_frames = 1
	action = {}
	timer = 0.0
	duration = 0.0


func stop() -> void:
	stage = Stage.IDLE
	tank = -1
	key = -1
	calls = 0
	action = {}


## One number per (match, round, turn, tank): the same on every device and every replay.
static func turn_key_of(state: MatchState, id: int) -> int:
	return state.round_index * 1000000 + state.turn_number * 16 + id


## A deterministic 0..1 roll for the pauses; `salt` tells THINK from SWEEP.
static func roll(state: MatchState, id: int, salt: int) -> float:
	var r: Rng = Rng.derive(state.seed, VISUAL_TAG + id).fork(state.round_index * 100000 + state.turn_number * 16 + salt)
	return float(r.range_int(0, 1000)) / 1000.0


## Think pause in seconds at normal speed for call number `call_no` (1-based) of the turn.
static func think_seconds(state: MatchState, id: int, call_no: int) -> float:
	var t: float = lerpf(THINK_MIN, THINK_MAX, roll(state, id, 1 + call_no))
	return t if call_no <= 1 else t * FOLLOW_UP


## Turret/power sweep length in seconds at normal speed.
static func sweep_seconds(state: MatchState, id: int) -> float:
	return lerpf(SWEEP_MIN, SWEEP_MAX, roll(state, id, 9))


## How much real time one second of CPU "acting" takes: the settings level (Normal 1, Fast
## 0.35, Instant 0) divided by the 1x/2x speed toggle. 0 means "do not wait at all".
static func wait_scale(setting_scale: float, speed: float, instant: bool) -> float:
	if instant:
		return 0.0
	return setting_scale / maxf(speed, 0.1)


## True for an action that ends the turn (fire, pass, repair).
static func ends_turn(a: Dictionary) -> bool:
	var kind: String = a.get("kind", "")
	return kind == "fire" or kind == "pass" or (kind == "use_item" and a.get("item", "") == "nanorepair_kit")


## Eased 0..1 for the sweep.
static func ease_sweep(k: float) -> float:
	var c: float = clampf(k, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)
