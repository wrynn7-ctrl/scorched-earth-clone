extends GutTest
## NameFilter: cleaning (length, spaces, control characters, glyphs the font lacks) and the
## blocklist, with its false-positive guards.


func test_clean_trims_and_collapses_spaces() -> void:
	assert_eq(NameFilter.clean("   Anna   Lee  "), "Anna Lee")
	assert_eq(NameFilter.clean("a\t\nb"), "a b", "tabs and newlines act as one space")
	assert_eq(NameFilter.clean("a" + String.chr(0xA0) + String.chr(0x2003) + "b"), "a b", "unicode spaces too")
	assert_eq(NameFilter.clean(""), "")
	assert_eq(NameFilter.clean("   "), "")


func test_clean_caps_at_twelve_characters() -> void:
	assert_eq(NameFilter.clean("ABCDEFGHIJKLMNOP"), "ABCDEFGHIJKL")
	assert_eq(NameFilter.clean("ABCDEFGHIJK MNOP"), "ABCDEFGHIJK", "no trailing space after the cut")
	assert_eq(NameFilter.clean("ABCDEFGHIJKL").length(), NameFilter.MAX_LENGTH)


func test_clean_live_keeps_one_trailing_space() -> void:
	assert_eq(NameFilter.clean("ANNA ", false), "ANNA ")
	assert_eq(NameFilter.clean("ANNA   ", false), "ANNA ")
	assert_eq(NameFilter.clean(" ANNA", false), "ANNA", "never a leading space")


func test_clean_strips_control_and_invisible_characters() -> void:
	assert_eq(NameFilter.clean("A" + String.chr(0) + "B" + String.chr(7) + "C" + String.chr(0x7F) + "D"), "ABCD")
	assert_eq(NameFilter.clean("A" + String.chr(0x200B) + "B" + String.chr(0x200D) + "C" + String.chr(0x202E) + "D" + String.chr(0xFEFF) + "E" + String.chr(0xAD) + "F"), "ABCDEF", "zero width, direction marks, BOM, soft hyphen")


func test_clean_strips_glyphs_the_font_cannot_draw() -> void:
	assert_eq(NameFilter.clean("Ann" + String.chr(0x1F600) + "a"), "Anna", "emoji")
	assert_eq(NameFilter.clean("Ann" + String.chr(0x2764) + "a"), "Anna", "a dingbat heart")
	assert_eq(NameFilter.clean(String.chr(0x4F60) + String.chr(0x597D) + "Bob"), "Bob", "CJK is not in the Latin font")
	assert_eq(NameFilter.clean(String.chr(0x416) + "enya"), "enya", "Cyrillic is not in the font either")
	assert_eq(NameFilter.clean(String.chr(0x301) + "Ann"), "Ann", "a lone combining mark")


func test_clean_keeps_everything_the_font_can_draw() -> void:
	assert_eq(NameFilter.clean("Zo" + String.chr(0xEB) + " J" + String.chr(0xFC) + "rgen"), "Zo" + String.chr(0xEB) + " J" + String.chr(0xFC) + "rgen")
	assert_eq(NameFilter.clean("R2-D2 #1"), "R2-D2 #1")
	assert_eq(NameFilter.clean("Mr. X's"), "Mr. X's")


func test_every_kept_character_has_a_glyph_in_the_game_font() -> void:
	var font: Font = load(NameFilter.FONT_PATH) as Font
	assert_not_null(font)
	var sample: String = ""
	for code: int in range(0x20, 0x500):
		sample += String.chr(code)
	for code: int in [0x2014, 0x2019, 0x20AC, 0x2122, 0x2022, 0x1F600, 0x2764, 0x0416]:
		sample += String.chr(code)
	# Twelve at a time, so the length cap does not hide anything.
	var i: int = 0
	var checked: int = 0
	while i < sample.length():
		var kept: String = NameFilter.clean(sample.substr(i, 12))
		for k: int in range(kept.length()):
			var code: int = kept.unicode_at(k)
			if code != 0x20:
				assert_true(font.has_char(code), "U+%04X has a glyph" % code)
				assert_true(font.has_char(kept.substr(k, 1).to_upper().unicode_at(0)), "U+%04X has a capital glyph" % code)
				checked += 1
		i += 12
	assert_gt(checked, 150, "most of Latin-1 is kept")


# --- blocklist ---

func test_plain_words_are_blocked() -> void:
	for w: String in ["fuck", "Shit", "BITCH", "cunt", "dick", "Nigger", "faggot", "pussy", "whore", "slut"]:
		assert_false(NameFilter.is_allowed(w), "%s is blocked" % w)


func test_case_leetspeak_and_repeats_are_folded() -> void:
	for w: String in ["FuCk", "sh1t", "5hit", "$h!t", "d1ck", "dIcK", "c0ck", "a55", "@ss", "@$$", "fuuuuck", "shiiit", "bitccch",
			"n1gger", "b1tch", "cvnt".replace("v", "u"), "p0rn", "7it5", "fvck".replace("v", "u")]:
		assert_false(NameFilter.is_allowed(w), "%s is blocked" % w)


func test_separators_cannot_hide_a_word() -> void:
	for w: String in ["f u c k", "f.u.c.k", "xx_fuck_xx", "d i c k", "BIG DICK", "the shit", "f_u_c_k"]:
		assert_false(NameFilter.is_allowed(w), "%s is blocked" % w)


func test_compounds_are_blocked() -> void:
	for w: String in ["dumbass", "Fatass", "dicks", "asses", "dickhead", "shithead", "bullshit", "jackass", "assdick", "motherfucker"]:
		assert_false(NameFilter.is_allowed(w), "%s is blocked" % w)


func test_accents_are_folded() -> void:
	assert_false(NameFilter.is_allowed("f" + String.chr(0xFC) + "ck"))
	assert_false(NameFilter.is_allowed("sh" + String.chr(0xEF) + "it"))


func test_innocent_names_with_blocked_letters_inside_pass() -> void:
	for w: String in ["Scunthorpe", "Cassie", "Dickens", "Assess", "Assassin", "Class", "Pass", "Bass", "Grass", "Mass Effect",
			"Penistone", "Cockburn", "Hancock", "Peacock", "Analyst", "Titan", "Shiitake", "Spice", "Niger", "Nigeria",
			"Raccoon", "Cocoon", "Hello", "Classic", "Dickson", "Therapist", "Grape", "Drape", "Pakistan", "Assam",
			"As", "Passion", "Cumin", "Cumbria", "Titus", "Essex", "Button", "Butler", "Anna", "Max", "Zoe", "Craterline"]:
		assert_true(NameFilter.is_allowed(w), "%s is fine" % w)


func test_empty_is_allowed() -> void:
	assert_true(NameFilter.is_allowed(""))
	assert_true(NameFilter.is_allowed("   "))


func test_only_the_first_twelve_characters_count() -> void:
	# A blocked word past the cap is cut off by clean(), which is_allowed applies first.
	assert_true(NameFilter.is_allowed("ABCDEFGHIJKLfuck"))
	assert_false(NameFilter.is_allowed("ABCDEFGfuck"))


func test_blocklist_data_is_well_formed() -> void:
	for list: PackedStringArray in [NameBlocklist.SUBSTRINGS, NameBlocklist.WORDS, NameBlocklist.PREFIXES, NameBlocklist.SUFFIXES]:
		for w: String in list:
			assert_eq(w, w.to_lower(), "%s is lowercase" % w)
			for i: int in range(w.length()):
				assert_true(w.unicode_at(i) >= 0x61 and w.unicode_at(i) <= 0x7A, "%s is letters only" % w)
