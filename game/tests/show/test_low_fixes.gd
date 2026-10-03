extends GutTest
## Low-severity QA fixes: SkinData number clamping, the list_skins cap, an opaque baked hull for a
## translucent picture, and AudioDirector staying silent on wrong-typed event fields.

const DIR: String = "user://test_low_fixes_skins"


func before_each() -> void:
	SkinStore.dir = DIR
	_wipe()
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	_wipe()
	SkinStore.dir = SkinStore.DEFAULT_DIR


## Only plain files directly inside DIR (the test never creates folders or links); nothing is followed.
func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + "/" + f)
	DirAccess.remove_absolute(DIR)


func _skin_file(id: String, name: String = "x") -> void:
	var f: FileAccess = FileAccess.open("%s/%s.json" % [DIR, id], FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "name": name, "body_style": 1}))
	f.close()


# --- SkinData._int_in ---------------------------------------------------------------------------

func test_huge_floats_clamp_to_the_matching_end() -> void:
	var up: SkinData = SkinData.from_dict({"body_style": 1e20, "pattern": 1e300, "decal": INF, "glow": 1e19}, "u")
	assert_eq([up.body_style, up.pattern, up.decal, up.glow], [3, 5, 9, 100])
	var down: SkinData = SkinData.from_dict({"body_style": -1e20, "pattern": -1e300, "decal": -INF, "glow": -1e19}, "d")
	assert_eq([down.body_style, down.pattern, down.decal, down.glow], [0, 0, 0, 0])


func test_nan_gives_the_default_and_ordinary_floats_still_round() -> void:
	var s: SkinData = SkinData.from_dict({"glow": NAN, "decal": NAN, "turret_style": 2.6, "body_style": 1.4}, "n")
	assert_eq(s.glow, 50)
	assert_eq(s.decal, 1)
	assert_eq(s.turret_style, 3)
	assert_eq(s.body_style, 1)


# --- SkinStore cap ------------------------------------------------------------------------------

func test_list_skins_returns_at_most_the_cap_oldest_first() -> void:
	for i: int in range(SkinStore.MAX_SKINS + 12):
		_skin_file("s%04d" % i)
	var all: Array[SkinData] = SkinStore.list_skins(false)
	assert_eq(all.size(), SkinStore.MAX_SKINS)
	assert_eq(all[0].id, "s0000")
	assert_eq(all[all.size() - 1].id, "s%04d" % (SkinStore.MAX_SKINS - 1))


func test_an_existing_skin_beyond_the_listed_ones_can_still_be_edited_at_the_cap() -> void:
	for i: int in range(SkinStore.MAX_SKINS + 3):
		_skin_file("s%04d" % i)
	var last: String = "s%04d" % (SkinStore.MAX_SKINS + 2)
	var s: SkinData = SkinStore.load_skin(last)
	assert_not_null(s)
	s.name = "edited"
	assert_true(SkinStore.save_skin(s))
	assert_eq(SkinStore.load_skin(last).name, "edited")
	assert_false(SkinStore.save_skin(SkinData.make_default("brand_new", "n")), "a new skin is still refused")


func test_unreadable_files_do_not_use_up_a_place() -> void:
	var f: FileAccess = FileAccess.open(DIR + "/a0000.json", FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	for i: int in range(SkinStore.MAX_SKINS):
		_skin_file("s%04d" % i)
	assert_eq(SkinStore.list_skins(false).size(), SkinStore.MAX_SKINS)


# --- SkinBaker ----------------------------------------------------------------------------------

func _opaque(img: Image) -> bool:
	for j: int in range(img.get_height()):
		for i: int in range(img.get_width()):
			if img.get_pixel(i, j).a < 0.999:
				return false
	return true


func test_a_translucent_picture_bakes_to_an_opaque_hull_that_still_shows_the_picture() -> void:
	var s: SkinData = SkinData.make_default("bake", "b")
	s.base = Color(0, 0, 0)
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(1.0, 1.0, 1.0, 0.5))
	var img: Image = SkinBaker.bake_image(s, 4)
	assert_true(_opaque(img))
	var mid: Color = img.get_pixel(48, 2)
	assert_gt(mid.r, 0.3, "the picture shows through")
	assert_lt(mid.r, 0.9, "over the dark base, not pure picture")


func test_a_fully_transparent_picture_leaves_the_base_colour() -> void:
	var s: SkinData = SkinData.make_default("bake", "b")
	s.image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	s.image.fill(Color(1, 1, 1, 0))
	var plain: Image = SkinBaker.bake_image(SkinData.make_default("p", "p"), 4)
	var img: Image = SkinBaker.bake_image(s, 4)
	assert_true(_opaque(img))
	assert_eq(img.get_pixel(10, 10), plain.get_pixel(10, 10))


# --- AudioDirector ------------------------------------------------------------------------------

func test_wrong_typed_event_fields_are_silent_not_errors() -> void:
	var ad: Variant = get_tree().root.get_node("AudioDirector")
	var junk: Array = [null, [], {}, 5, 1.5, true, "x", PackedStringArray(["a"]), Vector2(1, 2)]
	var fields: Dictionary = {"fire": "weapon", "explosion": "radius", "money": "reason"}
	for type: String in fields:
		for v: Variant in junk:
			if type != "explosion" and typeof(v) == TYPE_STRING:
				continue
			var e: Dictionary = {"type": type, fields[type]: v}
			if type == "explosion" and (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
				continue
			assert_eq(ad.sound_for_event(e), "", "%s with %s" % [type, str(v)])
	for e: Dictionary in [
			{"type": "money", "reason": "kill", "delta": [1]}, {"type": "tank_drag", "to_x": [], "from_x": null},
			{"type": "round_end", "winner": {}}, {"type": ["fire"]}, {"type": null},
			{"type": "damage", "cause": []}, {"type": "terrain_settle", "falls": {}}]:
		ad.sound_for_event(e)
		ad.on_event(e)
	assert_eq(ad.sound_for_event({"type": "money", "reason": "kill", "delta": 5}), "money_gain")
	assert_eq(ad.sound_for_event({"type": "explosion", "radius": 3}), "explosion_small")
