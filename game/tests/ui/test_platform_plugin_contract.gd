extends GutTest
## Keeps three things in step, so a rename on one side cannot silently break the other:
##   1. the Kotlin plugin sources (android_plugins/*/src/main/kotlin: @UsedByGodot methods, SignalInfo signals),
##   2. the GDScript fakes the tests use, and
##   3. the calls and signal connections of the GDScript wrappers (game/platform).
## It reads the Kotlin files from the repository checkout, so it cannot run from an exported package (tests are
## excluded from exports anyway); when the sources are not found the tests are marked pending, not failed.

const PLUGINS: Array[Dictionary] = [
	{"kotlin": "android_plugins/push/src/main/kotlin/com/wrynn7/craterline/plugin/push/CraterlinePush.kt",
		"fake": "res://platform/push_fake.gd", "wrapper": "res://platform/push_service.gd", "singleton": "CraterlinePush"},
	{"kotlin": "android_plugins/signin/src/main/kotlin/com/wrynn7/craterline/plugin/signin/CraterlineGoogleSignIn.kt",
		"fake": "res://platform/google_sign_in_fake.gd", "wrapper": "res://platform/google_sign_in.gd", "singleton": "CraterlineGoogleSignIn"},
	{"kotlin": "android_plugins/share/src/main/kotlin/com/wrynn7/craterline/plugin/share/CraterlineShare.kt",
		"fake": "res://platform/share_fake.gd", "wrapper": "res://platform/share_service.gd", "singleton": "CraterlineShare"},
]


func _read(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _kotlin(entry: Dictionary) -> String:
	var abs_path: String = ProjectSettings.globalize_path("res://").path_join("../" + str(entry["kotlin"])).simplify_path()
	return _read(abs_path)


## [{"name": String, "args": int}] for every `SignalInfo("name", Type::class.java, ...)`.
func _kotlin_signals(source: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rx: RegEx = RegEx.new()
	rx.compile('SignalInfo\\("([a-z_]+)"([^)]*)\\)')
	for m: RegExMatch in rx.search_all(source):
		out.append({"name": m.get_string(1), "args": m.get_string(2).count("::class.java")})
	return out


func _kotlin_methods(source: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var rx: RegEx = RegEx.new()
	rx.compile("@UsedByGodot\\s+fun\\s+([a-z_]+)\\(")
	for m: RegExMatch in rx.search_all(source):
		out.append(m.get_string(1))
	return out


func test_every_plugin_source_was_found() -> void:
	for entry: Dictionary in PLUGINS:
		var source: String = _kotlin(entry)
		if source == "":
			pending("Kotlin sources not available here: " + str(entry["kotlin"]))
			return
		assert_gt(_kotlin_methods(source).size(), 0, "%s exposes methods" % entry["singleton"])
		assert_gt(_kotlin_signals(source).size(), 0, "%s declares signals" % entry["singleton"])


func test_fakes_have_every_method_and_signal_of_the_plugins() -> void:
	for entry: Dictionary in PLUGINS:
		var source: String = _kotlin(entry)
		if source == "":
			pending("Kotlin sources not available")
			return
		var fake: RefCounted = (load(str(entry["fake"])) as GDScript).new()
		for method_name: String in _kotlin_methods(source):
			assert_true(fake.has_method(method_name), "%s: fake lacks method %s" % [entry["singleton"], method_name])
		for sig: Dictionary in _kotlin_signals(source):
			assert_true(fake.has_signal(str(sig["name"])), "%s: fake lacks signal %s" % [entry["singleton"], sig["name"]])
			for info: Dictionary in fake.get_signal_list():
				if info["name"] == sig["name"]:
					assert_eq((info["args"] as Array).size(), sig["args"], "%s.%s argument count" % [entry["singleton"], sig["name"]])


func test_wrappers_only_call_methods_and_signals_the_plugins_have() -> void:
	var call_rx: RegEx = RegEx.new()
	call_rx.compile('_bridge\\.call\\("([a-z_]+)"')
	var sig_rx: RegEx = RegEx.new()
	sig_rx.compile('_bridge\\.(?:connect|has_signal)\\("([a-z_]+)"')
	for entry: Dictionary in PLUGINS:
		var source: String = _kotlin(entry)
		if source == "":
			pending("Kotlin sources not available")
			return
		var methods: PackedStringArray = _kotlin_methods(source)
		var signal_names: PackedStringArray = PackedStringArray()
		for sig: Dictionary in _kotlin_signals(source):
			signal_names.append(str(sig["name"]))
		# DeepLinks shares the CraterlineShare singleton with ShareService, so check both wrappers against it.
		var wrappers: Array[String] = [str(entry["wrapper"])]
		if entry["singleton"] == "CraterlineShare":
			wrappers.append("res://platform/deep_links.gd")
		for wrapper: String in wrappers:
			var text: String = _read(wrapper)
			assert_ne(text, "", "wrapper readable: " + wrapper)
			for m: RegExMatch in call_rx.search_all(text):
				assert_true(methods.has(m.get_string(1)), "%s calls %s, which %s does not expose" % [wrapper, m.get_string(1), entry["singleton"]])
			for m: RegExMatch in sig_rx.search_all(text):
				assert_true(signal_names.has(m.get_string(1)), "%s uses signal %s, which %s does not emit" % [wrapper, m.get_string(1), entry["singleton"]])
