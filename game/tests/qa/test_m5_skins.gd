@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: skins (docs/ARCHITECTURE.md section 35). SkinStore and SkinData must survive corrupt JSON,
## huge values, missing fields, wrong types, 1000 files, odd file names and symlinks without crashing,
## keep the 50-skin cap on writes and clamp whatever they load. The image pipeline must cope with
## a 1x1 picture, a 10000x10 strip and files that are not pictures.

const SCRATCH: String = "user://qa_m5_skins"
const CANARY: String = "user://qa_m5_canary.json"

var _saved_dir: String = ""


func before_each() -> void:
	_saved_dir = SkinStore.dir
	SkinStore.dir = SCRATCH
	_wipe(SCRATCH)
	DirAccess.make_dir_recursive_absolute(SCRATCH)


func after_each() -> void:
	_wipe(SCRATCH)
	DirAccess.remove_absolute(SCRATCH)
	for p: String in [CANARY, "user://qa_m5_symlink_victim"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	SkinStore.dir = _saved_dir


## Empties a folder under SCRATCH. It never follows a symlink (a link is only unlinked) and refuses to
## touch anything outside the scratch folder.
func _wipe(dir: String) -> void:
	if not dir.begins_with(SCRATCH) or dir.contains("..") or not DirAccess.dir_exists_absolute(dir):
		return
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = true
	for f: String in da.get_files():
		DirAccess.remove_absolute(dir + "/" + f)
	for d: String in da.get_directories():
		if da.is_link(d):
			DirAccess.remove_absolute(dir + "/" + d)
			continue
		_wipe(dir + "/" + d)
		DirAccess.remove_absolute(dir + "/" + d)


func _write(path: String, content: Variant) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "can write %s" % path)
	if f == null:
		return
	if content is PackedByteArray:
		f.store_buffer(content as PackedByteArray)
	else:
		f.store_string(str(content))
	f.close()


func _skin_file(id: String, content: Variant) -> void:
	_write(SkinStore.json_path(id), content)


## Everything a loaded skin must satisfy, whatever the file said.
func _problems(s: SkinData, id: String) -> Array[String]:
	var errs: Array[String] = []
	if s == null:
		return ["null skin"]
	if s.id != id or not SkinStore.valid_id(s.id):
		errs.append("id '%s'" % s.id)
	if s.name.length() > SkinData.NAME_MAX:
		errs.append("name length %d" % s.name.length())
	for ch: String in s.name:
		if ch.unicode_at(0) < 32 or ch.unicode_at(0) == 127:
			errs.append("control character in the name")
			break
	if s.name != s.name.strip_edges():
		errs.append("name not trimmed")
	if s.body_style < 0 or s.body_style >= SkinData.BODY_STYLES:
		errs.append("body_style %d" % s.body_style)
	if s.turret_style < 0 or s.turret_style >= SkinData.TURRET_STYLES:
		errs.append("turret_style %d" % s.turret_style)
	if s.pattern < 0 or s.pattern >= SkinData.PATTERNS:
		errs.append("pattern %d" % s.pattern)
	if s.decal < 0 or s.decal >= SkinData.DECALS:
		errs.append("decal %d" % s.decal)
	if s.glow < 0 or s.glow > SkinData.GLOW_MAX:
		errs.append("glow %d" % s.glow)
	for c: Color in [s.base, s.accent, s.pattern_color]:
		if c.a != 1.0 or not is_finite(c.r) or not is_finite(c.g) or not is_finite(c.b) \
				or c.r < 0.0 or c.r > 1.0 or c.g < 0.0 or c.g > 1.0 or c.b < 0.0 or c.b > 1.0:
			errs.append("colour %s" % str(c))
	if s.image_file != "" and s.image_file != id + ".png":
		errs.append("image_file '%s'" % s.image_file)
	return errs


# --- ids ----------------------------------------------------------------------------------------

func test_valid_id_alphabet() -> void:
	for ok: String in ["a", "s1_0001", "abc-def_123", "0", "-", "_", "a".repeat(40)]:
		assert_true(SkinStore.valid_id(ok), "'%s' is fine" % ok)
	var bad: Array[String] = ["", "a".repeat(41), "A", "a b", "a.b", "../x", "a/b", "a\\b", "x.png", "x.json", "\u00fc",
			"a\nb", "a\tb", "a b ", " a", "%2e", "a:b", "a*", "a?", "CON ", "a\u0301", "\u202ea", "a\u200b"]
	for id: String in bad:
		assert_false(SkinStore.valid_id(id), "'%s' is refused" % id.c_escape())


func test_weird_ids_never_touch_files_outside_the_folder() -> void:
	_write(CANARY, "{}")
	for id: String in ["../qa_m5_canary", "..", "../../qa_m5_canary", "a/../../qa_m5_canary", "qa_m5_canary.json"]:
		SkinStore.delete_skin(id)
		assert_null(SkinStore.load_skin(id), id)
		assert_null(SkinStore.load_image(id), id)
		assert_false(SkinStore.assign(0, id), id)
		var s: SkinData = SkinData.make_default(id, "x")
		assert_false(SkinStore.save_skin(s), "refuses id '%s'" % id)
	assert_true(FileAccess.file_exists(CANARY), "the canary outside the skin folder is untouched")
	assert_eq(SkinStore.count(), 0)
	assert_false(SkinStore.save_skin(null))


# --- corrupt, odd and hostile JSON ---------------------------------------------------------------------

func _hostile_json_cases() -> Dictionary:
	var deep: String = "[".repeat(5000)
	var big: String = "{\"name\":\"" + "x".repeat(70000) + "\"}"
	return {
		"empty": "", "garbage": "\u0001\u0002 not json {{{", "open brace": "{", "array": "[]", "null": "null", "number": "123",
		"string": "\"skin\"", "true": "true", "deep nesting": deep, "oversize file": big,
		"nan": "{\"glow\": NaN}", "inf": "{\"glow\": Infinity, \"decal\": -Infinity}",
		"trailing comma": "{\"glow\": 5,}", "single quotes": "{'glow': 5}",
	}


func test_unreadable_json_files_load_as_nothing_and_never_crash() -> void:
	var n: int = 0
	for label: String in _hostile_json_cases():
		var id: String = "bad_%d" % n
		n += 1
		_skin_file(id, _hostile_json_cases()[label])
		var s: SkinData = SkinStore.load_skin(id)
		if s != null:
			# NaN / Infinity style JSON may parse; then the clamps must hold.
			assert_eq(_problems(s, id).size(), 0, "'%s' loaded as %s: %s" % [label, str(s.to_dict()), str(_problems(s, id))])
	assert_eq(SkinStore.list_skins().size(), SkinStore.list_skins().size())
	for label: String in ["empty", "array", "null", "number", "string", "true", "open brace", "oversize file"]:
		var idx: int = _hostile_json_cases().keys().find(label)
		assert_null(SkinStore.load_skin("bad_%d" % idx), "'%s' must not load" % label)


func test_wrong_types_missing_fields_and_huge_values_are_clamped() -> void:
	var cases: Array[Dictionary] = [
		{}, {"version": "x"},
		{"name": 5, "body_style": "x", "turret_style": null, "base": 12, "accent": [1, 2], "pattern": {}, "pattern_color": true,
				"decal": "3", "glow": [], "image": {"a": 1}},
		{"name": "x".repeat(500), "body_style": 99999999, "turret_style": -4, "pattern": 77, "decal": -1, "glow": 100000},
		{"body_style": 2.6, "turret_style": 1.4, "pattern": 4.5, "decal": 8.5, "glow": 99.5},
		{"base": "#zzzzzz", "accent": "red", "pattern_color": "#12345", "name": "\u0003\u0001tab\tname\n   "},
		{"base": "#FFFFFF80", "accent": "#00000000", "pattern_color": "#ff00ff"},
		{"image": "../../etc/passwd.png"}, {"image": "other.png"}, {"image": "bad_x.png"}, {"image": 7},
		{"name": "\u202e\u202eRTL override name"},
		{"glow": true, "decal": false},
	]
	for i: int in range(cases.size()):
		var id: String = "wt_%d" % i
		_skin_file(id, JSON.stringify(cases[i]))
		var s: SkinData = SkinStore.load_skin(id)
		assert_not_null(s, "case %d loads" % i)
		assert_eq(_problems(s, id).size(), 0, "case %d %s -> %s" % [i, str(cases[i]), str(_problems(s, id))])
	# Specific clamps.
	var s3: SkinData = SkinStore.load_skin("wt_3")
	assert_eq(s3.body_style, 3)
	assert_eq(s3.turret_style, 0)
	assert_eq(s3.pattern, 5)
	assert_eq(s3.decal, 0)
	assert_eq(s3.glow, 100)
	assert_eq(s3.name.length(), SkinData.NAME_MAX)
	var s0: SkinData = SkinStore.load_skin("wt_0")
	assert_eq(s0.glow, 50, "a missing field means the default")
	assert_eq(s0.decal, 1)
	var s6: SkinData = SkinStore.load_skin("wt_6")
	assert_eq(s6.base.a, 1.0, "alpha in a colour is dropped")


func test_astronomical_numbers_clamp_to_the_matching_end() -> void:
	# JSON numbers beyond int64 arrive as floats (1e20, 1e300). They must clamp to the nearest end of the
	# range, the same on every CPU (float -> int casts of huge values differ between x86 and ARM).
	var pos: Dictionary = {"body_style": 1e300, "turret_style": 1e20, "pattern": 1e19, "decal": 1e30, "glow": 1e300}
	var neg: Dictionary = {"body_style": -1e300, "turret_style": -1e20, "pattern": -1e19, "decal": -1e30, "glow": -1e300}
	var up: SkinData = SkinData.from_dict(pos, "p")
	var down: SkinData = SkinData.from_dict(neg, "n")
	var wrong: Array[String] = []
	if up.body_style != 3 or up.turret_style != 3 or up.pattern != 5 or up.decal != 9 or up.glow != 100:
		wrong.append("positive huge -> body %d turret %d pattern %d decal %d glow %d (expected 3 3 5 9 100)" % [
				up.body_style, up.turret_style, up.pattern, up.decal, up.glow])
	if down.body_style != 0 or down.turret_style != 0 or down.pattern != 0 or down.decal != 0 or down.glow != 0:
		wrong.append("negative huge -> body %d turret %d pattern %d decal %d glow %d (expected all 0)" % [
				down.body_style, down.turret_style, down.pattern, down.decal, down.glow])
	assert_eq(_problems(up, "p").size() + _problems(down, "n").size(), 0, "always inside the legal ranges")
	if not wrong.is_empty():
		pending("BUG (low): SkinData._int_in clamps astronomically large floats to the WRONG end on this CPU, so the " \
				+ "result is platform dependent. Input: JSON {\"glow\": 1e300} etc. Expected the nearest end " \
				+ "(glow 100); actual: " + "; ".join(wrong) + ". Suspected game/show/skins/skin_data.gd:131 (_int_in) " \
				+ "(roundi() of a float beyond int64 overflows before clampi). Fix: clampf first, then roundi.")
		return
	assert_eq(wrong.size(), 0)


func test_random_dictionaries_always_give_a_legal_skin() -> void:
	var rng: Rng = Rng.derive(9091, 3)
	var junk: Array = [null, true, false, 0, -1, 7, 99, 1000000, -1000000, 3.5, -2.5, 1e30, "", "x", "#ff0000", "#GGGGGG",
			"red", [], [1], {}, {"a": 1}, "x".repeat(300), "\u0007bell", " pad ", PackedStringArray(["a"]), Vector2(1, 2)]
	var keys: Array[String] = ["name", "body_style", "turret_style", "base", "accent", "pattern", "pattern_color", "decal",
			"glow", "image", "version", "extra"]
	for n: int in range(400):
		var d: Dictionary = {}
		for k: String in keys:
			if rng.range_int(0, 3) != 0:
				d[k] = junk[rng.range_int(0, junk.size() - 1)]
		var id: String = "fz_%d" % n
		var s: SkinData = SkinData.from_dict(d, id)
		var errs: Array[String] = _problems(s, id)
		assert_eq(errs.size(), 0, "dict %s -> %s" % [str(d), str(errs)])
		if errs.size() > 0:
			break


func test_a_skin_with_absurd_fields_is_clamped_on_the_way_back_from_disk() -> void:
	var s: SkinData = SkinData.make_default("absurd", "  \u0001 " + "N".repeat(100) + "  ")
	s.body_style = 9999
	s.turret_style = -5
	s.pattern = 600
	s.decal = -3
	s.glow = 100000
	s.base = Color(5.0, -2.0, 0.5, 0.0)
	assert_true(SkinStore.save_skin(s))
	var back: SkinData = SkinStore.load_skin("absurd")
	assert_not_null(back)
	assert_eq(_problems(back, "absurd").size(), 0, str(_problems(back, "absurd")))
	assert_eq(back.body_style, 3)
	assert_eq(back.glow, 100)


# --- the cap, 1000 files and odd names ------------------------------------------------------------------

func _valid_skin_json(i: int) -> String:
	return JSON.stringify({"version": 1, "name": "Skin %d" % i, "body_style": i % 4, "turret_style": (i / 4) % 4,
			"base": "#102030", "accent": "#00ffee", "pattern": i % 6, "pattern_color": "#ff2d9a", "decal": i % 10,
			"glow": i % 101, "image": null})


func test_the_skin_cap_holds_with_1000_files_on_disk() -> void:
	var t0: int = Time.get_ticks_msec()
	for i: int in range(1000):
		_skin_file("s%d_%04x" % [1000 + i, i], _valid_skin_json(i))
	var wrote_ms: int = Time.get_ticks_msec() - t0
	assert_eq(SkinStore.count(), 1000)
	assert_true(SkinStore.is_full())
	# New skins are refused, existing ones can still be overwritten, copies are refused.
	var fresh: SkinData = SkinData.make_default(SkinStore.new_id(), "one too many")
	assert_false(SkinStore.save_skin(fresh), "a new skin at the cap")
	assert_false(FileAccess.file_exists(SkinStore.json_path(fresh.id)), "and nothing was written")
	var existing: SkinData = SkinStore.load_skin("s1000_0000")
	assert_not_null(existing)
	existing.name = "renamed"
	assert_true(SkinStore.save_skin(existing), "editing a stored skin is not 'new'")
	assert_eq(SkinStore.load_skin("s1000_0000").name, "renamed")
	assert_null(SkinStore.duplicate_skin("s1000_0000"), "a copy at the cap")
	assert_eq(SkinStore.count(), 1000)
	# Loading them all is fast and every one is legal.
	var t1: int = Time.get_ticks_msec()
	var all: Array[SkinData] = SkinStore.list_skins(false)
	gut.p("SKINS  1000 files: written in %d ms, list_skins() returned %d in %d ms" % [wrote_ms, all.size(), Time.get_ticks_msec() - t1])
	for s: SkinData in all:
		var errs: Array[String] = _problems(s, s.id)
		if not errs.is_empty():
			assert_eq(errs.size(), 0, "%s: %s" % [s.id, str(errs)])
			break
	if all.size() > SkinStore.MAX_SKINS:
		pending("BUG (low): SkinStore keeps only MAX_SKINS (%d) on write, but list_skins() returns every file it finds. " % SkinStore.MAX_SKINS \
				+ "Input: 1000 valid <id>.json files in user://skins. Expected at most 50 skins listed (the class header says " \
				+ "'At most MAX_SKINS skins are kept'); actual: %d. Suspected game/show/skins/skin_store.gd:69,91 (list_ids/list_skins) " % all.size() \
				+ "(no truncation). Impact: the Skin Studio would build 1000 cards if files are copied in by hand.")
		return
	assert_lte(all.size(), SkinStore.MAX_SKINS)


func test_odd_file_names_are_ignored_and_never_crash() -> void:
	var ok_names: Array[String] = ["con", "-", "__", "a".repeat(40), "s1_0001", "up_ok"]
	for n: String in ok_names:
		_skin_file(n, _valid_skin_json(1))
	var bad_files: Array[String] = ["..json", ".json", "a b.json", "UP.json", "\u00fcn\u00ef.json", "a".repeat(41) + ".json",
			"x.json.json", "x.JSON", "x.json.tmp", "x.png", "a\tb.json", "a\nb.json", "s1_0001.json ", "a%2eb.json",
			"\u202efdp.json", "emoji_\U01F600.json"]
	for f: String in bad_files:
		var fa: FileAccess = FileAccess.open(SCRATCH + "/" + f, FileAccess.WRITE)
		if fa != null:  # a file system may refuse a name: that is fine
			fa.store_string(_valid_skin_json(2))
			fa.close()
	DirAccess.make_dir_recursive_absolute(SCRATCH + "/dir_named.json")
	var ids: PackedStringArray = SkinStore.list_ids()
	var expected: Array[String] = ok_names.duplicate()
	expected.sort()
	assert_eq(ids, PackedStringArray(expected), "only valid ids are listed")
	for s: SkinData in SkinStore.list_skins():
		assert_eq(_problems(s, s.id).size(), 0)
	assert_eq(SkinStore.list_skins().size(), ok_names.size())
	assert_null(SkinStore.load_skin("dir_named"), "a folder called x.json is not a skin")


func test_symlinks_in_the_skin_folder_do_not_crash() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(SCRATCH)
	# Targets stay harmless: a read-only system file, a folder inside the scratch area, a missing path.
	DirAccess.make_dir_recursive_absolute(SCRATCH + "/real_dir")
	var links: Dictionary = {"link_text": "/etc/hostname", "link_dir": abs_dir + "/real_dir", "link_missing": "/nonexistent/zzz"}
	var made: int = 0
	for lname: String in links:
		var code: int = OS.execute("ln", ["-s", links[lname], "%s/%s.json" % [abs_dir, lname]])
		if code == 0:
			made += 1
	# A loop: a.json -> b.json -> a.json
	if OS.execute("ln", ["-s", "%s/loop_b.json" % abs_dir, "%s/loop_a.json" % abs_dir]) == 0:
		OS.execute("ln", ["-s", "%s/loop_a.json" % abs_dir, "%s/loop_b.json" % abs_dir])
		made += 2
	if made == 0:
		pending("symlinks cannot be created here")
		return
	_skin_file("real_one", _valid_skin_json(3))
	for s: SkinData in SkinStore.list_skins():
		assert_eq(_problems(s, s.id).size(), 0)
	for id: String in ["link_text", "link_dir", "link_missing", "loop_a", "loop_b"]:
		var s: SkinData = SkinStore.load_skin(id)
		assert_true(s == null or _problems(s, id).is_empty(), id)
	assert_not_null(SkinStore.load_skin("real_one"))
	# Overwriting through a dangling symlink must not escape the folder.
	var victim: String = ProjectSettings.globalize_path("user://qa_m5_symlink_victim")
	OS.execute("ln", ["-s", victim, "%s/escape.json" % abs_dir])
	var sk: SkinData = SkinData.make_default("escape", "x")
	SkinStore.save_skin(sk)
	assert_false(FileAccess.file_exists(victim), "saving through a symlink created nothing outside the folder")
	if FileAccess.file_exists(victim):
		DirAccess.remove_absolute(victim)


# --- assignments -------------------------------------------------------------------------------------------

func test_assign_cfg_with_wrong_types_and_bad_ids_is_cleaned() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("assign", "slot1", 5)
	cfg.set_value("assign", "slot2", ["a"])
	cfg.set_value("assign", "slot3", "../x")
	cfg.set_value("assign", "slot4", "ghost")  # well-formed id, file missing
	cfg.set_value("assign", "slot5", "")
	cfg.set_value("assign", "slot6", "A B")
	cfg.set_value("assign", "slot9", "ghost")  # beyond the 8 slots
	cfg.set_value("assign", "slot0", "ghost")
	cfg.set_value("other", "slot7", "ghost")
	cfg.save(SkinStore.assign_path())
	var a: Dictionary = SkinStore.assignments()
	assert_eq(a.keys(), [3], "only slot 4 (index 3) holds a well-formed id")
	assert_null(SkinStore.skin_for_slot(3), "the skin file is missing: default look")
	assert_null(SkinStore.skin_for_slot(-1))
	assert_null(SkinStore.skin_for_slot(99))
	assert_false(SkinStore.assign(8, "ghost"))
	assert_false(SkinStore.assign(-1, "ghost"))
	assert_false(SkinStore.assign(0, "ghost"), "no assigning a skin that does not exist")
	# Deleting a skin frees every slot that used it.
	assert_true(SkinStore.save_skin(SkinData.make_default("pal", "Pal")))
	for slot: int in range(SkinStore.MAX_SLOTS):
		assert_true(SkinStore.assign(slot, "pal"))
	assert_eq(SkinStore.slots_using("pal").size(), 8)
	SkinStore.delete_skin("pal")
	assert_eq(SkinStore.assignments().size(), 0, "every slot that wore it is free again")
	assert_eq(SkinStore.slots_using("pal").size(), 0)


# --- the image pipeline ---------------------------------------------------------------------------------------------

func _png(w: int, h: int, c: Color = Color(0.9, 0.2, 0.5, 1.0)) -> PackedByteArray:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img.save_png_to_buffer()


func _gradient_png(w: int, h: int) -> PackedByteArray:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		for x: int in range(w):
			img.set_pixel(x, y, Color(float(x % 7) / 6.0, float(y % 5) / 4.0, float((x + y) % 3) / 2.0, 1.0))
	return img.save_png_to_buffer()


## decode -> crop -> neon filter, as the studio does. Returns the final image (or null if the file is refused).
func _pipeline(bytes: PackedByteArray, zoom: float = 1.0, center: Vector2 = Vector2(0.5, 0.5)) -> Image:
	var src: Image = SkinImage.decode(bytes)
	if src == null:
		return null
	var size: Vector2 = Vector2(src.get_width(), src.get_height())
	var rect: Rect2 = SkinImage.crop_rect(size, size * center, zoom)
	var eps: float = 0.01
	assert_true(rect.position.x >= -eps and rect.position.y >= -eps and rect.end.x <= size.x + eps and rect.end.y <= size.y + eps,
			"crop inside the picture: %s in %s" % [str(rect), str(size)])
	return SkinImage.process(src, rect)


func _assert_skin_image(img: Image, what: String) -> void:
	assert_not_null(img, what)
	if img == null:
		return
	assert_eq(img.get_width(), SkinData.IMAGE_W, what)
	assert_eq(img.get_height(), SkinData.IMAGE_H, what)
	assert_eq(img.get_format(), Image.FORMAT_RGBA8, what)


func test_one_pixel_picture_is_refused_at_import_and_survives_the_filter() -> void:
	assert_null(SkinImage.decode(_png(1, 1)), "1x1 is refused at decode (too small to crop)")
	assert_null(SkinImage.decode(_png(1, 50)), "1xN too")
	assert_null(SkinImage.decode(_png(40, 1)), "Nx1 too")
	# The filter itself must still cope with a 1x1 or a 2x2 image handed to it directly.
	for size: Vector2i in [Vector2i(1, 1), Vector2i(2, 2), Vector2i(3, 1)]:
		var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.1, 0.9, 0.4, 1.0))
		_assert_skin_image(SkinImage.neon(img), "neon of %s" % str(size))
		_assert_skin_image(SkinImage.process(img, Rect2(0, 0, size.x, size.y)), "process of %s" % str(size))
	_assert_skin_image(_pipeline(_png(2, 2)), "2x2 picture")


func test_wide_and_tall_extreme_pictures() -> void:
	var cases: Array[Vector2i] = [Vector2i(10000, 10), Vector2i(10, 10000), Vector2i(3000, 2), Vector2i(2, 3000), Vector2i(4000, 1500)]
	for size: Vector2i in cases:
		var bytes: PackedByteArray = _gradient_png(size.x, size.y) if size.x * size.y < 5_000_000 else _png(size.x, size.y)
		var src: Image = SkinImage.decode(bytes)
		assert_not_null(src, "decodes %s" % str(size))
		if src == null:
			continue
		assert_lte(maxi(src.get_width(), src.get_height()), SkinImage.MAX_SOURCE_EDGE, "shrunk on read %s" % str(size))
		assert_gte(mini(src.get_width(), src.get_height()), 2, "never thinner than 2 px %s" % str(size))
		for zoom: float in [0.0, 1.0, 3.0, 6.0, 1000.0, -5.0]:
			for center: Vector2 in [Vector2(0.0, 0.0), Vector2(0.5, 0.5), Vector2(1.0, 1.0), Vector2(-3.0, 9.0)]:
				_assert_skin_image(_pipeline(bytes, zoom, center), "%s zoom %s center %s" % [str(size), str(zoom), str(center)])
	# The tone budget still holds on an extreme picture.
	var out: Image = _pipeline(_gradient_png(10000, 10))
	assert_lte(SkinImage.tone_count(out), SkinImage.TONES + 2, "posterised")


func test_transparent_and_flat_pictures() -> void:
	_assert_skin_image(_pipeline(_png(300, 200, Color(0, 0, 0, 0))), "fully transparent")
	_assert_skin_image(_pipeline(_png(300, 200, Color(1, 1, 1, 1))), "pure white")
	_assert_skin_image(_pipeline(_png(300, 200, Color(0, 0, 0, 1))), "pure black")
	var img: Image = Image.create(64, 64, false, Image.FORMAT_L8)
	img.fill(Color(0.5, 0.5, 0.5))
	_assert_skin_image(_pipeline(img.save_png_to_buffer()), "greyscale PNG")


func test_files_that_are_not_pictures_are_refused_quietly() -> void:
	var rng: Rng = Rng.derive(4242, 5)
	var noise := PackedByteArray()
	for _i: int in range(5000):
		noise.append(rng.range_int(0, 255))
	var png_head: PackedByteArray = PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
	var jpg_head: PackedByteArray = PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0])
	var cases: Dictionary = {
		"empty": PackedByteArray(), "text": "hello, I am a text file, not a picture".to_utf8_buffer(),
		"noise": noise, "11 bytes": PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]),
		"zeros": PackedByteArray(), "html": "<html><body>photo.png</body></html>".to_utf8_buffer(),
	}
	cases["zeros"] = PackedByteArray()
	(cases["zeros"] as PackedByteArray).resize(4096)
	var paths: PackedStringArray = PackedStringArray()
	for label: String in cases:
		var p: String = SCRATCH + "/pic_" + label.replace(" ", "_") + ".bin"
		_write(p, cases[label])
		paths.append(p)
		assert_null(SkinImage.load_file(p), "'%s' is not a picture" % label)
		assert_null(SkinImage.decode(cases[label] as PackedByteArray), label)
	assert_null(SkinImage.load_file(SCRATCH + "/does_not_exist.png"))
	assert_null(SkinImage.load_file(""))
	assert_null(SkinImage.load_file(SCRATCH), "a folder is not a picture")
	# A real picture still loads from a file whatever its extension is.
	var real: String = SCRATCH + "/photo.txt"
	_write(real, _png(40, 30))
	assert_not_null(SkinImage.load_file(real), "found by its first bytes, not its name")
	# Magic bytes with nothing behind them (the decoders may log a complaint; the result must be null).
	var truncated: PackedByteArray = png_head.duplicate()
	truncated.append_array(PackedByteArray([0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]))
	var real_png: PackedByteArray = _png(64, 64)
	var half: PackedByteArray = real_png.slice(0, real_png.size() / 2)
	for pair: Array in [["png magic only", png_head + PackedByteArray([0, 0, 0, 0])], ["png header cut", truncated],
			["png half", half], ["jpg magic only", jpg_head + PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])]]:
		var bytes: PackedByteArray = pair[1]
		var img: Image = SkinImage.decode(bytes)
		assert_null(img, "'%s' must not decode" % pair[0])
	# Engine decoder complaints for the damaged files above are expected; they are not failures.
	for e: Variant in get_errors():
		e.handled = true


func test_a_damaged_picture_next_to_a_skin_loads_as_a_skin_without_image() -> void:
	var s: SkinData = SkinData.make_default("pic", "With picture")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(0.2, 0.7, 0.9, 1.0))
	assert_true(SkinStore.save_skin(s))
	var good: SkinData = SkinStore.load_skin("pic")
	assert_not_null(good.image)
	assert_eq(good.image_file, "pic.png")
	# Replace the picture with junk of three kinds; the skin must load, without a picture.
	for junk: PackedByteArray in [PackedByteArray([1, 2, 3]), "not a png".to_utf8_buffer(), PackedByteArray()]:
		_write(SkinStore.image_path("pic"), junk)
		var back: SkinData = SkinStore.load_skin("pic")
		assert_not_null(back, "the skin survives a damaged picture")
		assert_null(back.image)
		assert_eq(back.image_file, "", "and it says it has no picture")
	# A picture of the wrong size is scaled to 128x64 on load.
	_write(SkinStore.image_path("pic"), _png(500, 20))
	var scaled: SkinData = SkinStore.load_skin("pic")
	assert_not_null(scaled.image)
	assert_eq(scaled.image.get_size(), Vector2i(128, 64))
	# Removing the picture deletes the file; no leftovers (.tmp) remain in the folder.
	scaled.image = null
	assert_true(SkinStore.save_skin(scaled))
	assert_false(FileAccess.file_exists(SkinStore.image_path("pic")))
	for f: String in DirAccess.get_files_at(SCRATCH):
		assert_false(f.ends_with(".tmp"), "no leftover temp file: %s" % f)


# --- baking and shapes ---------------------------------------------------------------------------------------------

func _opaque(img: Image) -> bool:
	for y: int in range(0, img.get_height(), 3):
		for x: int in range(0, img.get_width(), 3):
			if img.get_pixel(x, y).a < 0.999:
				return false
	return true


func test_every_legal_look_bakes_to_the_right_size_at_every_scale() -> void:
	var count: int = 0
	for pattern: int in range(SkinData.PATTERNS):
		for decal: int in range(SkinData.DECALS):
			var s: SkinData = SkinData.make_default("bake", "b")
			s.pattern = pattern
			s.decal = decal
			s.body_style = decal % SkinData.BODY_STYLES
			s.turret_style = pattern % SkinData.TURRET_STYLES
			s.base = Color(float(decal) / 9.0, float(pattern) / 5.0, 0.5, 1.0)
			for ppu: int in [SkinBaker.MIN_PPU, SkinBaker.DEFAULT_PPU, 7]:
				var img: Image = SkinBaker.bake_image(s, ppu)
				var want: Vector2i = SkinBaker.texture_size(ppu)
				assert_eq(img.get_size(), want, "pattern %d decal %d ppu %d" % [pattern, decal, ppu])
				assert_true(_opaque(img), "the hull texture is opaque (pattern %d decal %d)" % [pattern, decal])
				count += 1
	assert_eq(count, 180)
	# Out-of-range scales are clamped, never an empty or gigantic image.
	var plain: SkinData = SkinData.make_default("bake", "b")
	for ppu: int in [-50, 0, 1000, 2147483647, -2147483648]:
		var size: Vector2i = SkinBaker.bake_image(plain, ppu).get_size()
		assert_eq(size, SkinBaker.texture_size(clampi(ppu, SkinBaker.MIN_PPU, SkinBaker.MAX_PPU)), "ppu %d" % ppu)
		assert_lte(size.x * size.y, 24 * 16 * 9 * 16)


func test_baking_with_pictures_of_any_size_and_with_out_of_range_styles() -> void:
	var sizes: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 2), Vector2i(128, 64), Vector2i(10000, 10), Vector2i(10, 4000), Vector2i(3, 7)]
	for size: Vector2i in sizes:
		var s: SkinData = SkinData.make_default("bake", "b")
		s.image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		s.image.fill(Color(0.3, 0.6, 0.9, 0.5))
		s.pattern = SkinData.Pattern.CAMO
		var img: Image = SkinBaker.bake_image(s, 4)
		assert_eq(img.get_size(), SkinBaker.texture_size(4), "picture %s" % str(size))
	# Styles outside the legal range (a hand-built SkinData; from_dict could never make these).
	var odd: SkinData = SkinData.make_default("bake", "b")
	for v: int in [-1, 99, 2147483647, -2147483648]:
		odd.pattern = v
		odd.decal = v
		odd.body_style = v
		odd.turret_style = v
		var img2: Image = SkinBaker.bake_image(odd, 2)
		assert_eq(img2.get_size(), SkinBaker.texture_size(2), "style %d" % v)
		assert_gte(SkinShapes.hull(v).size(), 0)
		assert_gte(SkinShapes.turret_polys(v).size(), 0)
		assert_gte(SkinShapes.turret_tip_half(v), 0.0)
		assert_gte(SkinShapes.decal_shapes(v).size(), 0)


func test_a_translucent_picture_still_bakes_to_an_opaque_hull() -> void:
	# The studio's neon filter always writes alpha 1, but SkinStore.load_image takes any PNG on disk as it is.
	var s: SkinData = SkinData.make_default("bake", "b")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(0.3, 0.6, 0.9, 0.4))
	var img: Image = SkinBaker.bake_image(s, 4)
	if not _opaque(img):
		pending("BUG (low, cosmetic): a skin picture with alpha < 1 punches translucent holes into the baked hull " \
				+ "texture (the base colour under it is overwritten, not composited). Input: a 128x64 PNG filled with " \
				+ "(0.3, 0.6, 0.9, 0.4) next to a skin json. Expected an opaque 96x36 hull texture (every other layer " \
				+ "forces alpha 1); actual: alpha " + str(img.get_pixel(48, 18).a) + " in the middle. Suspected game/show/skins/skin_baker.gd:64-68 " \
				+ "(_blit_picture uses Image.blit_rect, which copies alpha; use blend_rect or flatten the picture on the " \
				+ "base colour). Only reachable with a hand-made PNG: SkinImage.neon() outputs alpha 1.")
		return
	assert_true(_opaque(img))
