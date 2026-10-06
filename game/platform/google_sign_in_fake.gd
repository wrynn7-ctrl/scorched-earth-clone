class_name GoogleSignInFake
extends RefCounted
## Stands in for the CraterlineGoogleSignIn Android singleton in tests. Same method and signal names as
## android_plugins/signin/.../CraterlineGoogleSignIn.kt. `next_result` picks what the next sign_in() does:
## "success" or one of the plugin's failure codes ("cancelled", "no_credential", "unavailable", "network", "config",
## "bad_token", "error"); "hang" never answers (a sheet that stays open). It resets to "success" after one use.

signal sign_in_succeeded(id_token: String, email: String, display_name: String)
signal sign_in_failed(code: String, message: String)
signal sign_out_finished()

var available_flag: bool = true
var next_result: String = "success"
var fake_id_token: String = "fake.google.id-token"
var fake_email: String = "player@example.com"
var fake_display_name: String = "Player One"
var last_web_client_id: String = ""
var last_nonce: String = ""
var sign_in_calls: int = 0
var sign_out_calls: int = 0


func is_available() -> bool:
	return available_flag


func sign_in(web_client_id: String, nonce: String) -> void:
	sign_in_calls += 1
	last_web_client_id = web_client_id
	last_nonce = nonce
	var result: String = next_result
	next_result = "success"
	match result:
		"success":
			sign_in_succeeded.emit(fake_id_token, fake_email, fake_display_name)
		"hang":
			pass
		_:
			sign_in_failed.emit(result, "fake failure: " + result)


func sign_out() -> void:
	sign_out_calls += 1
	sign_out_finished.emit()
