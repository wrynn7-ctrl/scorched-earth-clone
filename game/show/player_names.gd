class_name PlayerNames
extends RefCounted
## The names the players typed on the setup screen, one per slot (ARCHITECTURE section 42). Like
## PlayerLooks this is presentation only: the simulation never sees a name, so it cannot affect
## fingerprints or saves. It travels in the autosave's `meta` ("names") instead, and a save without
## that key (or with a damaged one) simply shows PLAYER n.
##
## Every screen that labels a player asks `label(i)`; nothing else builds "PLAYER n" any more.
## A computer player never has a name, so it stays "PLAYER n" (with its level beside it where shown).

static var _names: PackedStringArray = PackedStringArray()


static func reset() -> void:
	_names = PackedStringArray()


## `names[i]` belongs to slot i. Each entry is cleaned again, so nothing unchecked gets in.
static func set_names(names: PackedStringArray) -> void:
	_names = PackedStringArray()
	for raw: String in names:
		_names.append(sanitize(raw))


## What a typed name becomes: cleaned, in capitals (the game shows names that way) and still within
## the length cap. "" when nothing usable is left or the name is blocked (the caller shows PLAYER n).
static func sanitize(raw: String) -> String:
	var cleaned: String = NameFilter.clean(raw).to_upper().substr(0, NameFilter.MAX_LENGTH).strip_edges()
	if cleaned == "" or not NameFilter.is_allowed(cleaned):
		return ""
	return cleaned


static func has_custom(player: int) -> bool:
	return player >= 0 and player < _names.size() and _names[player] != ""


## The name typed for slot `player`, or "".
static func typed(player: int) -> String:
	return _names[player] if has_custom(player) else ""


## The label to show for a player: the name, or "PLAYER n" (translated).
static func label(player: int) -> String:
	if has_custom(player):
		return _names[player]
	return TranslationServer.translate("HUD_PLAYER_N") % (player + 1)


## For the autosave meta.
static func to_array(count: int) -> Array:
	var out: Array = []
	for i: int in range(count):
		out.append(typed(i))
	return out


## Restores from `to_array` output. Anything missing or malformed means no names.
static func from_array(saved: Variant) -> void:
	reset()
	if typeof(saved) != TYPE_ARRAY:
		return
	var names: PackedStringArray = PackedStringArray()
	for v: Variant in saved as Array:
		names.append(str(v) if typeof(v) == TYPE_STRING else "")
	set_names(names)
