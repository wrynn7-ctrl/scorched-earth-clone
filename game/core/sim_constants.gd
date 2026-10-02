class_name SimConstants
extends RefCounted
## All tunable simulation numbers live here (docs/ARCHITECTURE.md section 6).

const WORLD_W: int = 1600
const WORLD_H: int = 900

const TICKS_PER_SECOND: int = 60
const GRAVITY: int = 9830  # Q16.16 added to vy each tick (about 0.15 cell/tick^2)
const MAX_SPEED: int = 17 * 65536  # muzzle speed at power 1000
const MAX_POWER: int = 1000
const MIN_POWER: int = 1
const MAX_ANGLE: int = 1800

const WIND_MAX: int = 100
const WIND_ACCEL_PER_UNIT: int = 13  # Q16.16 added to vx per tick per wind unit
const WIND_DRIFT: int = 6
## Sentinel for Ballistics.trace(): use the wind stored in the match state.
const WIND_USE_STATE: int = 1_000_000

const MAX_FLIGHT_TICKS: int = 1500

const TANK_W: int = 24
const TANK_H: int = 12
const BARREL_LEN: int = 14
const MAX_HEALTH: int = 100
const FALL_SAFE: int = 12
const FALL_DMG_DIV: int = 2

const MIN_TANKS: int = 2
const MAX_TANKS: int = 8
const DEFAULT_ANGLE_LEFT: int = 450
const DEFAULT_ANGLE_RIGHT: int = 1350
const DEFAULT_POWER: int = 500

## Random stream tags (see Rng.derive). Spaced so `TAG + round` never collides.
const TAG_TERRAIN: int = 1000
const TAG_WIND: int = 2000
const TAG_PLACEMENT: int = 3000
const TAG_AI: int = 4000

const PHASE_AIM: String = "aim"
const PHASE_ROUND_OVER: String = "round_over"
const PHASE_MATCH_OVER: String = "match_over"
