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

## CPU turn speed levels (the settings screen cycles through them).
const CPU_SPEED_NORMAL: int = 0
const CPU_SPEED_FAST: int = 1
const CPU_SPEED_INSTANT: int = 2
## Multiplier on the CPU's think and sweep times for each level (0 = no waiting at all).
const CPU_SPEED_SCALE: Array[float] = [1.0, 0.35, 0.0]

## Default sound volumes (percent).
const DEFAULT_SFX_VOLUME: int = 80
const DEFAULT_MUSIC_VOLUME: int = 70

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
## How fast computer opponents think and aim: CPU_SPEED_NORMAL / _FAST / _INSTANT.
static var cpu_turn_speed: int = CPU_SPEED_NORMAL
## Sound (docs/ARCHITECTURE.md section 33): volumes 0-100 and switches. The AudioDirector applies them to its buses.
static var sfx_volume: int = DEFAULT_SFX_VOLUME
static var sfx_on: bool = true
static var music_volume: int = DEFAULT_MUSIC_VOLUME
static var music_on: bool = true
static var ui_sounds: bool = true
## Left-handed battle HUD: power slider + FIRE on the left, angle panel + move on the right.
static var left_handed: bool = false


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
	cpu_turn_speed = CPU_SPEED_NORMAL
	sfx_volume = DEFAULT_SFX_VOLUME
	sfx_on = true
	music_volume = DEFAULT_MUSIC_VOLUME
	music_on = true
	ui_sounds = true
	left_handed = false
	CameraSettings.reset()
	set_text_size(100)
	# The last-used match setup is reset with the rest so tests never leak it into each other.
	SetupPrefs.reset()


## The wait multiplier for the current CPU turn speed setting.
static func cpu_speed_scale() -> float:
	return CPU_SPEED_SCALE[clampi(cpu_turn_speed, 0, CPU_SPEED_SCALE.size() - 1)]
