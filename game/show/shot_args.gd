class_name ShotArgs
extends RefCounted
## Debug/screenshot command-line options (user args after `--`), shared by the title and battle
## scenes. Parsed once; `parse()` is idempotent and must run before any HUD is built so the
## emulated DPI is already set.
##
##   --shot=<png>        save the viewport to <png> after --shot-time seconds, then quit
##   --shot-time=<s>     default 1.5 (real seconds since the scene started)
##   --dpi=<n>           emulate a screen density for UiScale (e.g. 500 for a phone)
##   --seed=<n>          battle: fixed match seed
##   --rounds=<n>        battle: rounds per match
##   --speed=<f>         battle: playback speed multiplier (fast-forward for screenshots)
##   --aim=<a>,<p>       battle: initial aim (tenths of degrees, power) of the first tank
##   --auto-fire         battle: fire once, shortly after start, with the current aim
##   --auto-play         battle: every turn, aim with a ballistic search and fire
##   --open-pause        battle: open the pause menu shortly after start
##   --auto-next         battle: with --auto-play, also press NEXT ROUND automatically

static var shot_path: String = ""
static var shot_time: float = 1.5
static var seed_value: int = 0
static var rounds: int = 0
static var speed: float = 0.0
static var aim_angle: int = -1
static var aim_power: int = -1
static var auto_fire: bool = false
static var auto_play: bool = false
static var auto_next: bool = false
static var open_pause: bool = false

static var _parsed: bool = false


static func parse() -> void:
	if _parsed:
		return
	_parsed = true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
		elif a.begins_with("--shot-time="):
			shot_time = a.substr(12).to_float()
		elif a.begins_with("--dpi="):
			UiScale.dpi_override = a.substr(6).to_float()
		elif a.begins_with("--seed="):
			seed_value = a.substr(7).to_int()
		elif a.begins_with("--rounds="):
			rounds = a.substr(9).to_int()
		elif a.begins_with("--speed="):
			speed = a.substr(8).to_float()
		elif a.begins_with("--aim="):
			var parts: PackedStringArray = a.substr(6).split(",")
			if parts.size() == 2:
				aim_angle = parts[0].to_int()
				aim_power = parts[1].to_int()
		elif a == "--auto-fire":
			auto_fire = true
		elif a == "--auto-play":
			auto_play = true
		elif a == "--open-pause":
			open_pause = true
		elif a == "--auto-next":
			auto_next = true
