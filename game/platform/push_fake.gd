class_name PushFake
extends RefCounted
## Stands in for the CraterlinePush Android singleton in tests (and on desktop if a screen wants to be tried out).
## Same method and signal names as android_plugins/push/.../CraterlinePush.kt, plus `simulate_*` helpers.

signal token_changed(token: String)
signal token_error(message: String)
signal permission_result(granted: bool)
signal notification_opened(payload_json: String)

var available_flag: bool = true
var token_value: String = "fake-fcm-token-1"
## Whether the "system dialog" says yes when request_notification_permission() is called.
var permission_answer: bool = true
var permission_granted: bool = false
var channel_name: String = ""
var channel_description: String = ""
var refresh_count: int = 0
var permission_requests: int = 0
var _pending_json: String = ""


func is_available() -> bool:
	return available_flag


func refresh_token() -> void:
	refresh_count += 1
	if available_flag:
		token_changed.emit(token_value)
	else:
		token_error.emit("push unavailable")


func get_token() -> String:
	return token_value if available_flag else ""


func has_notification_permission() -> bool:
	return permission_granted


func request_notification_permission() -> void:
	permission_requests += 1
	permission_granted = permission_answer
	permission_result.emit(permission_granted)


func ensure_channel(name: String, description: String) -> void:
	channel_name = name
	channel_description = description


func consume_launch_payload() -> String:
	var json: String = _pending_json
	_pending_json = ""
	return json


## The game was started by tapping a notification (nobody is listening yet).
func simulate_launch_tap(payload: Dictionary) -> void:
	_pending_json = JSON.stringify(payload)


## A notification is tapped while the game is running.
func simulate_tap(payload: Dictionary) -> void:
	_pending_json = JSON.stringify(payload)
	notification_opened.emit(_pending_json)
