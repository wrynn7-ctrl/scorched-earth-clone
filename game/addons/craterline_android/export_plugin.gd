@tool
extends EditorPlugin
## Adds Charred Horizons' Android plugins to a Gradle export (Godot 4.7 "v2" plugin format, same shape as the vendored
## billing plugin). Editor-only: it is excluded from exported packages (exclude_filter in export_presets.cfg).
##
## What it adds, and when:
##   - the plugin AARs from bin/ (built by tools/plugins/build_plugins.sh); a missing AAR is skipped with a warning,
##     so exporting from the editor without building them still works (the GDScript wrappers then report "unavailable");
##   - the pinned Maven dependencies listed in bin/plugins.cfg (Credential Manager, googleid, and firebase-messaging
##     only when the push AAR was built WITH google-services.json);
##   - an <activity-alias> with the charredhorizons://join/CODE intent filter (the game's own activity is not exported).

var _export_plugin: CraterlineExportPlugin


func _enter_tree() -> void:
	_export_plugin = CraterlineExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class CraterlineExportPlugin extends EditorExportPlugin:
	const ADDON_NAME: String = "craterline_android"
	const BIN_DIR: String = "res://addons/craterline_android/bin"
	const PUSH: String = "CraterlinePush"
	const SIGN_IN: String = "CraterlineGoogleSignIn"
	const SHARE: String = "CraterlineShare"

	func _get_name() -> String:
		return "CraterlineAndroid"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var libs: PackedStringArray = PackedStringArray()
		for plugin_name: String in [PUSH, SIGN_IN, SHARE]:
			if _has_aar(plugin_name, debug):
				libs.append(_aar_path(plugin_name, debug))
			else:
				push_warning("CraterlineAndroid: %s is missing; the %s plugin is NOT added to this export. Run tools/plugins/build_plugins.sh." % [_aar_path(plugin_name, debug), plugin_name])
		return libs

	func _get_android_dependencies(_platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		var cfg: ConfigFile = ConfigFile.new()
		var deps: PackedStringArray = PackedStringArray()
		if cfg.load(BIN_DIR + "/plugins.cfg") != OK:
			return deps
		if _has_aar(SIGN_IN, debug):
			deps.append_array(_deps(cfg, "sign_in"))
		if _has_aar(PUSH, debug) and bool(cfg.get_value("build", "fcm", false)):
			deps.append_array(_deps(cfg, "fcm"))
		return deps

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, debug: bool) -> String:
		if not _has_aar(SHARE, debug):
			return ""
		# The game's activity is exported=false, so links go through an exported alias that targets it.
		return "\n".join([
			"<activity-alias android:name=\".CraterlineDeepLink\" android:targetActivity=\".GodotApp\" android:exported=\"true\">",
			"    <intent-filter>",
			"        <action android:name=\"android.intent.action.VIEW\" />",
			"        <category android:name=\"android.intent.category.DEFAULT\" />",
			"        <category android:name=\"android.intent.category.BROWSABLE\" />",
			"        <data android:scheme=\"charredhorizons\" android:host=\"join\" />",
			"    </intent-filter>",
			"</activity-alias>",
		])

	## Library paths are relative to res://addons/, like the billing plugin's.
	func _aar_path(plugin_name: String, debug: bool) -> String:
		var kind: String = "debug" if debug else "release"
		return "%s/bin/%s/%s-%s.aar" % [ADDON_NAME, kind, plugin_name, kind]

	func _has_aar(plugin_name: String, debug: bool) -> bool:
		return FileAccess.file_exists("res://addons/" + _aar_path(plugin_name, debug))

	func _deps(cfg: ConfigFile, key: String) -> PackedStringArray:
		var out: PackedStringArray = PackedStringArray()
		for dep: Variant in cfg.get_value("dependencies", key, []):
			out.append(str(dep))
		return out
