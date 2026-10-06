extends GutTest
## Every script and scene of the online UI parses and loads (a typo in a rarely-used screen is caught here, not on a phone).

const DIRS: Array[String] = ["res://ui/online", "res://show/online"]


func _files(dir: String, out: Array[String]) -> void:
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return
	for f: String in da.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d: String in da.get_directories():
		_files(dir.path_join(d), out)


func test_all_online_scripts_and_scenes_load() -> void:
	var files: Array[String] = []
	for d: String in DIRS:
		_files(d, files)
	assert_gt(files.size(), 10, "found the online files")
	for path: String in files:
		var res: Resource = load(path)
		assert_not_null(res, path)
