class_name ShowSettings
extends RefCounted
## Global presentation switches (accessibility). The settings screen writes these;
## show-layer nodes only read them. Floats/visual-only, never touches the simulation.

## Master "reduce motion" flag: disables camera shake and large animated motion.
static var reduce_motion: bool = false
## Dim the bright explosion flash for flash-sensitive players.
static var reduce_flashing: bool = false
## Separate user toggle for camera shake (on by default).
static var screen_shake: bool = true


static func shake_enabled() -> bool:
	return screen_shake and not reduce_motion


static func reset() -> void:
	reduce_motion = false
	reduce_flashing = false
	screen_shake = true
