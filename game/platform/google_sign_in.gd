class_name GoogleSignIn
extends RefCounted
## Sign in with Google (Android Credential Manager) through the CraterlineGoogleSignIn plugin. It only produces a Google
## ID token; sending it to Firebase (Identity Toolkit signInWithIdp, to link the anonymous account) is the net layer's job.
##
## The web client id is the OAuth *web application* client of the Firebase project (docs/FIREBASE_SETUP.md); it comes
## from game configuration, never from this class. `available` is false on desktop, in tests and without Google Play
## services, and then `sign_in` reports UNAVAILABLE instead of doing anything.

const SINGLETON: String = "CraterlineGoogleSignIn"

## Why a sign-in did not produce a token. Codes come from the plugin (see CraterlineGoogleSignIn.kt).
enum Error {
	NONE,
	CANCELLED,    ## the player closed the Google sheet: not an error to show
	NO_ACCOUNT,   ## no Google account on the device
	UNAVAILABLE,  ## no plugin or no Google Play services
	NETWORK,
	CONFIG,       ## web client id missing or wrong, or the app's SHA-1 is not registered in Firebase
	BAD_TOKEN,    ## Google answered, but not with a usable ID token
	BUSY,         ## a sign-in is already running
	ERROR,
}

signal succeeded(id_token: String, email: String, display_name: String)
signal failed(error: int, detail: String)
signal signed_out()

var available: bool = false
var busy: bool = false
var _bridge: Object = null


func _init(bridge: Object = null) -> void:
	_bridge = bridge if bridge != null else _engine_bridge()
	if _bridge != null:
		if _bridge.has_signal("sign_in_succeeded"):
			_bridge.connect("sign_in_succeeded", _on_succeeded)
		if _bridge.has_signal("sign_in_failed"):
			_bridge.connect("sign_in_failed", _on_failed)
		if _bridge.has_signal("sign_out_finished"):
			_bridge.connect("sign_out_finished", _on_signed_out)


static func _engine_bridge() -> Object:
	if Engine.has_singleton(SINGLETON):
		return Engine.get_singleton(SINGLETON)
	return null


## Call once at startup (cheap); sets `available`.
func start() -> void:
	available = _bridge != null and _bridge.call("is_available") == true


## Starts the Google sign-in sheet. The result arrives as `succeeded` or `failed`. Returns false when it could not
## start (then `failed` has already been emitted, with the reason).
func sign_in(web_client_id: String, nonce: String = "") -> bool:
	if busy:
		failed.emit(Error.BUSY, "a sign-in is already running")
		return false
	if _bridge == null or not available:
		failed.emit(Error.UNAVAILABLE, "Google sign-in is not available on this device")
		return false
	if web_client_id.strip_edges() == "":
		failed.emit(Error.CONFIG, "no web client id configured")
		return false
	busy = true
	_bridge.call("sign_in", web_client_id.strip_edges(), nonce)
	return true


## Forgets the chosen Google account on the device (the next sign-in shows the chooser again).
func sign_out() -> void:
	if _bridge == null or not available:
		signed_out.emit()
		return
	_bridge.call("sign_out")


## Maps a plugin failure code to an Error.
static func error_from_code(code: String) -> int:
	match code:
		"cancelled":
			return Error.CANCELLED
		"no_credential":
			return Error.NO_ACCOUNT
		"unavailable":
			return Error.UNAVAILABLE
		"network":
			return Error.NETWORK
		"config":
			return Error.CONFIG
		"bad_token":
			return Error.BAD_TOKEN
	return Error.ERROR


func _on_succeeded(id_token: String, email: String, display_name: String) -> void:
	busy = false
	if id_token.strip_edges() == "":
		failed.emit(Error.BAD_TOKEN, "empty ID token")
		return
	succeeded.emit(id_token, email, display_name)


func _on_failed(code: String, message: String) -> void:
	busy = false
	failed.emit(error_from_code(code), message)


func _on_signed_out() -> void:
	signed_out.emit()
