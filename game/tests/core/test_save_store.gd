extends GutTest
## game/platform/save_store.gd: atomic autosave file IO under user://.

const U = preload("res://tests/core/sim_test_util.gd")
const PATH: String = "user://test_autosave.crtl"


func before_each() -> void:
	SaveStore.delete(PATH)


func after_all() -> void:
	SaveStore.delete(PATH)


func _state(seed_value: int) -> MatchState:
	var s: MatchState = U.shop_state(2, 3, seed_value)
	Simulation.apply_action(s, U.buy(0, "glow_shield", 1))
	U.begin_round(s)
	return s


func test_default_path() -> void:
	assert_eq(SaveStore.AUTOSAVE_PATH, "user://autosave.crtl")


func test_no_file_means_no_valid_save() -> void:
	assert_false(SaveStore.has_valid_save(PATH))
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_false(res["ok"])
	assert_eq(res["error"], "no_file")
	assert_null(res["state"])
	assert_eq(SaveStore.read_bytes(PATH).size(), 0)


func test_write_then_read_back() -> void:
	var s: MatchState = _state(11)
	var actions: Array[Dictionary] = [U.buy(0, "glow_shield", 1), U.ready(0), U.fire(0, 450, 500)]
	assert_true(SaveStore.save(s, actions, PATH))
	assert_true(FileAccess.file_exists(PATH))
	assert_true(SaveStore.has_valid_save(PATH))
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_true(res["ok"], str(res["error"]))
	assert_eq(Simulation.fingerprint(res["state"]), Simulation.fingerprint(s))
	assert_eq(res["actions"], actions)
	assert_eq(SaveStore.read_bytes(PATH), SaveCodec.encode(s, actions), "the file is exactly the codec output")


func test_the_atomic_temp_file_is_cleaned_up() -> void:
	var s: MatchState = _state(12)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], PATH))
	assert_false(FileAccess.file_exists(PATH + SaveStore.TMP_SUFFIX), "temp file renamed away")
	assert_true(SaveStore.save(s, [] as Array[Dictionary], PATH), "overwriting an existing save works")
	assert_false(FileAccess.file_exists(PATH + SaveStore.TMP_SUFFIX))
	var dir: DirAccess = DirAccess.open("user://")
	var leftovers: int = 0
	for f: String in dir.get_files():
		if f.begins_with("test_autosave") and f.ends_with(".tmp"):
			leftovers += 1
	assert_eq(leftovers, 0)


func test_overwrite_replaces_the_previous_save() -> void:
	var a: MatchState = _state(21)
	var b: MatchState = _state(22)
	SaveStore.save(a, [] as Array[Dictionary], PATH)
	SaveStore.save(b, [] as Array[Dictionary], PATH)
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_eq(Simulation.fingerprint(res["state"]), Simulation.fingerprint(b))
	assert_ne(Simulation.fingerprint(a), Simulation.fingerprint(b))


func test_a_stale_temp_file_does_not_break_saving_or_loading() -> void:
	var s: MatchState = _state(31)
	var f: FileAccess = FileAccess.open(PATH + SaveStore.TMP_SUFFIX, FileAccess.WRITE)
	f.store_string("half written garbage")
	f.close()
	assert_false(SaveStore.has_valid_save(PATH), "a temp file alone is not a save")
	assert_true(SaveStore.save(s, [] as Array[Dictionary], PATH))
	assert_true(SaveStore.has_valid_save(PATH))
	assert_false(FileAccess.file_exists(PATH + SaveStore.TMP_SUFFIX))


func test_a_failed_write_keeps_the_previous_save() -> void:
	var s: MatchState = _state(41)
	assert_true(SaveStore.save(s, [] as Array[Dictionary], PATH))
	var before: PackedByteArray = SaveStore.read_bytes(PATH)
	# a directory that does not exist: the temp file cannot be created
	assert_false(SaveStore.write_bytes(PackedByteArray([1, 2, 3]), "user://no_such_dir_xyz/save.crtl"))
	assert_eq(SaveStore.read_bytes(PATH), before)
	assert_true(SaveStore.has_valid_save(PATH))


func test_corrupt_file_is_not_a_valid_save() -> void:
	var s: MatchState = _state(51)
	SaveStore.save(s, [] as Array[Dictionary], PATH)
	var bytes: PackedByteArray = SaveStore.read_bytes(PATH)
	bytes[bytes.size() / 2] = bytes[bytes.size() / 2] ^ 0xFF
	assert_true(SaveStore.write_bytes(bytes, PATH))
	assert_false(SaveStore.has_valid_save(PATH))
	var res: Dictionary = SaveStore.load_save(PATH)
	assert_false(res["ok"])
	assert_eq(res["error"], "corrupt")
	assert_true(SaveStore.write_bytes("not a save at all, definitely".to_ascii_buffer(), PATH))
	assert_false(SaveStore.has_valid_save(PATH))


func test_delete() -> void:
	var s: MatchState = _state(61)
	SaveStore.save(s, [] as Array[Dictionary], PATH)
	assert_true(SaveStore.delete(PATH))
	assert_false(FileAccess.file_exists(PATH))
	assert_false(SaveStore.has_valid_save(PATH))
	assert_true(SaveStore.delete(PATH), "deleting nothing is fine")
	var f: FileAccess = FileAccess.open(PATH + SaveStore.TMP_SUFFIX, FileAccess.WRITE)
	f.store_8(1)
	f.close()
	SaveStore.delete(PATH)
	assert_false(FileAccess.file_exists(PATH + SaveStore.TMP_SUFFIX), "delete also removes a stray temp file")


func test_empty_file_is_not_valid() -> void:
	assert_true(SaveStore.write_bytes(PackedByteArray(), PATH))
	assert_false(SaveStore.has_valid_save(PATH))
