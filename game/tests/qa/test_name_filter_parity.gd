extends GutTest
## M7-Q: the game's NameFilter (GDScript) and the server's port (firebase/functions/src/name_filter.ts) must agree.
##
## fixtures/name_filter_corpus.json holds 2,000 random and adversarial strings with the TypeScript verdicts (regenerate with
## tools/qa/gen_name_corpus.sh; firebase/test/qa/unit/name_corpus.test.ts keeps the fixture in step with the TS filter). Every
## string is run through NameFilter here and compared on two questions:
##   clean    the text that is kept
##   allowed  whether the cleaned text is free of blocked words
##
## What the corpus showed, and what was done (numbers are pinned in BASELINE so any change is noticed):
##  * Where both sides keep the same text, the matchers agree on every string: no disagreement in the blocklist logic itself.
##  * Before M7-QF-B the server kept characters the game font cannot draw (the game deletes them), so 263 strings such as
##    "sh¬it", "fu§k", "pis®s", "arseh¬ole" were BLOCKED by the game and ALLOWED by the server (the server turned the undrawable
##    character into a word separator, the game deleted it), and 5 went the other way ("pedø").
##  * Now the server deletes exactly the characters the game deletes: the set of drawable characters is exported from the game
##    (tools/firebase/gen_name_glyphs.sh -> firebase/functions/src/name_glyphs.json) and the server's clean() uses that table.
##    On the 2,000-string corpus the two clean() outputs are identical for every string and so are the verdicts: 0 strings the
##    server allows and the game blocks, 0 the other way round, 0 differences in the cleaned text.
##    game/tests/net/test_name_glyph_table.gd keeps the table in step with the game's own check for every code point.

const CORPUS: String = "res://tests/qa/fixtures/name_filter_corpus.json"
## Pinned results for the committed corpus: [strings, clean differs, game blocks but server allows, server blocks but game allows].
const BASELINE: Array[int] = [2000, 0, 0, 0]

static var _cache: Dictionary = {}


func _load_corpus() -> Array:
	var f: FileAccess = FileAccess.open(CORPUS, FileAccess.READ)
	assert_not_null(f, "corpus fixture present")
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert_true(parsed is Array, "corpus is a JSON array")
	return parsed as Array if parsed is Array else []


func _run_parity() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var clean_diff: Array = []
	var permissive: Array = []
	var strict: Array = []
	var matcher_diff: Array = []
	var not_subsequence: Array = []
	var items: Array = _load_corpus()
	for item: Variant in items:
		var d: Dictionary = item as Dictionary
		var s: String = d["s"]
		var ts_clean: String = d["clean"]
		var ts_allowed: bool = d["allowed"]
		var gd_clean: String = NameFilter.clean(s)
		var gd_allowed: bool = NameFilter.is_allowed(s)
		if gd_clean != ts_clean:
			clean_diff.append(s)
			# Both stop at 12 characters, and the game reaches the cap later (it deletes more), so only compare when the
			# server's text was not cut short.
			if ts_clean.length() < NameFilter.MAX_LENGTH and not _is_subsequence(gd_clean, ts_clean):
				not_subsequence.append(s)
		elif gd_allowed != ts_allowed:
			matcher_diff.append(s)
		if gd_allowed != ts_allowed:
			if ts_allowed:
				permissive.append(s)
			else:
				strict.append(s)
	_cache = {"n": items.size(), "clean": clean_diff, "permissive": permissive, "strict": strict, "matcher": matcher_diff, "not_subsequence": not_subsequence}
	return _cache


## True when every character of `small` appears in `big`, in order.
func _is_subsequence(small: String, big: String) -> bool:
	var at: int = 0
	for i: int in range(big.length()):
		if at < small.length() and big[i] == small[at]:
			at += 1
	return at == small.length()


func test_the_corpus_is_present_and_big_enough() -> void:
	var r: Dictionary = _run_parity()
	assert_eq(r["n"], 2000)


func test_matchers_agree_wherever_both_sides_keep_the_same_text() -> void:
	var r: Dictionary = _run_parity()
	assert_eq(r["matcher"], [], "blocklist logic differs on identical cleaned text")


func test_the_game_never_keeps_a_character_the_server_drops() -> void:
	var r: Dictionary = _run_parity()
	assert_eq(r["not_subsequence"], [], "the server's clean() must keep at least everything the game keeps")


func test_there_are_no_disagreements() -> void:
	var r: Dictionary = _run_parity()
	var now: Array[int] = [r["n"], (r["clean"] as Array).size(), (r["permissive"] as Array).size(), (r["strict"] as Array).size()]
	assert_eq(now, BASELINE, "a changed filter or corpus: re-read the report, regenerate the glyph table, update BASELINE deliberately")


func test_cleaned_text_is_identical() -> void:
	var r: Dictionary = _run_parity()
	assert_eq((r["clean"] as Array).slice(0, 8), [], "the server's clean() must keep exactly what the game keeps")


func test_server_is_not_more_permissive() -> void:
	var r: Dictionary = _run_parity()
	var bad: Array = r["permissive"]
	assert_eq(bad.slice(0, 8), [], "the server allows %d of 2000 strings that the game blocks" % bad.size())


func test_server_is_not_stricter_either() -> void:
	# Not a safety problem, but a name the game accepted would then be rewritten by the server after the fact.
	var r: Dictionary = _run_parity()
	assert_eq((r["strict"] as Array).slice(0, 8), [], "the server blocks strings the game allows")


func test_honest_client_output_is_unchanged_by_the_server() -> void:
	# A name the game keeps as typed (clean(s) == s) must also be kept by the server, or the server would rewrite names
	# that the game itself produced.
	var changed: Array = []
	for item: Variant in _load_corpus():
		var d: Dictionary = item as Dictionary
		var s: String = d["s"]
		if NameFilter.clean(s) == s and (d["clean"] as String) != s:
			changed.append(s)
	assert_eq(changed, [])
