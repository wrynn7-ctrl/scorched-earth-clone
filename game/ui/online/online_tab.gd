class_name OnlineTab
extends VBoxContainer
## Base of the four pages of the Online home (matches, friends, join, host). A page holds the session, builds its own
## widgets and reports what the player wants through signals; the Online screen decides what that means (open a
## match, show a menu, ask a question), so every page can be tested on its own with a fake session.

## A short message for the screen's toast ("Code copied").
signal toast(text: String)
signal open_match(match_id: String)
signal open_lobby(match_id: String)
## The player tapped a name: {uid, name, friend, in_match}. The screen opens the player menu.
signal player_menu(info: Dictionary)
## Ask a yes/no question; `on_yes` runs when the player confirms.
signal confirm(text: String, on_yes: Callable)
## A locked option was tapped: the screen opens the Unlock screen with this reason ("host").
signal unlock(kind: String)
## The backend says the game version differs ("Please update the game").
signal update_needed()
## Something changed that the tab button should show (a count).
signal badge_changed(count: int)

var net: NetSession = null
var _active: bool = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func setup(session: NetSession) -> void:
	net = session


## The page became visible: refresh what it shows and start watching.
func activate() -> void:
	_active = true


func deactivate() -> void:
	_active = false


func is_active() -> bool:
	return _active


## Re-applies the dp sizes (the screen calls it on every layout change).
func apply_scale() -> void:
	OnlineKit.apply(self)
	add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))


## Whether a failed call means "update the game"; tells the screen and returns true.
func check_update(r: NetResult) -> bool:
	if r.is_code(NetError.Code.PROTOCOL_MISMATCH):
		update_needed.emit()
		return true
	return false
