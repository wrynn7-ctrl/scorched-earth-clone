class_name SettingsStore
extends RefCounted
## Persists ShowSettings to `user://settings.cfg` (ConfigFile). Values are validated on
## load, so a hand-edited or damaged file can never put the UI in an impossible state.

const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "show"

## Where load/save go. Tests point this at a scratch file.
static var path: String = DEFAULT_PATH
## Headless runs (the test suite) must not read the developer's real settings, so
## ensure_loaded() does nothing there unless a test sets this.
static var allow_headless_load: bool = false

static var _loaded: bool = false


## Loads the settings once per process (title and battle both call this on start).
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if DisplayServer.get_name() == "headless" and not allow_headless_load:
		return
	load_into()


## Test hook: forget that the settings were loaded.
static func forget_loaded() -> void:
	_loaded = false


## Reads the file into ShowSettings. Returns false when there is no usable file (the
## current values are kept).
static func load_into(file_path: String = "") -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(file_path if file_path != "" else path) != OK:
		return false
	ShowSettings.haptics = _bool(cfg, "haptics", ShowSettings.haptics)
	ShowSettings.screen_shake = _bool(cfg, "screen_shake", ShowSettings.screen_shake)
	ShowSettings.reduce_flashing = _bool(cfg, "reduce_flashing", ShowSettings.reduce_flashing)
	ShowSettings.reduce_motion = _bool(cfg, "reduce_motion", ShowSettings.reduce_motion)
	var preview: Variant = cfg.get_value(SECTION, "trajectory_preview", ShowSettings.trajectory_preview)
	if typeof(preview) == TYPE_INT:
		ShowSettings.trajectory_preview = ShowSettings.PREVIEW_SHORT if (preview as int) != ShowSettings.PREVIEW_OFF else ShowSettings.PREVIEW_OFF
	var speed: Variant = cfg.get_value(SECTION, "playback_speed", ShowSettings.playback_speed)
	if typeof(speed) == TYPE_FLOAT or typeof(speed) == TYPE_INT:
		ShowSettings.playback_speed = 2.0 if float(speed) >= 1.5 else 1.0
	var size: Variant = cfg.get_value(SECTION, "text_size", ShowSettings.text_size)
	if typeof(size) == TYPE_INT or typeof(size) == TYPE_FLOAT:
		ShowSettings.set_text_size(int(size))
	return true


## Writes the current ShowSettings. Returns true on success.
static func save(file_path: String = "") -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "haptics", ShowSettings.haptics)
	cfg.set_value(SECTION, "screen_shake", ShowSettings.screen_shake)
	cfg.set_value(SECTION, "reduce_flashing", ShowSettings.reduce_flashing)
	cfg.set_value(SECTION, "reduce_motion", ShowSettings.reduce_motion)
	cfg.set_value(SECTION, "trajectory_preview", ShowSettings.trajectory_preview)
	cfg.set_value(SECTION, "playback_speed", ShowSettings.playback_speed)
	cfg.set_value(SECTION, "text_size", ShowSettings.text_size)
	return cfg.save(file_path if file_path != "" else path) == OK


static func delete(file_path: String = "") -> void:
	var p: String = file_path if file_path != "" else path
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


static func _bool(cfg: ConfigFile, key: String, fallback: bool) -> bool:
	var v: Variant = cfg.get_value(SECTION, key, fallback)
	return v as bool if typeof(v) == TYPE_BOOL else fallback
