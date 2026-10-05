class_name SettingsStore
extends RefCounted
## Persists ShowSettings to `user://settings.cfg` (ConfigFile). Values are validated on
## load, so a hand-edited or damaged file can never put the UI in an impossible state.

const DEFAULT_PATH: String = "user://settings.cfg"
const SECTION: String = "show"
## The last-used match setup (SetupPrefs) lives in its own section.
const SETUP_SECTION: String = "setup"
## The Love Edition's own little setup (player 2).
const LOVE_SECTION: String = "love"

## Where load/save go. Tests point this at a scratch file.
static var path: String = DEFAULT_PATH
## Headless runs (the test suite) must not read the developer's real settings, so
## ensure_loaded() does nothing there unless a test sets this.
static var allow_headless_load: bool = false

## The Love Edition secret was found (ARCHITECTURE section 37). It lives here, not in ShowSettings,
## so "reset settings" can never hide the button again.
static var love_found: bool = false

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
	var cpu: Variant = cfg.get_value(SECTION, "cpu_turn_speed", ShowSettings.cpu_turn_speed)
	if typeof(cpu) == TYPE_INT or typeof(cpu) == TYPE_FLOAT:
		ShowSettings.cpu_turn_speed = clampi(int(cpu), ShowSettings.CPU_SPEED_NORMAL, ShowSettings.CPU_SPEED_INSTANT)
	ShowSettings.sfx_volume = _volume(cfg, "sfx_volume", ShowSettings.sfx_volume)
	ShowSettings.sfx_on = _bool(cfg, "sfx_on", ShowSettings.sfx_on)
	ShowSettings.music_volume = _volume(cfg, "music_volume", ShowSettings.music_volume)
	ShowSettings.music_on = _bool(cfg, "music_on", ShowSettings.music_on)
	ShowSettings.ui_sounds = _bool(cfg, "ui_sounds", ShowSettings.ui_sounds)
	ShowSettings.left_handed = _bool(cfg, "left_handed", ShowSettings.left_handed)
	love_found = _bool(cfg, "love_found", love_found)
	CameraSettings.load_from(cfg)
	_load_setup(cfg)
	var love_cpu: Variant = cfg.get_value(LOVE_SECTION, "cpu", SetupPrefs.love_cpu)
	if typeof(love_cpu) == TYPE_INT or typeof(love_cpu) == TYPE_FLOAT:
		SetupPrefs.love_cpu = clampi(int(love_cpu), SimConstants.CTRL_HUMAN, SimConstants.CTRL_MAX)
	_apply_audio()
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
	cfg.set_value(SECTION, "cpu_turn_speed", ShowSettings.cpu_turn_speed)
	cfg.set_value(SECTION, "sfx_volume", ShowSettings.sfx_volume)
	cfg.set_value(SECTION, "sfx_on", ShowSettings.sfx_on)
	cfg.set_value(SECTION, "music_volume", ShowSettings.music_volume)
	cfg.set_value(SECTION, "music_on", ShowSettings.music_on)
	cfg.set_value(SECTION, "ui_sounds", ShowSettings.ui_sounds)
	cfg.set_value(SECTION, "left_handed", ShowSettings.left_handed)
	cfg.set_value(SECTION, "love_found", love_found)
	CameraSettings.save_to(cfg)
	if SetupPrefs.love_cpu != 0:
		cfg.set_value(LOVE_SECTION, "cpu", SetupPrefs.love_cpu)
	if SetupPrefs.has_saved:
		cfg.set_value(SETUP_SECTION, "players", SetupPrefs.players)
		cfg.set_value(SETUP_SECTION, "rounds", SetupPrefs.rounds)
		cfg.set_value(SETUP_SECTION, "money_level", SetupPrefs.money_level)
		cfg.set_value(SETUP_SECTION, "wind_level", SetupPrefs.wind_level)
		cfg.set_value(SETUP_SECTION, "controllers", SetupPrefs.controllers_array())
		cfg.set_value(SETUP_SECTION, "watch", SetupPrefs.watch)
		cfg.set_value(SETUP_SECTION, "theme", SetupPrefs.theme)
		cfg.set_value(SETUP_SECTION, "names", SetupPrefs.names_array())
		cfg.set_value(SETUP_SECTION, "teams", SetupPrefs.teams_array())
		cfg.set_value(SETUP_SECTION, "friendly_fire", SetupPrefs.friendly_fire)
	return cfg.save(file_path if file_path != "" else path) == OK


## Reads the [setup] section. It is all-or-nothing: a file without it leaves the defaults, and
## every value is clamped to what the setup screen can show.
static func _load_setup(cfg: ConfigFile) -> void:
	if not cfg.has_section(SETUP_SECTION):
		return
	SetupPrefs.has_saved = true
	SetupPrefs.players = _int_in(cfg, "players", SetupPrefs.players, SimConstants.MIN_TANKS, SimConstants.MAX_TANKS)
	SetupPrefs.rounds = _int_in(cfg, "rounds", SetupPrefs.rounds, SimConstants.MIN_ROUNDS, SimConstants.MAX_ROUNDS)
	SetupPrefs.money_level = _int_in(cfg, "money_level", SetupPrefs.money_level, 0, 2)
	SetupPrefs.wind_level = _int_in(cfg, "wind_level", SetupPrefs.wind_level, 0, 3)
	SetupPrefs.set_controllers_from(cfg.get_value(SETUP_SECTION, "controllers", []))
	var watch: Variant = cfg.get_value(SETUP_SECTION, "watch", false)
	SetupPrefs.watch = watch as bool if typeof(watch) == TYPE_BOOL else false
	SetupPrefs.theme = ThemeDefs.sanitize(cfg.get_value(SETUP_SECTION, "theme", ThemeDefs.DEFAULT_ID))
	SetupPrefs.set_names_from(cfg.get_value(SETUP_SECTION, "names", []))
	SetupPrefs.set_teams_from(cfg.get_value(SETUP_SECTION, "teams", []))
	var ff: Variant = cfg.get_value(SETUP_SECTION, "friendly_fire", true)
	SetupPrefs.friendly_fire = ff as bool if typeof(ff) == TYPE_BOOL else true


static func _int_in(cfg: ConfigFile, key: String, fallback: int, lo: int, hi: int) -> int:
	var v: Variant = cfg.get_value(SETUP_SECTION, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), lo, hi)
	return fallback


static func delete(file_path: String = "") -> void:
	var p: String = file_path if file_path != "" else path
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)


## A 0-100 volume (anything else keeps `fallback`, out-of-range numbers are clamped).
static func _volume(cfg: ConfigFile, key: String, fallback: int) -> int:
	var v: Variant = cfg.get_value(SECTION, key, fallback)
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		return clampi(int(v), 0, 100)
	return fallback


## Pushes the loaded sound settings into the audio buses (the AudioDirector autoload may not exist, e.g. in a tool script).
static func _apply_audio() -> void:
	var loop: SceneTree = Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null and loop.root.has_node("AudioDirector"):
		loop.root.get_node("AudioDirector").call("apply_settings")


static func _bool(cfg: ConfigFile, key: String, fallback: bool) -> bool:
	var v: Variant = cfg.get_value(SECTION, key, fallback)
	return v as bool if typeof(v) == TYPE_BOOL else fallback
