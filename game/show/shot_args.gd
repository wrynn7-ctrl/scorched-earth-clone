class_name ShotArgs
extends RefCounted
## Debug/screenshot command-line options (user args after `--`), shared by the title and battle
## scenes. Parsed once; `parse()` is idempotent and must run before any HUD is built so the
## emulated DPI is already set.
##
##   --shot=<png>        save the viewport to <png> after --shot-time seconds, then quit
##   --shot-time=<s>     default 1.5 (real seconds since the scene started)
##   --dpi=<n>           emulate a screen density for UiScale (e.g. 500 for a phone)
##   --no-layout-guard   only detect (and count) wrong HUD/overlay rects, never correct them
##   --open-diag         title: open settings and the hidden diagnostics screen (5 taps on the version)
##   --safe=<l>,<t>,<r>,<b>  fake safe-area insets in physical pixels (cutout / gesture bar)
##   --resize=<W>x<H>    after --resize-after seconds, resize the window to W x H (Android-like late size)
##   --resize-after=<s>  default 0.6 (real seconds since the scene started)
##   --resize-seq=<W>x<H>@<s>,...  several resizes at the given times (portrait first, then landscape, ...)
##   --open-diag         battle: also opens the diagnostics screen over the battle
##   --shot-before=<png> with --resize: also save the viewport just before the resize
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
##   --freeze-tick=<n>   battle: stop the first shot's playback at tick n and take the --shot then
##                       (instead of after --shot-time); shows one moment of a weapon
##   --freeze-shot=<n>   with --freeze-tick: which shot (1 = the first fire action), default 1
##   --freeze-hold=<s>   with --freeze-tick: real seconds to wait after the freeze (effects
##                       keep animating in real time), default 0.25
##   --place=<i>:<x>     battle: move tank i to column x (0-based tank, simulation x) right after
##                       the round starts; the tank rests on the ground there (screenshots)

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
static var open_diag: bool = false
static var freeze_tick: int = -1
static var freeze_hold: float = 0.25
static var freeze_shot: int = 1
static var places: Array[String] = []
static var resize_to: Vector2i = Vector2i.ZERO
static var resize_after: float = 0.6
## --resize-seq=WxH@seconds,WxH@seconds,...: several window resizes (Android reports the size in steps).
static var resize_seq: Array[Dictionary] = []
static var shot_before_path: String = ""

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
		elif a == "--no-layout-guard":
			LayoutGuard.detect_only = true
		elif a == "--open-diag":
			open_diag = true
		elif a.begins_with("--safe="):
			var q: PackedStringArray = a.substr(7).split(",")
			if q.size() == 4:
				UiScale.safe_px_override = Vector4(q[0].to_float(), q[1].to_float(), q[2].to_float(), q[3].to_float())
		elif a.begins_with("--resize="):
			var wh: PackedStringArray = a.substr(9).to_lower().split("x")
			if wh.size() == 2:
				resize_to = Vector2i(wh[0].to_int(), wh[1].to_int())
		elif a.begins_with("--resize-seq="):
			for step: String in a.substr(13).split(","):
				var at: PackedStringArray = step.split("@")
				var wh2: PackedStringArray = at[0].to_lower().split("x")
				if at.size() == 2 and wh2.size() == 2:
					resize_seq.append({"size": Vector2i(wh2[0].to_int(), wh2[1].to_int()), "at": at[1].to_float()})
		elif a.begins_with("--resize-after="):
			resize_after = a.substr(15).to_float()
		elif a.begins_with("--shot-before="):
			shot_before_path = a.substr(14)
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
		elif a.begins_with("--freeze-tick="):
			freeze_tick = a.substr(14).to_int()
		elif a.begins_with("--freeze-shot="):
			freeze_shot = a.substr(14).to_int()
		elif a.begins_with("--freeze-hold="):
			freeze_hold = a.substr(14).to_float()
		elif a.begins_with("--place="):
			places.append(a.substr(8))
