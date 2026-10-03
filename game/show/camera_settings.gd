class_name CameraSettings
extends RefCounted
## Camera preferences, kept apart from ShowSettings (which the audio work is editing).
## `follow_shots` is the Settings toggle "Camera follows shots" (default ON). Persistence:
## SettingsStore (or a later settings rework) calls load_from()/save_to() with its ConfigFile.

const SECTION: String = "show"
const KEY_FOLLOW: String = "camera_follow"

static var follow_shots: bool = true


## True when the camera should actually move for shots: the toggle is on and reduce motion is
## off (reduce motion falls back to the off-screen marker only).
static func follow_active() -> bool:
	return follow_shots and not ShowSettings.reduce_motion


static func reset() -> void:
	follow_shots = true


static func load_from(cfg: ConfigFile) -> void:
	var v: Variant = cfg.get_value(SECTION, KEY_FOLLOW, follow_shots)
	follow_shots = v as bool if typeof(v) == TYPE_BOOL else follow_shots


static func save_to(cfg: ConfigFile) -> void:
	cfg.set_value(SECTION, KEY_FOLLOW, follow_shots)
