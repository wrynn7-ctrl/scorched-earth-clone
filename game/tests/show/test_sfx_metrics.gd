extends GutTest
## The generated sound files against the objective rules of docs/ARCHITECTURE.md section 33a: tools/sfx/check_sfx.py
## measures peak, RMS, duration, the low-end and 100-300 Hz shares, flatness and loop seams of every WAV, and
## tools/sfx/test_gen_sfx.py checks the generator. Both are plain Python (standard library); the tests are
## skipped (pending) where python3 is not installed.

func _python() -> String:
	for exe: String in ["python3", "python"]:
		var out: Array = []
		if OS.execute(exe, ["--version"], out, true) == 0:
			return exe
	return ""


func _tools_path(file: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tools/sfx/" + file).simplify_path()


func test_the_sound_files_pass_the_objective_checks() -> void:
	var py: String = _python()
	if py == "":
		pending("python3 is not installed")
		return
	var out: Array = []
	var code: int = OS.execute(py, [_tools_path("check_sfx.py"), "--no-table"], out, true)
	var text: String = "\n".join(PackedStringArray(out))
	assert_eq(code, 0, "check_sfx.py failed:\n" + text)
	assert_true(text.contains("check_sfx: OK"), text)


func test_the_generator_unit_tests_pass() -> void:
	var py: String = _python()
	if py == "":
		pending("python3 is not installed")
		return
	var out: Array = []
	var code: int = OS.execute(py, [_tools_path("test_gen_sfx.py")], out, true)
	assert_eq(code, 0, "test_gen_sfx.py failed:\n" + "\n".join(PackedStringArray(out)))
