class_name SetupPrefs
extends RefCounted
## The match setup the player used last time (player count, who controls each slot, rounds,
## money, wind), so replaying is one tap. Presentation-side only: it just seeds the setup
## screen's controls. SettingsStore saves it in `user://settings.cfg` and validates it on load.

const SLOTS: int = SimConstants.MAX_TANKS

## False until something was saved or loaded; the setup screen then uses its own defaults.
static var has_saved: bool = false
static var players: int = 2
static var rounds: int = 3
## Index into SetupScreen.MONEY_CHOICES / WIND_CHOICES.
static var money_level: int = 1
static var wind_level: int = 2
## SimConstants.CTRL_* per slot (always SLOTS long).
static var controllers: PackedInt32Array = _human_slots()
## "Watch CPUs play": allows a match with no human at all.
static var watch: bool = false
## Terrain theme (a ThemeDefs id or "random"). Visual only.
static var theme: String = ThemeDefs.DEFAULT_ID
## The name typed for each slot ("" = none, PLAYER n is used). Kept for CPU slots too, so switching
## a slot back to Human brings its name back. Always SLOTS long, every entry already sanitized.
static var names: PackedStringArray = _empty_names()
## The Love Edition's player 2 (SimConstants.CTRL_*), remembered separately from the standard setup.
static var love_cpu: int = 0


static func _human_slots() -> PackedInt32Array:
	var c := PackedInt32Array()
	c.resize(SLOTS)
	c.fill(SimConstants.CTRL_HUMAN)
	return c


static func _empty_names() -> PackedStringArray:
	var n := PackedStringArray()
	n.resize(SLOTS)
	return n


static func reset() -> void:
	has_saved = false
	players = 2
	rounds = 3
	money_level = 1
	wind_level = 2
	controllers = _human_slots()
	watch = false
	theme = ThemeDefs.DEFAULT_ID
	names = _empty_names()
	love_cpu = 0


## Stores the setup screen's choices (called on START).
static func remember(p_players: int, p_rounds: int, p_money_level: int, p_wind_level: int,
		p_controllers: PackedInt32Array, p_watch: bool, p_theme: String = "",
		p_names: PackedStringArray = PackedStringArray()) -> void:
	has_saved = true
	players = p_players
	rounds = p_rounds
	money_level = p_money_level
	wind_level = p_wind_level
	controllers = p_controllers.duplicate()
	controllers.resize(SLOTS)
	watch = p_watch
	if p_theme != "":
		theme = ThemeDefs.sanitize(p_theme)
	set_names_from(Array(p_names))


## Controllers as a plain Array (ConfigFile-friendly).
static func controllers_array() -> Array:
	var out: Array = []
	for c: int in controllers:
		out.append(c)
	return out


## Sets the controllers from a loaded value; anything malformed falls back to all human.
static func set_controllers_from(v: Variant) -> void:
	var c: PackedInt32Array = _human_slots()
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		for i: int in range(mini(arr.size(), SLOTS)):
			var x: Variant = arr[i]
			if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT:
				c[i] = clampi(int(x), SimConstants.CTRL_HUMAN, SimConstants.CTRL_MAX)
	controllers = c


## Names as a plain Array (ConfigFile-friendly).
static func names_array() -> Array:
	var out: Array = []
	for n: String in names:
		out.append(n)
	return out


## Sets the names from a loaded value. Every entry goes through PlayerNames.sanitize (cleaned,
## capitals, blocklist), so a hand-edited file cannot smuggle in anything; malformed means no names.
static func set_names_from(v: Variant) -> void:
	var n: PackedStringArray = _empty_names()
	if typeof(v) == TYPE_ARRAY:
		var arr: Array = v
		for i: int in range(mini(arr.size(), SLOTS)):
			if typeof(arr[i]) == TYPE_STRING:
				n[i] = PlayerNames.sanitize(arr[i] as String)
	names = n
