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
##   --auto-next         battle: with --auto-play, also press NEXT automatically on the round summary
##   --players=<n>       battle: number of tanks (2..8) for a quick match
##   --money=<n>         battle: starting credits
##   --give=<id>:<n>     battle: put n units of a catalog entry in every tank's inventory (repeatable)
##   --skip-shop         battle: every player presses READY at once (no shop screens)
##   --shop-player=<n>   battle: open the shop of player n (1-based) directly, skipping the hand-over
##   --use-item=<id>     battle: the first tank uses this item right after the round starts
##   --open-picker       battle: open the weapon picker shortly after the round starts
##   --select=<id>       battle: the first tank starts with this weapon selected
##   --shop-tab=<n>      battle: shop tab to show (0 weapons, 1 items)
##   --shop-select=<id>  battle: shop entry to select (opens the detail popup on phones)
##   --open-settings     title/battle: open the settings screen shortly after start

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
static var players: int = 0
static var money: int = -1
static var gives: Array[String] = []
static var skip_shop: bool = false
static var shop_player: int = 0
static var use_item: String = ""
static var open_picker: bool = false
static var select_weapon: String = ""
static var shop_tab: int = 0
static var shop_select: String = ""
static var open_settings: bool = false

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
		elif a.begins_with("--players="):
			players = a.substr(10).to_int()
		elif a.begins_with("--money="):
			money = a.substr(8).to_int()
		elif a.begins_with("--give="):
			gives.append(a.substr(7))
		elif a == "--skip-shop":
			skip_shop = true
		elif a.begins_with("--shop-player="):
			shop_player = a.substr(14).to_int()
		elif a.begins_with("--use-item="):
			use_item = a.substr(11)
		elif a == "--open-picker":
			open_picker = true
		elif a.begins_with("--select="):
			select_weapon = a.substr(9)
		elif a.begins_with("--shop-tab="):
			shop_tab = a.substr(11).to_int()
		elif a.begins_with("--shop-select="):
			shop_select = a.substr(14)
		elif a == "--open-settings":
			open_settings = true
