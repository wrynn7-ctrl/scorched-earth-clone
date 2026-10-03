class_name CpuNames
extends RefCounted
## Display names of the controller levels (SimConstants.CTRL_*), shared by the setup screen, the
## turn banner and the round summary. Static, so translation goes through the server.

const LEVEL_KEYS: Array[String] = ["", "CPU_LEVEL_EASY", "CPU_LEVEL_NORMAL", "CPU_LEVEL_HARD", "CPU_LEVEL_EXPERT"]


## "EASY" .. "EXPERT" ("" for a human).
static func level_word(level: int) -> String:
	if level <= SimConstants.CTRL_HUMAN:
		return ""
	return TranslationServer.translate(LEVEL_KEYS[clampi(level, 1, SimConstants.CTRL_MAX)])


## "HUMAN" or "CPU NORMAL".
static func full_name(level: int) -> String:
	if level <= SimConstants.CTRL_HUMAN:
		return TranslationServer.translate("SETUP_PICK_HUMAN")
	return TranslationServer.translate("SETUP_PICK_CPU_FMT") % level_word(level)
