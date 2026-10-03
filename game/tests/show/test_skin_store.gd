extends GutTest
## Skin storage: the JSON schema (ARCHITECTURE section 35), validation of damaged files, the 50-skin
## cap, and the slot assignments in assign.cfg.

const DIR: String = "user://test_skins_store"


func before_each() -> void:
	SkinStore.dir = DIR
	_wipe()


func after_each() -> void:
	_wipe()
	SkinStore.dir = SkinStore.DEFAULT_DIR
	SkinStore.allow_headless_default = false


func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _skin(id: String, skin_name: String = "Test") -> SkinData:
	var s: SkinData = SkinData.make_default(id, skin_name)
	s.body_style = 2
	s.turret_style = 3
	s.base = Color8(0x12, 0x34, 0x56)
	s.accent = Color8(0xAB, 0xCD, 0xEF)
	s.pattern = SkinData.Pattern.CAMO
	s.pattern_color = Color8(0xFF, 0x00, 0x80)
	s.decal = 7
	s.glow = 33
	return s


func _write_bytes(name: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/" + name, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _write(name: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var f: FileAccess = FileAccess.open(DIR + "/" + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_round_trip_keeps_every_field() -> void:
	var s: SkinData = _skin("a1")
	assert_true(SkinStore.save_skin(s))
	var back: SkinData = SkinStore.load_skin("a1")
	assert_not_null(back)
	assert_eq(back.name, "Test")
	assert_eq(back.body_style, 2)
	assert_eq(back.turret_style, 3)
	assert_eq(back.base.to_html(false), "123456")
	assert_eq(back.accent.to_html(false), "abcdef")
	assert_eq(back.pattern, SkinData.Pattern.CAMO)
	assert_eq(back.pattern_color.to_html(false), "ff0080")
	assert_eq(back.decal, 7)
	assert_eq(back.glow, 33)
	assert_eq(back.image_file, "")
	assert_null(back.image)


func test_the_file_has_exactly_the_schema_fields() -> void:
	SkinStore.save_skin(_skin("a1"))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/a1.json")) as Dictionary
	var keys: Array = d.keys()
	keys.sort()
	var want: Array = ["accent", "base", "body_style", "decal", "glow", "image", "name", "pattern", "pattern_color", "turret_style", "version"]
	assert_eq(keys, want)
	assert_eq(int(d["version"]), 1)
	assert_null(d["image"], "image is null without a picture")


func test_picture_is_a_128x64_png_next_to_the_json() -> void:
	var s: SkinData = _skin("pic")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(0.2, 0.6, 0.9))
	assert_true(SkinStore.save_skin(s))
	assert_true(FileAccess.file_exists(DIR + "/pic.png"))
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "/pic.json")) as Dictionary
	assert_eq(d["image"], "pic.png")
	var back: SkinData = SkinStore.load_skin("pic")
	assert_not_null(back.image)
	assert_eq(back.image.get_size(), Vector2i(128, 64))
	assert_eq(back.image_file, "pic.png")
	# Removing the picture removes the file.
	back.image = null
	SkinStore.save_skin(back)
	assert_false(FileAccess.file_exists(DIR + "/pic.png"))


func test_bad_fields_are_clamped_or_ignored() -> void:
	_write("bad.json", JSON.stringify({
		"version": 99, "name": 12, "body_style": 99, "turret_style": -4, "base": "not a colour", "accent": "#GG0000",
		"pattern": 2.6, "pattern_color": 5, "decal": "x", "glow": 1000, "image": "../../evil.png"}))
	var s: SkinData = SkinStore.load_skin("bad")
	assert_not_null(s, "a JSON object with bad fields still loads")
	assert_eq(s.name, "")
	assert_eq(s.body_style, 3)
	assert_eq(s.turret_style, 0)
	assert_eq(s.base, SkinData.DEFAULT_BASE)
	assert_eq(s.accent, SkinData.DEFAULT_ACCENT)
	assert_eq(s.pattern, 3, "a float rounds")
	assert_eq(s.pattern_color, SkinData.DEFAULT_PATTERN_COLOR)
	assert_eq(s.decal, 1, "a wrong type falls back to the default")
	assert_eq(s.glow, 100)
	assert_eq(s.image_file, "", "an image path that is not <id>.png is ignored")


func test_missing_fields_use_defaults() -> void:
	_write("empty.json", "{}")
	var s: SkinData = SkinStore.load_skin("empty")
	assert_not_null(s)
	assert_eq(s.glow, 50)
	assert_eq(s.decal, 1)


func test_corrupt_files_never_crash() -> void:
	_write("junk.json", "this is { not json")
	_write("array.json", "[1, 2, 3]")
	_write("string.json", "\"hello\"")
	_write("empty_file.json", "")
	_write_bytes("nul.json", PackedByteArray([0, 1, 2, 255, 254, 123, 125, 0]))
	_write("big.json", "{" + "\"x\":1,".repeat(20000) + "\"y\":2}")
	SkinStore.save_skin(_skin("good"))
	for id: String in ["junk", "array", "string", "empty_file", "nul", "big"]:
		assert_null(SkinStore.load_skin(id), id + " is rejected")
	var all: Array[SkinData] = SkinStore.list_skins()
	assert_eq(all.size(), 1, "only the readable skin is listed")
	assert_eq(all[0].id, "good")


func test_a_missing_or_damaged_picture_drops_the_picture_only() -> void:
	var s: SkinData = _skin("pic2")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	SkinStore.save_skin(s)
	var f: FileAccess = FileAccess.open(DIR + "/pic2.png", FileAccess.WRITE)
	f.store_string("not a png")
	f.close()
	var back: SkinData = SkinStore.load_skin("pic2")
	assert_not_null(back)
	assert_null(back.image)
	assert_eq(back.image_file, "")
	assert_eq(back.decal, 7, "the rest of the skin survives")


func test_a_picture_of_another_size_is_scaled_to_128x64() -> void:
	var s: SkinData = _skin("odd")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	SkinStore.save_skin(s)
	var big: Image = Image.create(300, 100, false, Image.FORMAT_RGBA8)
	big.save_png(DIR + "/odd.png")
	assert_eq(SkinStore.load_skin("odd").image.get_size(), Vector2i(128, 64))


func test_ids_are_safe_file_names() -> void:
	for bad: String in ["", "../x", "a/b", "A", "x y", "a.json", "é", "a".repeat(41)]:
		assert_false(SkinStore.valid_id(bad), "'%s' is not a valid id" % bad)
		var s: SkinData = _skin("ok")
		s.id = bad
		assert_false(SkinStore.save_skin(s), "'%s' cannot be saved" % bad)
	for good: String in ["a", "s1759_ab12", "x-1_y", "0"]:
		assert_true(SkinStore.valid_id(good))
	assert_null(SkinStore.load_skin("../etc/passwd"))


func test_new_ids_are_valid_and_unique() -> void:
	var seen: Dictionary = {}
	for i: int in range(20):
		var id: String = SkinStore.new_id()
		assert_true(SkinStore.valid_id(id))
		assert_false(seen.has(id))
		seen[id] = true
		SkinStore.save_skin(_skin(id))


func test_list_is_sorted_oldest_first_and_ignores_other_files() -> void:
	SkinStore.save_skin(_skin("s300_aaaa"))
	SkinStore.save_skin(_skin("s100_bbbb"))
	SkinStore.save_skin(_skin("s200_cccc"))
	_write("notes.txt", "hi")
	_write("Weird Name.json", "{}")
	_write("assign.cfg", "")
	assert_eq(SkinStore.list_ids(), PackedStringArray(["s100_bbbb", "s200_cccc", "s300_aaaa"]))


func test_the_cap_is_fifty_skins() -> void:
	for i: int in range(SkinStore.MAX_SKINS):
		assert_true(SkinStore.save_skin(_skin("s%03d" % i)), "skin %d fits" % i)
	assert_eq(SkinStore.count(), 50)
	assert_true(SkinStore.is_full())
	assert_false(SkinStore.save_skin(_skin("one_too_many")), "the 51st is refused")
	assert_eq(SkinStore.count(), 50)
	assert_true(SkinStore.save_skin(_skin("s000", "renamed")), "an existing skin can still be saved")
	assert_eq(SkinStore.load_skin("s000").name, "renamed")
	assert_null(SkinStore.duplicate_skin("s001"), "duplicating at the cap is refused")
	SkinStore.delete_skin("s002")
	assert_not_null(SkinStore.duplicate_skin("s001"), "room again after a delete")


func test_duplicate_copies_the_look_under_a_new_id() -> void:
	var s: SkinData = _skin("orig", "Viper")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color.RED)
	SkinStore.save_skin(s)
	var copy: SkinData = SkinStore.duplicate_skin("orig", "Viper 2")
	assert_not_null(copy)
	assert_ne(copy.id, "orig")
	assert_eq(copy.name, "Viper 2")
	assert_eq(copy.decal, 7)
	assert_eq(copy.image_file, copy.id + ".png")
	assert_true(FileAccess.file_exists(DIR + "/" + copy.id + ".png"))
	assert_eq(SkinStore.count(), 2)


func test_delete_removes_files_and_assignments() -> void:
	var s: SkinData = _skin("gone")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	SkinStore.save_skin(s)
	SkinStore.save_skin(_skin("stay"))
	SkinStore.assign(0, "gone")
	SkinStore.assign(3, "gone")
	SkinStore.assign(1, "stay")
	SkinStore.delete_skin("gone")
	assert_false(FileAccess.file_exists(DIR + "/gone.json"))
	assert_false(FileAccess.file_exists(DIR + "/gone.png"))
	assert_eq(SkinStore.assignments(), {1: "stay"})


# --- assignments --------------------------------------------------------------------------

func test_assignments_persist_in_assign_cfg() -> void:
	SkinStore.save_skin(_skin("one"))
	SkinStore.save_skin(_skin("two"))
	assert_true(SkinStore.assign(0, "one"))
	assert_true(SkinStore.assign(7, "two"))
	assert_true(FileAccess.file_exists(DIR + "/assign.cfg"))
	# A fresh read (nothing is cached in memory).
	assert_eq(SkinStore.assigned_id(0), "one")
	assert_eq(SkinStore.assigned_id(7), "two")
	assert_eq(SkinStore.assigned_id(3), "")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(DIR + "/assign.cfg"), OK)
	assert_eq(cfg.get_value("assign", "slot1"), "one", "slots are numbered from 1 on disk")
	assert_eq(cfg.get_value("assign", "slot8"), "two")
	assert_eq(SkinStore.slots_using("one"), [0] as Array[int])


func test_assign_replaces_and_unassign_clears() -> void:
	SkinStore.save_skin(_skin("one"))
	SkinStore.save_skin(_skin("two"))
	SkinStore.assign(2, "one")
	SkinStore.assign(2, "two")
	assert_eq(SkinStore.assigned_id(2), "two")
	SkinStore.unassign(2)
	assert_eq(SkinStore.assigned_id(2), "")
	SkinStore.unassign(5)
	assert_eq(SkinStore.assignments().size(), 0)


func test_bad_assignments_are_refused() -> void:
	SkinStore.save_skin(_skin("one"))
	assert_false(SkinStore.assign(-1, "one"))
	assert_false(SkinStore.assign(8, "one"))
	assert_false(SkinStore.assign(0, "missing"))
	assert_false(SkinStore.assign(0, "../one"))
	assert_eq(SkinStore.assignments().size(), 0)


func test_a_damaged_assign_file_is_ignored() -> void:
	SkinStore.save_skin(_skin("one"))
	_write("assign.cfg", "[assign]\nslot1=\"one\"\nslot2=17\nslot3=\"../x\"\nslot99=\"one\"\nthis is junk\n")
	var a: Dictionary = SkinStore.assignments()
	assert_true(a.size() <= 1)
	_write_bytes("assign.cfg", PackedByteArray([0, 1, 2, 255, 254, 91, 0, 93]))
	assert_eq(SkinStore.assignments().size(), 0)


func test_a_slot_whose_skin_file_is_gone_has_no_skin() -> void:
	SkinStore.allow_headless_default = true
	SkinStore.save_skin(_skin("one"))
	SkinStore.assign(0, "one")
	assert_not_null(SkinStore.skin_for_slot(0))
	DirAccess.remove_absolute(DIR + "/one.json")
	assert_null(SkinStore.skin_for_slot(0))
	assert_null(SkinStore.skin_for_slot(4), "nothing assigned")


func test_headless_runs_never_read_the_real_skin_folder() -> void:
	SkinStore.dir = SkinStore.DEFAULT_DIR
	assert_null(SkinStore.skin_for_slot(0))
