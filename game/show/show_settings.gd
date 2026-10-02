class_name ShowSettings
extends RefCounted
## Global presentation switches (accessibility). The settings screen writes these;
## show-layer nodes only read them. Floats/visual-only, never touches the simulation.
## Persistence lives in game/platform/settings_store.gd.

## Trajectory preview modes (PLAN 3.5). More modes (long, full) come later.
const PREVIEW_OFF: int = 0
const PREVIEW_SHORT: int = 1

## Text size limits, in percent (step 10).
const TEXT_SIZE_MIN: int = 80
const TEXT_SIZE_MAX: int = 150
const TEXT_SIZE_STEP: int = 10

## Master "reduce motion" flag: disables camera shake and large animated motion.
static var reduce_motion: bool = false
## Dim the bright explosion flash for flash-sensitive players.
static var reduce_flashing: bool = false
## Separate user toggle for camera shake (on by default).
static var screen_shake: bool = true
## Vibrate on explosions (Android only; no-op elsewhere).
static var haptics: bool = true
## Aiming aid: PREVIEW_OFF or PREVIEW_SHORT.
static var trajectory_preview: int = PREVIEW_SHORT
## Playback speed multiplier for timelines (1.0 or 2.0).
static var playback_speed: float = 1.0
## UI text size in percent (80..150). Applied through UiScale.text_scale.
static var text_size: int = 100


static func shake_enabled() -> bool:
	return screen_shake and not reduce_motion


## Clamps to 80..150 in steps of 10, stores it and updates UiScale.text_scale.
static func set_text_size(percent: int) -> void:
	var snapped_pct: int = roundi(float(percent) / float(TEXT_SIZE_STEP)) * TEXT_SIZE_STEP
	text_size = clampi(snapped_pct, TEXT_SIZE_MIN, TEXT_SIZE_MAX)
	UiScale.text_scale = float(text_size) / 100.0


static func reset() -> void:
	reduce_motion = false
	reduce_flashing = false
	screen_shake = true
	haptics = true
	trajectory_preview = PREVIEW_SHORT
	playback_speed = 1.0
	set_text_size(100)
