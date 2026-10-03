class_name AiSituation
extends RefCounted
## Everything the AI works out once per decision and then hands around: the state, the
## shooter, the chosen target, the aiming context and the plain (spark/pulse-style) solution
## for hitting the target from here. Built by AiPlayer, read by AiWeapons.

var state: MatchState
var me: TankState
var level: int = 2
var prof: Dictionary = {}
var rng: Rng
var target: TankState
var enemies: Array[TankState] = []
var ctx: AimSolver.Ctx
var flight: AiFlight
## Preferred launch angle, tenths of a degree from the horizontal towards the target.
var a0: int = 450
## Model-only solution aimed at the target's x (see AimSolver.solve_direct). ok = false means
## "blocked or out of range".
var direct: Dictionary = {}
## Correction from the last shot at this target, or {} (see AiPlayer.correction_for).
var corr: Dictionary = {}
var dist: int = 0
## True when the last shot at this target went out at (nearly) full power and still came down well short
## of it: no power can fix that, whatever the model believes about the wind (see AiPlayer.spent_short).
var spent_short: bool = false
## Id of the enemy closest to this tank (a Seeker locks on to that one).
var nearest_id: int = -1
## Verified aim solutions already worked out in this decision, by "aim_x/physics/corrected", so
## that weapons with the same flight do not search (or trace) twice.
var memo: Dictionary = {}


func owns(weapon_id: String) -> bool:
	if WeaponDefs.get_def(weapon_id).get("unlimited", false):
		return true
	return me.stock_of(weapon_id) > 0
