class_name CameraShake
extends Camera2D
## Camera2D with a subtle, decaying trauma-based shake. Idle cost is zero (processing is
## switched off until shake() is called). Respects ShowSettings (reduce_motion, screen_shake).

## Maximum offset in world units at intensity 1.0.
@export var max_offset: float = 14.0
## How fast trauma decays per second.
@export var decay: float = 1.8

var _trauma: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	set_process(false)


## intensity in 0..1 (an explosion of radius 28 is about 0.35). Adds to current trauma.
func shake(intensity: float) -> void:
	if not ShowSettings.shake_enabled():
		return
	_trauma = minf(1.0, _trauma + clampf(intensity, 0.0, 1.0))
	set_process(true)


func is_shaking() -> bool:
	return _trauma > 0.0


func _process(delta: float) -> void:
	_time += delta
	_trauma = maxf(0.0, _trauma - decay * delta)
	if _trauma <= 0.0 or not ShowSettings.shake_enabled():
		_trauma = 0.0
		offset = Vector2.ZERO
		set_process(false)
		return
	var amp: float = _trauma * _trauma * max_offset
	offset = Vector2(sin(_time * 61.0), sin(_time * 83.0 + 1.7)) * amp
