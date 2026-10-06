extends GutTest
## GoogleSignIn wrapper with GoogleSignInFake: success, every failure code, busy handling, config errors, desktop.

const WEB_ID: String = "123-abc.apps.googleusercontent.com"

var _ok: Array[String] = []
var _errors: Array[int] = []


func before_each() -> void:
	_ok.clear()
	_errors.clear()


func _wire(g: GoogleSignIn) -> void:
	g.succeeded.connect(func(token: String, email: String, display_name: String) -> void:
		_ok.append("%s|%s|%s" % [token, email, display_name]))
	g.failed.connect(func(error: int, _detail: String) -> void: _errors.append(error))


func test_desktop_is_unavailable_and_never_throws() -> void:
	var g: GoogleSignIn = GoogleSignIn.new()
	_wire(g)
	g.start()
	assert_false(g.available)
	assert_false(g.sign_in(WEB_ID))
	assert_eq(_errors, [GoogleSignIn.Error.UNAVAILABLE] as Array[int])
	watch_signals(g)
	g.sign_out()
	assert_signal_emitted(g, "signed_out", "sign_out still completes")


func test_success_returns_the_token() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	assert_true(g.available)
	assert_true(g.sign_in(WEB_ID, "nonce-1"))
	assert_eq(_ok, ["fake.google.id-token|player@example.com|Player One"] as Array[String])
	assert_eq(fake.last_web_client_id, WEB_ID)
	assert_eq(fake.last_nonce, "nonce-1")
	assert_false(g.busy, "not busy after the answer")


func test_each_failure_code_maps_to_a_typed_error() -> void:
	var cases: Dictionary = {
		"cancelled": GoogleSignIn.Error.CANCELLED,
		"no_credential": GoogleSignIn.Error.NO_ACCOUNT,
		"unavailable": GoogleSignIn.Error.UNAVAILABLE,
		"network": GoogleSignIn.Error.NETWORK,
		"config": GoogleSignIn.Error.CONFIG,
		"bad_token": GoogleSignIn.Error.BAD_TOKEN,
		"error": GoogleSignIn.Error.ERROR,
		"something-new": GoogleSignIn.Error.ERROR,
	}
	for code: String in cases.keys():
		var fake: GoogleSignInFake = GoogleSignInFake.new()
		var g: GoogleSignIn = GoogleSignIn.new(fake)
		var seen: Array[int] = []
		g.failed.connect(func(error: int, _detail: String) -> void: seen.append(error))
		g.start()
		fake.next_result = code
		g.sign_in(WEB_ID)
		assert_eq(seen, [cases[code]] as Array[int], code)
		assert_false(g.busy, "a failure frees the wrapper: %s" % code)


func test_cancel_can_be_retried() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	fake.next_result = "cancelled"
	g.sign_in(WEB_ID)
	g.sign_in(WEB_ID)
	assert_eq(_errors, [GoogleSignIn.Error.CANCELLED] as Array[int])
	assert_eq(_ok.size(), 1)


func test_second_sign_in_while_busy_is_refused() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	fake.next_result = "hang"
	assert_true(g.sign_in(WEB_ID))
	assert_true(g.busy)
	assert_false(g.sign_in(WEB_ID))
	assert_eq(_errors, [GoogleSignIn.Error.BUSY] as Array[int])
	assert_eq(fake.sign_in_calls, 1, "the plugin was only asked once")


func test_missing_web_client_id_is_a_config_error_without_calling_the_plugin() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	assert_false(g.sign_in(""))
	assert_false(g.sign_in("   "))
	assert_eq(_errors, [GoogleSignIn.Error.CONFIG, GoogleSignIn.Error.CONFIG] as Array[int])
	assert_eq(fake.sign_in_calls, 0)
	assert_false(g.busy)


func test_empty_token_from_the_plugin_is_bad_token() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	fake.fake_id_token = ""
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	g.sign_in(WEB_ID)
	assert_eq(_errors, [GoogleSignIn.Error.BAD_TOKEN] as Array[int])
	assert_eq(_ok.size(), 0)


func test_unavailable_device() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	fake.available_flag = false
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	_wire(g)
	g.start()
	assert_false(g.available)
	assert_false(g.sign_in(WEB_ID))
	assert_eq(_errors, [GoogleSignIn.Error.UNAVAILABLE] as Array[int])
	assert_eq(fake.sign_in_calls, 0)


func test_sign_out_goes_to_the_plugin() -> void:
	var fake: GoogleSignInFake = GoogleSignInFake.new()
	var g: GoogleSignIn = GoogleSignIn.new(fake)
	g.start()
	watch_signals(g)
	g.sign_out()
	assert_eq(fake.sign_out_calls, 1)
	assert_signal_emitted(g, "signed_out")
