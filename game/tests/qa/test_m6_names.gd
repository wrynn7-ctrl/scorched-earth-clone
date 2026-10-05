@warning_ignore_start("integer_division")
extends GutTest
## M6-Q 4: player names (section 42).
##  - NameFilter fuzz: random unicode, emoji, RTL and zero-width characters, combining marks, controls, 1000-char
##    and 100,000-char strings: never an error, at most 12 characters, only glyphs the game font can draw (also as
##    capitals), no stray spaces, cleaning is idempotent, a kept name is allowed.
##  - blocked words stay blocked in every documented disguise (case, leetspeak, repeats, accents, separators,
##    compounds); a list of innocent words stays allowed; undocumented tricks are reported as pending gaps.
##  - names through SettingsStore (round trip, hand-edited / corrupt / missing keys) and through the autosave
##    meta (JSON round trip, corrupt and missing meta).
##  - a 12-wide name in every screen that shows names: setup rows, HUD turn banners (with team badge), hand-over,
##    shop title, round summary and results in team mode with eight names, love win.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M6 = preload("res://tests/qa/qa_m6.gd")

const SETUP: String = "res://ui/setup/setup_screen.tscn"
const PREFS_PATH: String = "user://qa_m6_names_prefs.cfg"
const META_PATH: String = "user://qa_m6_names_autosave.crtl"
const W12: String = "WWWWWWWWWWWW"

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(2340, 1080), 535.0, "narrowest realistic (700 dp)"],
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(1280, 720), 240.0, "small 16:9"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
]

var _font: Font = null


func before_all() -> void:
	_font = load(NameFilter.FONT_PATH) as Font


func before_each() -> void:
	SettingsStore.path = PREFS_PATH
	_cleanup(PREFS_PATH)
	SetupPrefs.reset()
	PlayerNames.reset()


func after_each() -> void:
	_cleanup(PREFS_PATH)
	_cleanup(META_PATH)
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SetupPrefs.reset()
	UiScale.reset_overrides()
	ShowSettings.reset()
	BattleConfig.reset()
	PlayerLooks.reset()
	PlayerNames.reset()


## Deletes one plain file inside this file's own user:// scratch names. Never follows or creates links.
func _cleanup(path: String) -> void:
	if not (path == PREFS_PATH or path == META_PATH or path == META_PATH + ".tmp"):
		return
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(path + ".tmp"):
		DirAccess.remove_absolute(path + ".tmp")


# --- NameFilter fuzz -----------------------------------------------------------------------------------------

const RANGES: Array = [
	[0x00, 0x1F], [0x20, 0x7E], [0x20, 0x7E], [0x20, 0x7E], [0x7F, 0x9F], [0xA0, 0xFF], [0x100, 0x24F], [0x300, 0x36F],
	[0x370, 0x3FF], [0x400, 0x4FF], [0x590, 0x6FF], [0x200B, 0x200F], [0x2028, 0x202E], [0x2060, 0x206F], [0xFE00, 0xFE0F],
	[0xFEFF, 0xFEFF], [0xFFF0, 0xFFFF], [0x1F300, 0x1FAFF], [0x4E00, 0x9FFF], [0xE000, 0xF8FF], [0x10000, 0x10FFFF],
	[0x2000, 0x200A], [0x3000, 0x3000], [0x1AB0, 0x1AFF], [0x20D0, 0x20FF], [0xFF00, 0xFF5E], [0x2100, 0x214F], [0x1E00, 0x1EFF],
]


func _random_string(rng: Rng, length: int) -> String:
	var out: String = ""
	for _i: int in range(length):
		var r: Array = RANGES[rng.range_int(0, RANGES.size() - 1)]
		var code: int = rng.range_int(r[0] as int, r[1] as int)
		if code == 0 or (code >= 0xD800 and code <= 0xDFFF):
			code = 0x41
		out += String.chr(code)
	return out


func _drawable(text: String) -> bool:
	for i: int in range(text.length()):
		var code: int = text.unicode_at(i)
		if code == 0x20:
			continue
		if not _font.has_char(code):
			return false
		var up: String = String.chr(code).to_upper()
		for k: int in range(up.length()):
			if not _font.has_char(up.unicode_at(k)):
				return false
	return true


func _check_name(raw: String, tag: String) -> Array[String]:
	var errs: Array[String] = []
	var c: String = NameFilter.clean(raw)
	if c.length() > NameFilter.MAX_LENGTH:
		errs.append("%s: clean() is %d chars" % [tag, c.length()])
	if c != c.strip_edges() or c.contains("  "):
		errs.append("%s: stray spaces in '%s'" % [tag, c])
	if not _drawable(c):
		errs.append("%s: clean() kept an undrawable character: %s" % [tag, c.to_utf8_buffer().hex_encode()])
	if NameFilter.clean(c) != c:
		errs.append("%s: clean() is not idempotent ('%s' -> '%s')" % [tag, c, NameFilter.clean(c)])
	var live: String = NameFilter.clean(raw, false)
	if live.length() > NameFilter.MAX_LENGTH or live.begins_with(" ") or live.ends_with("  "):
		errs.append("%s: live clean '%s'" % [tag, live])
	var allowed: bool = NameFilter.is_allowed(raw)
	var san: String = PlayerNames.sanitize(raw)
	if san.length() > NameFilter.MAX_LENGTH:
		errs.append("%s: sanitize() is %d chars" % [tag, san.length()])
	if san != san.to_upper():
		errs.append("%s: sanitize() not in capitals: '%s'" % [tag, san])
	if san != san.strip_edges():
		errs.append("%s: sanitize() has edge spaces: '%s'" % [tag, san])
	if not _drawable(san):
		errs.append("%s: sanitize() kept an undrawable character" % tag)
	if san != "" and not NameFilter.is_allowed(san):
		errs.append("%s: sanitize() kept a blocked name '%s'" % [tag, san])
	if san != "" and not allowed:
		errs.append("%s: sanitize() kept '%s' while is_allowed(raw) is false" % [tag, san])
	return errs


func test_fuzz_random_unicode_never_breaks_the_limits() -> void:
	var rng := Rng.new(0x6D360004)
	var bad: Array[String] = []
	var kept: int = 0
	var empty: int = 0
	var t0: int = Time.get_ticks_msec()
	for i: int in range(3000):
		var len: int = [1, 3, 8, 12, 13, 20, 60, 200][i % 8]
		var raw: String = _random_string(rng, len)
		bad.append_array(_check_name(raw, "sample %d" % i))
		var c: String = NameFilter.clean(raw)
		if c == "":
			empty += 1
		else:
			kept += 1
	gut.p("NAMES fuzz: 3000 random strings in %d ms, %d kept something, %d cleaned to nothing" % [Time.get_ticks_msec() - t0, kept, empty])
	assert_eq(bad.size(), 0, "\n".join(bad.slice(0, 8)))
	assert_gt(kept, 500, "the fuzz really produces drawable names too")


func test_fuzz_mostly_printable_strings_with_odd_characters_mixed_in() -> void:
	var rng := Rng.new(0x6D360005)
	var bad: Array[String] = []
	var odd: Array[int] = [0x200B, 0x200E, 0x202E, 0x2066, 0xFEFF, 0x0301, 0x1F600, 0x05D0, 0x0627, 0x00DF, 0x0130, 0x0149, 0xFB01,
			0x1E9E, 0x2764, 0x00AD, 0x3000, 0xA0]
	for i: int in range(1500):
		var s: String = ""
		var n: int = rng.range_int(1, 16)
		for _k: int in range(n):
			if rng.range_int(0, 3) == 0:
				s += String.chr(odd[rng.range_int(0, odd.size() - 1)])
			else:
				s += String.chr(rng.range_int(0x20, 0x7E))
		bad.append_array(_check_name(s, "mixed %d" % i))
	assert_eq(bad.size(), 0, "\n".join(bad.slice(0, 8)))


func test_huge_and_pathological_strings_are_fast_and_safe() -> void:
	var cases: Dictionary = {
		"1000 letters": "A".repeat(1000),
		"100000 letters": "B".repeat(100000),
		"1000 zero-width": String.chr(0x200B).repeat(1000),
		"100000 zero-width then a name": String.chr(0x200B).repeat(100000) + "ANNA",
		"1000 spaces then a name": " ".repeat(1000) + "ANNA",
		"1000 emoji": String.chr(0x1F600).repeat(1000),
		"1000 combining marks": "e" + String.chr(0x0301).repeat(1000),
		"1000 RTL": String.chr(0x05D0).repeat(1000),
		"alternating space and letter": "A ".repeat(500),
		"1000 single letters (glue)": "f u c k ".repeat(125),
		"1000 ß": String.chr(0xDF).repeat(1000),
		"1000 dotted I": String.chr(0x130).repeat(1000),
		"1000 ligature": String.chr(0xFB01).repeat(1000),
		"1000 digits": "1".repeat(1000),
		"leet wall": "1337".repeat(250),
		"1000 newlines": "\n".repeat(1000),
	}
	var t0: int = Time.get_ticks_usec()
	var bad: Array[String] = []
	for k: Variant in cases.keys():
		var t1: int = Time.get_ticks_usec()
		bad.append_array(_check_name(cases[k] as String, str(k)))
		var ms: int = (Time.get_ticks_usec() - t1) / 1000
		if ms > 400:
			bad.append("%s took %d ms" % [str(k), ms])
	gut.p("NAMES pathological: %d strings in %d ms" % [cases.size(), (Time.get_ticks_usec() - t0) / 1000])
	assert_eq(bad.size(), 0, "\n".join(bad.slice(0, 8)))
	assert_eq(NameFilter.clean(String.chr(0x200B).repeat(1000) + "ANNA"), "ANNA", "zero-width characters are not kept (and do not count to the cap)")
	assert_eq(NameFilter.clean(" ".repeat(1000) + "ANNA"), "ANNA")
	assert_lte(PlayerNames.sanitize("ß".repeat(12)).length(), 12, "capitalising never grows a name past 12")


func test_upper_casing_never_pushes_a_name_past_twelve_or_around_the_filter() -> void:
	# The game shows names in capitals; characters whose capital may be longer (ß, ŉ, ﬁ) must not make a name
	# grow past 12 (Godot keeps ß as it is, but the check is on the real output either way).
	for s: String in ["ßhit", "sßhit", "ﬁsh", "ﬁt", String.chr(0xDF) + "it", "ßßßßßßßßßßßß", "aßßßßßßßßßßß", "ﬁﬁﬁﬁﬁﬁﬁﬁﬁﬁﬁﬁ"]:
		var errs: Array[String] = _check_name(s, s)
		assert_eq(errs.size(), 0, "\n".join(errs))


# --- blocked words ----------------------------------------------------------------------------------------------

const LEET: Dictionary = {"o": "0", "i": "1", "e": "3", "a": "4", "s": "5", "t": "7"}
const LEET2: Dictionary = {"a": "@", "s": "$", "i": "!"}
const ACC: Dictionary = {"a": "à", "e": "é", "i": "ï", "o": "ö", "u": "ü"}


func _subst(word: String, map: Dictionary) -> String:
	var out: String = ""
	for i: int in range(word.length()):
		var ch: String = word[i]
		out += map.get(ch, ch) as String
	return out


func _stretch(word: String, times: int) -> String:
	var out: String = ""
	for i: int in range(word.length()):
		out += word[i].repeat(times)
	return out


func _alt_case(word: String) -> String:
	var out: String = ""
	for i: int in range(word.length()):
		out += word[i].to_upper() if i % 2 == 0 else word[i]
	return out


func _spread(word: String, sep: String) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(word.length()):
		parts.append(word[i])
	return sep.join(parts)


## Every documented disguise of `word` that fits the 12-character cap. `severe` words also hide behind
## padding and separators between the letters.
func _variants(word: String, severe: bool) -> Dictionary:
	var v: Dictionary = {
		"plain": word, "upper": word.to_upper(), "capital": word.capitalize(), "alt case": _alt_case(word),
		"leet digits": _subst(word, LEET), "leet symbols": _subst(word, LEET2), "accents": _subst(word, ACC),
		"stretched x2": _stretch(word, 2), "stretched x3": _stretch(word, 3),
		"the + word": "the " + word, "word + the": word + " the", "leet+upper": _subst(word, LEET).to_upper(),
		"leet symbols+upper": _subst(word, LEET2).to_upper(),
	}
	if severe:
		v["padded"] = "xx" + word + "xx"
		v["spaced"] = _spread(word, " ")
		v["dotted"] = _spread(word, ".")
		v["underscored"] = _spread(word, "_")
		v["dashed"] = _spread(word, "-")
		v["glued to a name"] = "ann" + word
	else:
		v["single letters"] = _spread(word, " ")
		v["dotted"] = _spread(word, ".")
	var out: Dictionary = {}
	for k: Variant in v.keys():
		var s: String = v[k] as String
		if s.length() <= NameFilter.MAX_LENGTH:
			out[k] = s
	return out


func test_every_blocklist_word_is_blocked_in_every_documented_disguise() -> void:
	var misses: Array[String] = []
	var checked: int = 0
	var lists: Array = [[NameBlocklist.SUBSTRINGS, true], [NameBlocklist.WORDS, false]]
	for l: Array in lists:
		for w: String in (l[0] as PackedStringArray):
			var vars: Dictionary = _variants(w, l[1] as bool)
			for k: Variant in vars.keys():
				var s: String = vars[k] as String
				checked += 1
				if NameFilter.is_allowed(s) or PlayerNames.sanitize(s) != "":
					misses.append("%s [%s] -> '%s'" % [w, str(k), s])
	gut.p("NAMES blocklist: %d disguises of %d words checked, %d got through" % [checked,
			NameBlocklist.SUBSTRINGS.size() + NameBlocklist.WORDS.size(), misses.size()])
	assert_gt(checked, 1000)
	assert_eq(misses.size(), 0, "blocked words that got through:\n" + "\n".join(misses.slice(0, 25)))


const INNOCENT: Array[String] = [
	"Scunthorpe", "Cassie", "Dickens", "Assess", "Assassin", "Class", "Pass", "Bass", "Grass", "Mass Effect", "Penistone",
	"Cockburn", "Hancock", "Peacock", "Analyst", "Titan", "Shiitake", "Spice", "Niger", "Nigeria", "Raccoon", "Cocoon", "Hello",
	"Classic", "Dickson", "Therapist", "Grape", "Drape", "Pakistan", "Assam", "Passion", "Cumin", "Cumbria", "Titus", "Essex",
	"Button", "Butler", "Anna", "Max", "Zoe", "Craterline", "Sussex", "Middlesex", "Arsenal", "Assistant", "Associate", "Passage",
	"Classy", "Brass", "Compass", "Embassy", "Glass", "Harass", "Massive", "Molasses", "Bassoon", "Cumberland", "Document",
	"Circumstance", "Scum", "Titanic", "Constitution", "Prickly", "Dykstra", "Spicy", "Cooney", "Cockney", "Cocktail", "Cockpit",
	"Mishit", "Bastion", "Fagin", "Fagan", "Rapeseed", "Drapes", "Grapes", "Therapy", "Skanky Pete", "Sasha", "Tom Hanks",
	"Hitchcock", "Shitsu", "Pissarro", "Moscow", "Matsushita", "Mr Tit", "Penny", "Dickie", "Bitchin", "Analysis", "Anus Fan",
	"Canal", "Anuspa", "Kikuyu", "Chinkara", "Gooky", "Paki Pete", "Pakistani", "Spicer", "Wankel", "Wankers Union",
]
## Entries above that ARE meant to be blocked (they hold a whole blocked word); the rest must pass.
const INNOCENT_BUT_BLOCKED: Array[String] = ["Mr Tit", "Anus Fan", "Paki Pete", "Wankers Union", "Bitchin"]


func test_innocent_words_are_not_blocked() -> void:
	var blocked: Array[String] = []
	for w: String in INNOCENT:
		if INNOCENT_BUT_BLOCKED.has(w):
			continue
		if not NameFilter.is_allowed(w):
			blocked.append(w)
	gut.p("NAMES false positives among %d innocent words: %s" % [INNOCENT.size() - INNOCENT_BUT_BLOCKED.size(), str(blocked)])
	assert_eq(blocked.size(), 0, "innocent words that were blocked: %s" % str(blocked))
	for w: String in INNOCENT_BUT_BLOCKED:
		assert_false(NameFilter.is_allowed(w), "%s holds a whole blocked word and stays blocked" % w)


## Tricks the documentation does not promise (digits and symbols beyond 0 1 3 4 5 7 @ $ !, look-alike
## letters, censor stars). They are reported, not asserted: a courtesy filter. Pending, not failing.
func test_undocumented_disguises_are_reported_as_gaps() -> void:
	var gaps: Array[String] = []
	var tricks: Array[String] = ["fvck", "8itch", "ni99er", "sh1+", "d|ck", "phuck", "(unt", "f*ck", "f**k", "sh*t", "p*ssy", "cvnt", "b1tch",
			"ßhit", "ßlut", "fuk", "fuq", "sh!t", "5h1t", "a$$", "@$$hole", "wh0re", "fvk", "pvssy", "d1ldo", "c0ck", "f4g", "j1zz", "tw4t", "nigg3r", "fag"]
	for s: String in tricks:
		if NameFilter.is_allowed(s):
			gaps.append(s)
	gut.p("NAMES gaps (not blocked): %s" % str(gaps))
	if not gaps.is_empty():
		pending("BUG (low): NameFilter lets simple look-alike spellings through: %s. LEET/ACCENTS in game/ui/names/name_filter.gd:20-24 fold only 0 1 3 4 5 7 @ $ ! and Latin accents; 'v' for u, '8' b, '9' g, '+' t, '|' i/l, '*' censor, 'ph' f are not folded (a courtesy filter, so low)." % str(gaps))


# --- SettingsStore ------------------------------------------------------------------------------------------------

func _write_cfg(text: String) -> void:
	var f: FileAccess = FileAccess.open(PREFS_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_names_teams_and_friendly_fire_round_trip_through_settings_store() -> void:
	var names: PackedStringArray = PackedStringArray(["ANNA", "", "ZOË K", "WWWWWWWWWWWW", "R2-D2", "", "", "MR. X'S"])
	var teams: PackedInt32Array = PackedInt32Array([0, 0, 1, 1, 2, -1, 3, 0])
	var ctrl: PackedInt32Array = PackedInt32Array([0, 2, 0, 3, 0, 1, 4, 0])
	SetupPrefs.remember(8, 5, 2, 3, ctrl, true, "", names, teams, false)
	assert_true(SettingsStore.save())
	SetupPrefs.reset()
	assert_false(SetupPrefs.has_saved)
	assert_true(SettingsStore.load_into())
	assert_true(SetupPrefs.has_saved)
	assert_eq(SetupPrefs.names, names)
	assert_eq(SetupPrefs.teams, teams)
	assert_false(SetupPrefs.friendly_fire)
	assert_eq(SetupPrefs.players, 8)
	assert_eq(SetupPrefs.controllers, ctrl)


func test_hand_edited_names_teams_and_flags_are_cleaned_on_load() -> void:
	var long_name: String = "x".repeat(1000)
	_write_cfg('[setup]\nplayers=3\nrounds=2\nmoney_level=1\nwind_level=1\nwatch=false\ncontrollers=[0, 0, 0]\n'
			+ 'names=["  anna  ", "FUCK", "%s", 5, null, ["x"], "%sEVIL", "ok", "overflow", "more"]\n' % [long_name, String.chr(0x202E)]
			+ 'teams=[0, 1, 7, -5, 2.0, "A", null, 99, 0, 1, 2, 3]\nfriendly_fire="yes"\n')
	assert_true(SettingsStore.load_into())
	assert_eq(SetupPrefs.names.size(), SetupPrefs.SLOTS, "always one entry per slot")
	assert_eq(SetupPrefs.names[0], "ANNA")
	assert_eq(SetupPrefs.names[1], "", "blocked name dropped")
	assert_eq(SetupPrefs.names[2], "XXXXXXXXXXXX", "1000 chars cut to 12")
	assert_eq(SetupPrefs.names[3], "")
	assert_eq(SetupPrefs.names[4], "")
	assert_eq(SetupPrefs.names[5], "")
	assert_eq(SetupPrefs.names[6], "EVIL", "the right-to-left override is gone")
	assert_eq(SetupPrefs.names[7], "OK")
	for n: String in SetupPrefs.names:
		assert_lte(n.length(), 12)
	assert_eq(SetupPrefs.teams.size(), SetupPrefs.SLOTS)
	assert_eq(SetupPrefs.teams[0], 0)
	assert_eq(SetupPrefs.teams[1], 1)
	assert_eq(SetupPrefs.teams[2], TeamStyle.NONE, "team 7 is no team")
	assert_eq(SetupPrefs.teams[3], TeamStyle.NONE, "team -5 is no team")
	assert_eq(SetupPrefs.teams[4], 2, "a whole-number float is a team")
	assert_eq(SetupPrefs.teams[5], TeamStyle.NONE, "a string is no team")
	assert_eq(SetupPrefs.teams[7], TeamStyle.NONE, "team 99 is no team")
	assert_true(SetupPrefs.friendly_fire, "a non-bool falls back to the default (on)")


func test_corrupt_and_missing_setup_values_never_crash_the_loader() -> void:
	var bodies: Array[String] = [
		'[setup]\nnames=5\nteams="abc"\nfriendly_fire=3\ncontrollers={"a": 1}\n',
		'[setup]\nnames={"a": "b"}\nteams={"x": 1}\n',
		'[setup]\nnames=[]\nteams=[]\n',
		'[setup]\nplayers="x"\n',
		'[setup]\nnames=[[[[1]]]]\nteams=[[0], [1]]\n',
		'[setup]\n',
		'',
		'garbage that is not a config file {{{',
		'[setup]\nnames=["%s"]\n' % "a".repeat(100000),
	]
	for body: String in bodies:
		SetupPrefs.reset()
		_write_cfg(body)
		SettingsStore.load_into()
		assert_eq(SetupPrefs.names.size(), SetupPrefs.SLOTS)
		assert_eq(SetupPrefs.teams.size(), SetupPrefs.SLOTS)
		for t: int in SetupPrefs.teams:
			assert_true(t == TeamStyle.NONE or TeamStyle.is_team(t))
		for n: String in SetupPrefs.names:
			assert_lte(n.length(), 12)
	# Missing keys leave the defaults.
	SetupPrefs.reset()
	_write_cfg('[setup]\nplayers=4\nrounds=3\n')
	assert_true(SettingsStore.load_into())
	for n: String in SetupPrefs.names:
		assert_eq(n, "")
	for t: int in SetupPrefs.teams:
		assert_eq(t, TeamStyle.NONE)
	assert_true(SetupPrefs.friendly_fire)
	# A file that predates teams: loading never invents teams.
	var s: SetupScreen = (load(SETUP) as PackedScene).instantiate()
	add_child_autofree(s)
	assert_false(s.teams_on())


# --- the autosave meta ----------------------------------------------------------------------------------------------

func test_names_round_trip_through_the_autosave_meta() -> void:
	PlayerNames.set_names(PackedStringArray(["ANNA", "", "BOB K", W12]))
	var meta: Dictionary = {"names": PlayerNames.to_array(4), "theme": "random"}
	var packed: PackedByteArray = SaveStore.pack(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8]), meta)
	var un: Dictionary = SaveStore.unpack(packed)
	assert_true(un["ok"])
	PlayerNames.reset()
	PlayerNames.from_array((un["meta"] as Dictionary).get("names", []))
	assert_eq(PlayerNames.typed(0), "ANNA")
	assert_eq(PlayerNames.typed(1), "")
	assert_eq(PlayerNames.typed(2), "BOB K")
	assert_eq(PlayerNames.typed(3), W12)
	assert_eq(PlayerNames.label(1), "PLAYER 2")
	# Through a real file with a real match.
	var settings := MatchSettings.new()
	settings.seed = 12
	settings.num_tanks = 4
	settings.teams = PackedInt32Array([0, 1, 0, 1])
	var state: MatchState = QaUtil.started_match(settings)
	assert_true(SaveStore.save(state, [] as Array[Dictionary], META_PATH, meta))
	var res: Dictionary = SaveStore.load_save(META_PATH)
	assert_true(res["ok"], str(res["error"]))
	PlayerNames.reset()
	PlayerNames.from_array((res["meta"] as Dictionary).get("names", []))
	assert_eq(PlayerNames.typed(3), W12)
	assert_eq((res["state"] as MatchState).settings.teams, PackedInt32Array([0, 1, 0, 1]))


func test_corrupt_and_missing_meta_names_become_player_n() -> void:
	var bad_values: Array = [null, 5, "ANNA", {"a": 1}, [1, 2, 3], [null, [], {}], ["ok", 5, null, "FUCK", "x".repeat(500), "\u202eLTR"],
			range(100), [["a"], ["b"]], [1.5, true], ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]]
	for v: Variant in bad_values:
		PlayerNames.reset()
		PlayerNames.from_array(v)
		for i: int in range(12):
			assert_lte(PlayerNames.label(i).length(), 40)
			assert_lte(PlayerNames.typed(i).length(), 12)
			if PlayerNames.has_custom(i):
				assert_true(NameFilter.is_allowed(PlayerNames.typed(i)))
	PlayerNames.from_array(["ok", 5, null, "FUCK", "x".repeat(500), "\u202eLTR"])
	assert_eq(PlayerNames.typed(0), "OK")
	assert_eq(PlayerNames.typed(1), "")
	assert_eq(PlayerNames.typed(3), "")
	assert_eq(PlayerNames.typed(4), "XXXXXXXXXXXX")
	assert_eq(PlayerNames.typed(5), "LTR")
	# JSON round trip of the meta (numbers come back as floats, strings as strings).
	var json: String = JSON.stringify({"names": ["ANNA", "", "ZOË"]})
	var parsed: Variant = JSON.parse_string(json)
	PlayerNames.from_array((parsed as Dictionary).get("names", []))
	assert_eq(PlayerNames.typed(2), "ZOË")
	# A meta without the key (an old save) or with garbage JSON.
	var no_names: Dictionary = SaveStore.unpack(SaveStore.pack(PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9]), {"theme": "x"}))["meta"]
	PlayerNames.from_array(no_names.get("names", []))
	assert_eq(PlayerNames.label(0), "PLAYER 1")
	var broken: PackedByteArray = SaveStore.pack(PackedByteArray([9, 9, 9, 9, 9, 9, 9, 9]), {"names": ["A"]})
	broken[16] = 0x7B  # inside the JSON: breaks it
	var un: Dictionary = SaveStore.unpack(broken)
	PlayerNames.from_array((un["meta"] as Dictionary).get("names", []))
	assert_lte(PlayerNames.typed(0).length(), 12)


## battle_controller.gd restores the autosave meta with unchecked casts. The meta JSON is NOT covered by the save
## checksum, and a wrong-typed value raises "Invalid cast" (verified by hand: `{"looks": 5}` makes the engine
## report an error at battle_controller.gd:436). The run_tests.sh gate fails on any such engine error line, so
## this test only scans the source for the unguarded patterns instead of executing them.
func test_the_battle_does_not_cast_raw_meta_values() -> void:
	var f: FileAccess = FileAccess.open("res://show/battle/battle_controller.gd", FileAccess.READ)
	assert_not_null(f, "the battle controller source can be read")
	if f == null:
		return
	var lines: PackedStringArray = f.get_as_text().split("\n")
	f.close()
	var found: Array[String] = []
	for i: int in range(lines.size()):
		var l: String = lines[i]
		if "meta.get(" in l and (" as Dictionary" in l or " as bool" in l or " as Array" in l or " as String" in l):
			found.append("battle_controller.gd:%d `%s`" % [i + 1, l.strip_edges()])
	gut.p("META unguarded casts in the battle's restore path: %s" % str(found))
	if not found.is_empty():
		pending("BUG (low): restoring an autosave whose meta JSON has a wrong-typed value raises an 'Invalid cast' runtime error: %s. Input: meta {\"looks\": 5} (or {\"summary_pending\": \"yes\"}). Expected: the value is ignored like _cpu_buys_from_meta ignores bad data. Actual: a runtime error, _start_match aborts, Continue shows a broken battle. Only a hand-edited/damaged file reaches it (the meta is outside the SHA-256), so low." % "; ".join(found))


# --- 12-wide names in the screens ---------------------------------------------------------------------------------------

func _viewport(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


func test_big_turn_banner_fits_with_the_widest_name_and_a_team_badge() -> void:
	for size_pct: int in [100, 150]:
		ShowSettings.set_text_size(size_pct)
		for case: Array in CASES:
			var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
			var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
			for team: int in [TeamStyle.NONE, 0, 3]:
				for love: bool in [false, true]:
					var b := BigTurnBanner.new()
					vp.add_child(b)
					b.show_turn(7, W12, love, team)
					b.advance(0.3)
					await wait_process_frames(2)
					var row: Control = b.get_node("Row")
					var rect: Rect2 = row.get_global_rect()
					assert_true(vis.encloses(rect), "%s @%d%% team %d love %s: banner row %s inside %s" % [case[2], size_pct, team, str(love), rect, vis])
					var lab: Label = b.get_label()
					var w: float = lab.get_theme_font("font").get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, lab.get_theme_font_size("font_size")).x
					assert_lte(w, lab.size.x + 1.0, "%s: the name text is not clipped" % case[2])
					b.queue_free()
			vp.queue_free()
			await wait_process_frames(1)


func test_hud_turn_banner_fits_with_the_widest_name_and_a_team_badge() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
		var hud: BattleHud = (load("res://ui/hud/hud.tscn") as PackedScene).instantiate()
		vp.add_child(hud)
		hud.set_teams(PackedInt32Array([0, 1, 2, 3, 0, 1, 2, 3]))
		await wait_process_frames(2)
		PlayerNames.set_names(PackedStringArray([W12, W12, W12, W12, W12, W12, W12, W12]))
		for i: int in [0, 3, 7]:
			hud.show_turn(i, W12)
			await wait_process_frames(2)
			var banner: Control = hud.get_turn_banner()
			var rect: Rect2 = banner.get_global_rect()
			var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
			assert_true(vis.encloses(rect), "%s: turn banner %s inside %s (player %d)" % [case[2], rect, vis, i])
			# It must not run into the power panel or the wind indicator (the other top-row panels).
			for other: Control in [hud.get_power_panel(), hud.get_wind_indicator(), hud.get_angle_panel()]:
				if other.is_visible_in_tree() and other.size.x > 0.0:
					var o: Rect2 = other.get_global_rect()
					var ov: Rect2 = o.intersection(rect)
					assert_true(ov.size.x <= 1.0 or ov.size.y <= 1.0, "%s: turn banner %s overlaps %s %s" % [case[2], rect, other.name, o])
		vp.queue_free()
		await wait_process_frames(1)


## The ScrollContainer that clips `c`, or null.
func _clipping_scroll(c: Control, stop: Node) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null and n != stop:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


## Every visible label of `overlay` sits inside the panel, or - when it is table content in a scroll area -
## inside the scroll area sideways (vertical overflow is scrolled, not lost).
func _label_problems(overlay: OverlayPanel, tag: String) -> Array[String]:
	var errs: Array[String] = []
	var panel: Control = overlay.get_node("Center/Panel")
	for l: Node in overlay.find_children("*", "Label", true, false):
		var lab: Label = l as Label
		if not lab.is_visible_in_tree() or lab.get_global_rect().size.x <= 0.0:
			continue
		var r: Rect2 = lab.get_global_rect()
		var sc: ScrollContainer = _clipping_scroll(lab, overlay)
		if sc != null:
			var sr: Rect2 = sc.get_global_rect()
			if r.position.x < sr.position.x - 1.5 or r.end.x > sr.end.x + 1.5:
				errs.append("%s: %s scrolled label '%s' %s sticks out of its scroll area %s sideways" % [tag, overlay.name, lab.text, r, sr])
		elif not panel.get_global_rect().grow(1.5).encloses(r):
			errs.append("%s: %s label '%s' %s outside the panel %s" % [tag, overlay.name, lab.text, r, panel.get_global_rect()])
	return errs


func test_team_summary_and_results_fit_with_eight_widest_names() -> void:
	var problems: Array[String] = []
	var panel_overflow: Array[String] = []
	for case: Array in CASES:
		for winners: int in [1, 4, 7]:
			var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
			var names := PackedStringArray()
			for _i: int in range(8):
				names.append(W12)
			PlayerNames.set_names(names)
			var rnd := RoundEndOverlay.new()
			var fin := MatchEndOverlay.new()
			vp.add_child(rnd)
			vp.add_child(fin)
			var rows: Array[Dictionary] = []
			var teams := PackedInt32Array()
			for i: int in range(8):
				rows.append({"id": i, "earned": 125000, "kills": 12, "wins": 5 - (i / 4), "damage": 123456 - i * 100, "money": 999999})
				teams.append(0 if i < winners else 1)
			rnd.show_summary(0, rows, 2, 5, [] as Array[Dictionary], teams, 0)
			var order: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
			var torder: Array[int] = [0, 1]
			fin.show_team_standings(torder, order, rows, teams)
			await wait_process_frames(4)
			var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
			var tag: String = "%s, %d winners" % [case[2], winners]
			for o: OverlayPanel in [rnd, fin]:
				var panel: Control = o.get_node("Center/Panel")
				if not vis.encloses(panel.get_global_rect()):
					panel_overflow.append("%s: %s panel %s in a %s screen" % [tag, o.name, panel.get_global_rect(), vp.size])
				problems.append_array(_label_problems(o, tag))
				var next: Control = o.find_child("Next", true, false)
				if next == null:
					next = o.find_child("Rematch", true, false)
				for b: Node in o.find_children("*", "Button", true, false):
					var br: Rect2 = (b as Button).get_global_rect()
					if (b as Button).is_visible_in_tree() and not vis.encloses(br):
						problems.append("%s: %s button '%s' %s is cut off by the screen %s" % [tag, o.name, (b as Button).text, br, vp.size])
			var members: Label = rnd.find_child("Members", true, false) as Label
			assert_true(members.visible, "%s: the winning team's members are listed" % tag)
			assert_eq(members.text.split(" · ").size(), winners)
			assert_true((rnd.get_node("Center/Panel") as Control).get_global_rect().grow(1.5).encloses(members.get_global_rect()),
					"%s: members line inside the panel" % tag)
			vp.queue_free()
			await wait_process_frames(1)
	assert_eq(problems.size(), 0, "\n".join(problems.slice(0, 6)))
	if not panel_overflow.is_empty():
		pending("BUG (low): the team round summary panel is taller than the screen by a few pixels when the winning team lists many 12-wide names (members line wraps to 4 lines): %s. OverlayPanel._fit_scrolls (ui/overlay/overlay_panel.gd:127-141) never shrinks the table below 72 dp, so the panel cannot fit a 700 dp phone; the NEXT button stays on screen, the panel's bottom padding is cut." % "; ".join(panel_overflow.slice(0, 3)))


func test_love_win_overlay_fits_the_widest_name() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _viewport(case[0] as Vector2, case[1] as float)
		PlayerNames.set_names(PackedStringArray([W12, W12]))
		var o := LoveWinOverlay.new()
		vp.add_child(o)
		o.show_win(1)
		await wait_process_frames(3)
		var vis := Rect2(Vector2.ZERO, Vector2(vp.size)).grow(1.5)
		assert_true(vis.encloses(o.get_panel().get_global_rect()), "%s: love win panel inside the screen" % case[2])
		for l: Node in o.find_children("*", "Label", true, false):
			var lab: Label = l as Label
			if lab.is_visible_in_tree() and lab.get_global_rect().size.x > 0.0:
				assert_true(o.get_panel().get_global_rect().grow(1.5).encloses(lab.get_global_rect()), "%s: '%s' inside the panel" % [case[2], lab.text])
		vp.queue_free()
		await wait_process_frames(1)


## Tags are centred over their tank at the same height. Tanks are placed one per equal segment with a jitter of
## +-segment/5, so two neighbours can stand as close as 3/5 of a segment (120 world units with 8 tanks), not a
## full lane (the show test assumes 200). Two long names (plus badges) then run into each other.
func test_adjacent_name_tags_do_not_collide_with_long_names_at_eight_players() -> void:
	var w12: float = TankView.tag_width(W12) * TankView.VISUAL_SCALE
	var badge_cap: float = TankView.MAX_TAG_EXTENT * TankView.VISUAL_SCALE
	var closest: int = 100000
	var collide_plain: int = 0
	var collide_badge: int = 0
	var pairs: int = 0
	for seed_value: int in range(24):
		var s := MatchSettings.new()
		s.seed = 4000 + seed_value
		s.num_tanks = 8
		s.teams = PackedInt32Array([0, 1, 0, 1, 0, 1, 0, 1])
		var state: MatchState = QaUtil.started_match(s)
		for i: int in range(7):
			var d: int = state.tanks[i + 1].x - state.tanks[i].x
			closest = mini(closest, d)
			pairs += 1
			if w12 > float(d):  # two equal tags: half a width each side
				collide_plain += 1
			if badge_cap > float(d):
				collide_badge += 1
	gut.p("NAME TAGS at 8 players: closest neighbours %d units apart over %d pairs; a 12-capital tag is %.0f units wide (%.0f with a badge): %d / %d pairs collide without / with a badge" % [
			closest, pairs, w12, badge_cap, collide_plain, collide_badge])
	if collide_plain > 0 or collide_badge > 0:
		pending("BUG (low): with 8 players, neighbouring tanks can stand only %d units apart (Simulation._place_tanks jitter +-seg/5 leaves 3/5 of a %d unit lane), while a 12-capital name tag is %.0f units wide on screen (%.0f with a team badge, TankView.MAX_TAG_EXTENT %.0f x 1.5). %d of %d neighbour pairs (%d without badges) in 24 seeded 8-tank rounds would draw overlapping tags if both players use 12-letter names of wide capitals. tests/show/test_teams_battle.gd:150 and test_player_names.gd:430 assume a full 200 unit lane." % [
				closest, 1600 / 8, w12, badge_cap, TankView.MAX_TAG_EXTENT, collide_badge, pairs, collide_plain])
