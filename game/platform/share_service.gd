class_name ShareService
extends RefCounted
## The Android share sheet for "Join my Craterline match: CODE" (docs/ARCHITECTURE.md section 49), through the
## CraterlineShare plugin. On desktop, in tests and in builds without the plugin `available` is false and
## `share_or_copy` falls back to the clipboard, so the UI always has something sensible to do.
##
## The invite text is user-visible, so the caller passes a translated template (from tr()) that may contain
## {code} and {link}; this class never invents wording.

const SINGLETON: String = "CraterlineShare"

enum Result {
	SHARED,   ## the system share sheet was opened
	COPIED,   ## no share sheet; the text was put on the clipboard (tell the player)
	FAILED,   ## nothing could be done (empty text)
}

var available: bool = false
var _bridge: Object = null


func _init(bridge: Object = null) -> void:
	_bridge = bridge if bridge != null else _engine_bridge()
	available = _bridge != null


static func _engine_bridge() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


## Opens the share sheet. Returns false when it could not (no plugin, empty text).
func share_text(title: String, text: String) -> bool:
	if _bridge == null or text.strip_edges() == "":
		return false
	return _bridge.call("share_text", title, text) == true


## Share sheet when there is one, clipboard otherwise.
func share_or_copy(title: String, text: String) -> int:
	if text.strip_edges() == "":
		return Result.FAILED
	if share_text(title, text):
		return Result.SHARED
	DisplayServer.clipboard_set(text)
	return Result.COPIED


## Shares the invite for a match code. `template` is the translated text with {code} and {link}.
func share_invite(title: String, template: String, code: String) -> int:
	var text: String = invite_text(template, code)
	if text == "":
		return Result.FAILED
	return share_or_copy(title, text)


## Fills {code} and {link} in `template`. "" when `code` is not a valid match code.
static func invite_text(template: String, code: String) -> String:
	var normalized: String = DeepLinks.normalize_code(code)
	if normalized == "":
		return ""
	return template.replace("{code}", normalized).replace("{link}", DeepLinks.build_join_link(normalized))
