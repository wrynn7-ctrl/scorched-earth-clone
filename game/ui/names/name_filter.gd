class_name NameFilter
extends RefCounted
## Cleans and checks player names (ARCHITECTURE section 42). Static, no state to set up; M7 (online
## names) reuses it. The whole API is two calls:
##
##   NameFilter.clean(raw)       -> the text to keep: trimmed, single spaces, only characters the game
##                                  font can draw, at most MAX_LENGTH characters. "" if nothing is left.
##   NameFilter.is_allowed(name) -> false when the name contains a word from NameBlocklist.
##
## A caller that wants a usable name does `var n := NameFilter.clean(raw)` and, when `n` is empty or
## `not NameFilter.is_allowed(n)`, falls back to its own default ("PLAYER 2").
##
## Matching folds case, accents and simple leetspeak (0 o, 1 i or l, 3 e, 4 a, 5 s, 7 t, @ a, $ s, ! i)
## and ignores repeated letters. Words are matched as whole space-separated words (see
## NameBlocklist.WORDS), so "Scunthorpe", "Cassie" and "Dickens" pass. A few severe words
## (NameBlocklist.SUBSTRINGS) are blocked anywhere, also with separators between the letters.
## This is a courtesy filter, not a moderation system: a determined player can get around it.

const MAX_LENGTH: int = 12
## The font every name is drawn with (see assets/fonts). A glyph it lacks would show as a box.
const FONT_PATH: String = "res://assets/fonts/orbitron-latin-700-normal.woff2"
## Letters standing in for symbols and digits. "1" is tried as both i and l (see _folds).
const LEET: Dictionary = {"0": "o", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i"}
const ACCENTS: Dictionary = {
	"a": "àáâãäå", "c": "ç", "e": "èéêë", "i": "ìíîï", "n": "ñ", "o": "òóôõöø", "u": "ùúûü", "y": "ýÿ",
}

static var _font: Font = null
static var _glyphs: Dictionary = {}
static var _compiled: Dictionary = {}
static var _accent_map: Dictionary = {}


## The name as it will be kept. `final = false` keeps one trailing space, for a field that is
## still being typed in (otherwise "ANNA K" could never get its space).
static func clean(raw: String, final: bool = true) -> String:
	var out: String = ""
	for i: int in range(raw.length()):
		var code: int = raw.unicode_at(i)
		if _is_space(code):
			if out != "" and not out.ends_with(" "):
				out += " "
		elif _drawable(code):
			out += String.chr(code)
		if out.length() >= MAX_LENGTH:
			break
	out = out.substr(0, MAX_LENGTH)
	return out.strip_edges() if final else out.strip_edges(true, false)


## False when `player_name` contains a blocked word. An empty name is allowed (nothing to object to).
static func is_allowed(player_name: String) -> bool:
	for folded: String in _folds(clean(player_name)):
		if _blocked(folded):
			return false
	return true


# ======================================================================================
# Cleaning
# ======================================================================================

static func _is_space(code: int) -> bool:
	return code == 0x20 or code == 0x09 or code == 0x0A or code == 0x0D or code == 0xA0 \
			or (code >= 0x2000 and code <= 0x200A) or code == 0x202F or code == 0x205F or code == 0x3000


## A character the name may contain: printable, in the font (also as a capital, because the game
## shows names in capitals), and not an invisible or direction-changing format character.
static func _drawable(code: int) -> bool:
	if _glyphs.has(code):
		return _glyphs[code] as bool
	var ok: bool = _drawable_uncached(code)
	_glyphs[code] = ok
	return ok


static func _drawable_uncached(code: int) -> bool:
	if code < 0x20 or (code >= 0x7F and code <= 0x9F) or code == 0xAD:
		return false
	# Combining marks would pile onto the neighbouring letter (or onto the field's own border).
	if (code >= 0x0300 and code <= 0x036F) or (code >= 0x1AB0 and code <= 0x1AFF) or (code >= 0x20D0 and code <= 0x20FF):
		return false
	if (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202E) \
			or (code >= 0x2060 and code <= 0x206F) or code == 0xFEFF or code >= 0xFFF0 \
			or (code >= 0xD800 and code <= 0xDFFF) or code > 0xFFFF:
		return false
	var font: Font = _get_font()
	if font == null:
		return code < 0x7F
	if not font.has_char(code):
		return false
	var upper: String = String.chr(code).to_upper()
	for i: int in range(upper.length()):
		if not font.has_char(upper.unicode_at(i)):
			return false
	return true


static func _get_font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


# ======================================================================================
# Matching
# ======================================================================================

## The name as plain lowercase letters with single spaces between words; every symbol that is not a
## letter, digit or leetspeak stand-in becomes a space. A "1" gives two readings (i and l).
static func _folds(text: String) -> Array[String]:
	var variants: Array[String] = [_fold(text, "i")]
	if text.contains("1"):
		variants.append(_fold(text, "l"))
	return variants


static func _fold(text: String, one_as: String) -> String:
	if _accent_map.is_empty():
		for letter: String in ACCENTS:
			var chars: String = ACCENTS[letter]
			for i: int in range(chars.length()):
				_accent_map[chars[i]] = letter
	var out: String = ""
	for raw_ch: String in text.to_lower():
		var ch: String = raw_ch
		if _accent_map.has(raw_ch):
			ch = _accent_map[raw_ch] as String
		elif raw_ch == "1":
			ch = one_as
		elif LEET.has(raw_ch):
			ch = LEET[raw_ch] as String
		var c: int = ch.unicode_at(0)
		out += ch if (c >= 0x61 and c <= 0x7A) else " "
	return out


static func _blocked(folded: String) -> bool:
	var tokens: PackedStringArray = _tokens(folded)
	if _contains_severe("".join(tokens)):
		return true
	for token: String in tokens:
		if _is_blocked_word(token):
			return true
	return false


## Words of the folded text; runs of single letters are glued together ("d i c k" is one word).
static func _tokens(folded: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var singles: String = ""
	for part: String in folded.split(" ", false):
		if part.length() == 1:
			singles += part
			continue
		if singles != "":
			out.append(singles)
			singles = ""
		out.append(part)
	if singles != "":
		out.append(singles)
	return out


static func _contains_severe(joined: String) -> bool:
	for word: String in NameBlocklist.SUBSTRINGS:
		for start: int in range(joined.length()):
			if not _ends(joined, start, word).is_empty():
				return true
	return false


## `token` is [prefix] + blocked word (+ blocked word) + [suffix], nothing else.
static func _is_blocked_word(token: String) -> bool:
	var starts: Array[int] = [0]
	for prefix: String in NameBlocklist.PREFIXES:
		starts.append_array(_ends(token, 0, prefix, true))
	var reached: Array[int] = []
	for s: int in starts:
		for word: String in NameBlocklist.WORDS:
			reached.append_array(_ends(token, s, word))
	# Optionally a second blocked word ("assdick").
	var glued: Array[int] = reached.duplicate()
	for pos: int in reached:
		for word: String in NameBlocklist.WORDS:
			glued.append_array(_ends(token, pos, word))
	for pos: int in glued:
		if pos == token.length():
			return true
		for suffix: String in NameBlocklist.SUFFIXES:
			if _ends(token, pos, suffix, true).has(token.length()):
				return true
	return false


## Every index where `word` can end when matched against `text` from `start`; each letter of the
## word may be repeated ("fuuck"), never shortened. Empty when it does not match there. `exact`
## switches the repeats off; prefixes and suffixes use it, or "Assess" would read as "ass" + "es" + "s".
static func _ends(text: String, start: int, word: String, exact: bool = false) -> Array[int]:
	var out: Array[int] = []
	_match_runs(text, start, _runs(word), 0, out, exact)
	return out


static func _match_runs(text: String, pos: int, runs: Array, index: int, out: Array[int], exact: bool) -> void:
	if index == runs.size():
		out.append(pos)
		return
	var run: Array = runs[index]
	var letter: String = run[0]
	var need: int = run[1]
	var have: int = 0
	while pos + have < text.length() and text[pos + have] == letter:
		have += 1
	for count: int in range(need, (need if exact else have) + 1):
		if count <= have:
			_match_runs(text, pos + count, runs, index + 1, out, exact)


## "ass" -> [["a", 1], ["s", 2]] (cached).
static func _runs(word: String) -> Array:
	if _compiled.has(word):
		return _compiled[word] as Array
	var runs: Array = []
	for i: int in range(word.length()):
		if i > 0 and word[i] == word[i - 1]:
			(runs[runs.size() - 1] as Array)[1] += 1
		else:
			runs.append([word[i], 1])
	_compiled[word] = runs
	return runs
