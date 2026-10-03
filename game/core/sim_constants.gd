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

## Phases (section 16). PHASE_ROUND_OVER is no longer produced by the core (kept for compatibility).
const PHASE_SHOP: String = "shop"
const PHASE_AIM: String = "aim"
const PHASE_ROUND_OVER: String = "round_over"
const PHASE_MATCH_OVER: String = "match_over"

## Settings limits (section 23).
const MIN_ROUNDS: int = 1
const MAX_ROUNDS: int = 20
const MAX_START_MONEY: int = 1_000_000
const DEFAULT_START_MONEY: int = 10000
## Free-version caps (section 32), enforced while `full_unlocked` is false.
const FREE_MAX_TANKS: int = 4
const FREE_MAX_ROUNDS: int = 5

## Controllers (section 27): who plays a tank. Hard and Expert are full-version only.
const CTRL_HUMAN: int = 0
const CTRL_EASY: int = 1
const CTRL_NORMAL: int = 2
const CTRL_HARD: int = 3
const CTRL_EXPERT: int = 4
const CTRL_MAX: int = CTRL_EXPERT
## Highest controller allowed while `full_unlocked` is false.
const CTRL_FREE_MAX: int = CTRL_NORMAL

## Economy (section 18).
const CREDIT_PER_HP: int = 15
const KILL_BONUS: int = 1500
const SURVIVE_PAY: int = 1000
const WIN_PAY: int = 2500
const INVENTORY_CAP: int = 99

## Movement (section 20). START_FUEL is not in the contract: tanks start with no fuel.
const START_FUEL: int = 0
const MOVE_MAX_DX: int = 200
const MAX_CLIMB: int = 3  # steps up by more than this are blocked
const WALK_DROP: int = 3  # per-step drops up to this are walking, not falling

## Shields and repulsors (section 20). The bubble is centred at (x, y - SHIELD_CENTER_DY).
const SHIELD_RADIUS: int = 24
const SHIELD_CENTER_DY: int = 6
const REPULSOR_RADIUS: int = 60
const REPULSOR_PUSH: int = 131072  # 2.00 cell/tick^2 at the centre, Q16.16 (tuned in M3-C2)
const REPULSOR_CHARGE: int = 100
const REPAIR_HEAL: int = 40
