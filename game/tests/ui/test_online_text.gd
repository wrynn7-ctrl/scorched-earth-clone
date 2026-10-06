extends GutTest
## Player-facing text of the online layer: error mapping, relative times, code filtering, and that every string key the
## online code can show exists in strings.csv.

const SOURCE_DIRS: Array[String] = ["res://ui/online", "res://show/online", "res://ui/title", "res://ui/overlay", "res://ui/hud"]


func test_backend_reasons_map_to_specific_text() -> void:
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.NOT_FOUND, "unknown_code")), "No match or player")
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.EXHAUSTED, "match_full")), "full")
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.PERMISSION, "full_required")), "full game")
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.NAME_REJECTED, "empty")), "type a name")


func test_unknown_reasons_fall_back_to_the_code() -> void:
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.OFFLINE, "whatever")), "No connection")
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.SERVER, "x")), "problem")
	assert_string_contains(OnlineText.error(NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "x")), "update")
	assert_ne(OnlineText.error(NetResult.failure(NetError.Code.BAD_RESPONSE, "x")), "", "something is always said")


func test_relative_times() -> void:
	var now: int = 10 * 86400000
	assert_eq(OnlineText.ago(now, now - 20000), "just now")
	assert_eq(OnlineText.ago(now, now - 5 * 60000), "5 min ago")
	assert_eq(OnlineText.ago(now, now - 3 * 3600000), "3 h ago")
	assert_eq(OnlineText.ago(now, now - 2 * 86400000), "2 d ago")
	assert_eq(OnlineText.ago(now, 0), "")
	assert_eq(OnlineText.ago(now, now + 5000), "just now", "a clock that is a little off never shows a negative time")


func test_code_filter() -> void:
	assert_eq(OnlineText.filter_code("abc-234", 6), "ABC234")
	assert_eq(OnlineText.filter_code("0O1Iabc", 6), "ABC")
	assert_eq(OnlineText.filter_code("zzzzzzzzzz", 6), "ZZZZZZ")
	assert_eq(OnlineText.filter_code("", 6), "")
	assert_eq(OnlineText.spaced("ABCD2345"), "ABCD 2345")
	assert_eq(OnlineText.spaced("ABC"), "ABC")


func _keys_in(dir: String, out: Dictionary) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	var rx := RegEx.new()
	rx.compile("\"((?:NET|MSG)_[A-Z0-9_]+|TITLE_ONLINE|UNLOCK_CTX_HOST)\"")
	for f: String in da.get_files():
		if f.ends_with(".gd"):
			var text: String = FileAccess.get_file_as_string(dir.path_join(f))
			for m: RegExMatch in rx.search_all(text):
				out[m.get_string(1)] = dir.path_join(f)
	for d: String in da.get_directories():
		_keys_in(dir.path_join(d), out)


func test_every_online_string_key_is_in_the_csv() -> void:
	var csv: String = FileAccess.get_file_as_string("res://locale/strings.csv")
	var keys: Dictionary = {}
	for dir: String in SOURCE_DIRS:
		_keys_in(dir, keys)
	for k: String in OnlineText.all_keys():
		keys[k] = "OnlineText"
	for spec: Array in MessageDefs.TABLE:
		keys[spec[0] as String] = "MessageDefs"
	assert_gt(keys.size(), 150, "found the keys")
	for k: String in keys.keys():
		assert_true(csv.contains("\n" + k + ","), "%s (%s) is missing from strings.csv" % [k, keys[k]])


func test_keys_built_with_tr_calls_exist_too() -> void:
	# tr("KEY") with a literal key in the online sources, plus the labels the tabs use.
	var csv: String = FileAccess.get_file_as_string("res://locale/strings.csv")
	var rx := RegEx.new()
	rx.compile("tr\\(\"([A-Z0-9_]+)\"\\)")
	var bad: Array[String] = []
	for dir: String in ["res://ui/online", "res://show/online"]:
		var da: DirAccess = DirAccess.open(dir)
		for f: String in da.get_files():
			if f.ends_with(".gd"):
				for m: RegExMatch in rx.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
					if not csv.contains("\n" + m.get_string(1) + ","):
						bad.append("%s in %s" % [m.get_string(1), f])
	assert_eq(bad, [] as Array[String])


func test_the_csv_has_no_duplicate_keys() -> void:
	var seen: Dictionary = {}
	var dups: Array[String] = []
	var f: FileAccess = FileAccess.open("res://locale/strings.csv", FileAccess.READ)
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() >= 1 and row[0] != "":
			if seen.has(row[0]):
				dups.append(row[0])
			seen[row[0]] = true
	assert_eq(dups, [] as Array[String])
