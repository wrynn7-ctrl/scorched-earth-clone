extends SceneTree
## Child-process probe for test_m5_free_full.gd (not a test file). Run with
##   godot --headless --path game -s res://tests/qa/qa_m5_entitlement_probe.gd -- <cache file>...
## For every cache file it behaves like a fresh release-build launch and prints
##   PROBE|<file>|<is_full>|<is_debug_full>
## It runs in its own process because ConfigFile prints an engine "parse error" line for a damaged
## cache, which must not appear in the test runner's output (the runner treats it as a script error).


func _init() -> void:
	for path: String in OS.get_cmdline_user_args():
		Entitlement.forget_for_tests()
		Entitlement.cache_path = path
		Entitlement.persist_headless = true
		Entitlement.debug_build_override = 0
		var full: bool = Entitlement.is_full()
		var dbg: bool = Entitlement.is_debug_full()
		print("PROBE|%s|%s|%s" % [path, str(full), str(dbg)])
	Entitlement.forget_for_tests()
	quit(0)
