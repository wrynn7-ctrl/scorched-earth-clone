class_name ErrorText
extends RefCounted
## Player-facing text for a simulation error key (e.g. "no_fuel" -> ERR_NO_FUEL).
##
## `bad_phase` is shown for any action sent in the wrong phase (fire, move, items, shop), so
## it gets the general wording instead of the old fire-only ERR_BAD_PHASE.


static func message(err: String) -> String:
	if err == "bad_phase":
		return TranslationServer.translate(&"ERR_BAD_PHASE_M3")
	return TranslationServer.translate(StringName("ERR_" + err.to_upper()))
