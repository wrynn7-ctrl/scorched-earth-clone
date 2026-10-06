extends GutTest
## PushService with PushFake: availability, token changes, the permission flow, notification taps (cold and warm
## start, delivered exactly once), payload parsing, and the desktop no-op behaviour.

var _tokens: Array[String] = []
var _taps: Array[Dictionary] = []


func before_each() -> void:
	_tokens.clear()
	_taps.clear()


func _wire(p: PushService) -> void:
	p.token_changed.connect(func(t: String) -> void: _tokens.append(t))
	p.notification_opened.connect(func(payload: Dictionary) -> void: _taps.append(payload))


func test_desktop_is_unavailable_and_every_call_is_harmless() -> void:
	var p: PushService = PushService.new()
	_wire(p)
	watch_signals(p)
	p.start()
	p.refresh_token()
	p.poll()
	p.ensure_channel("Turns", "desc")
	assert_false(p.available)
	assert_false(p.has_permission())
	assert_eq(p.token, "")
	assert_eq(p.take_pending_payload(), {})
	p.request_permission()
	assert_signal_emitted_with_parameters(p, "permission_result", [false])
	assert_eq(_tokens.size(), 0)


func test_unavailable_plugin_stays_quiet() -> void:
	var fake: PushFake = PushFake.new()
	fake.available_flag = false
	var p: PushService = PushService.new(fake)
	p.start()
	assert_false(p.available)
	assert_eq(fake.refresh_count, 0, "FCM is never asked when push is unavailable")
	p.refresh_token()
	assert_eq(fake.refresh_count, 0)


func test_start_fetches_the_token() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	assert_true(p.available)
	assert_eq(p.token, "fake-fcm-token-1")
	assert_eq(_tokens, ["fake-fcm-token-1"] as Array[String])


func test_token_signal_only_fires_when_it_changes() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	p.refresh_token()
	assert_eq(_tokens.size(), 1, "same token twice: one signal")
	fake.token_value = "rotated-token"
	p.refresh_token()
	assert_eq(_tokens, ["fake-fcm-token-1", "rotated-token"] as Array[String])
	assert_eq(p.token, "rotated-token")


func test_empty_token_is_ignored() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	fake.token_changed.emit("")
	assert_eq(p.token, "fake-fcm-token-1")
	assert_eq(_tokens.size(), 1)


func test_token_failure_is_reported() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	watch_signals(p)
	p.start()
	fake.token_error.emit("SERVICE_NOT_AVAILABLE")
	assert_signal_emitted_with_parameters(p, "token_failed", ["SERVICE_NOT_AVAILABLE"])


func test_permission_flow() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	watch_signals(p)
	p.start()
	assert_false(p.has_permission())
	p.request_permission()
	assert_signal_emitted_with_parameters(p, "permission_result", [true])
	assert_true(p.has_permission())
	assert_eq(fake.permission_requests, 1)


func test_permission_denied() -> void:
	var fake: PushFake = PushFake.new()
	fake.permission_answer = false
	var p: PushService = PushService.new(fake)
	watch_signals(p)
	p.start()
	p.request_permission()
	assert_signal_emitted_with_parameters(p, "permission_result", [false])
	assert_false(p.has_permission())


func test_channel_names_reach_the_plugin() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	p.start()
	p.ensure_channel("Tur", "Dein Zug")
	assert_eq(fake.channel_name, "Tur")
	assert_eq(fake.channel_description, "Dein Zug")


func test_cold_start_tap_waits_for_a_handler() -> void:
	var fake: PushFake = PushFake.new()
	fake.simulate_launch_tap({"matchId": "-Nabc123_x", "type": "turn"})
	var p: PushService = PushService.new(fake)
	p.start()
	assert_true(p.has_pending())
	var payload: Dictionary = p.take_pending_payload()
	assert_eq(payload.get("matchId"), "-Nabc123_x")
	assert_eq(payload.get("type"), "turn")
	assert_eq(p.take_pending_payload(), {}, "delivered once")
	assert_eq(fake.consume_launch_payload(), "", "the plugin's copy was consumed")


func test_warm_start_tap_is_emitted_once() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	fake.simulate_tap({"matchId": "m1"})
	assert_eq(_taps.size(), 1)
	assert_eq(PushService.match_id_of(_taps[0]), "m1")
	assert_false(p.has_pending())
	p.poll()
	assert_eq(_taps.size(), 1, "polling does not deliver it again")


func test_tap_without_a_handler_is_kept() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	p.start()
	fake.simulate_tap({"matchId": "m2"})
	assert_eq(PushService.match_id_of(p.take_pending_payload()), "m2")


func test_poll_picks_up_a_tap_kept_while_paused() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	fake.simulate_launch_tap({"matchId": "m3"})
	p.poll()
	assert_eq(_taps.size(), 1)


func test_garbage_payloads_are_dropped() -> void:
	var fake: PushFake = PushFake.new()
	var p: PushService = PushService.new(fake)
	_wire(p)
	p.start()
	fake.notification_opened.emit("not json")
	fake.notification_opened.emit("[1,2,3]")
	fake.notification_opened.emit("{}")
	fake.notification_opened.emit("")
	assert_eq(_taps.size(), 0)
	assert_false(p.has_pending())


# --- pure helpers ---------------------------------------------------------------------------

func test_parse_payload() -> void:
	assert_eq(PushService.parse_payload('{"matchId":"abc","n":3,"ok":true}'), {"matchId": "abc", "n": "3", "ok": "true"})
	assert_eq(PushService.parse_payload(""), {})
	assert_eq(PushService.parse_payload("nope"), {})
	assert_eq(PushService.parse_payload('["a"]'), {})
	assert_eq(PushService.parse_payload('{"a":{"b":1},"c":[1],"d":null,"e":"x"}'), {"e": "x"}, "nested values are dropped")


func test_match_id_of_accepts_push_ids_only() -> void:
	assert_eq(PushService.match_id_of({"matchId": "-OabcDEF123_xyz-9"}), "-OabcDEF123_xyz-9")
	assert_eq(PushService.match_id_of({}), "")
	assert_eq(PushService.match_id_of({"matchId": ""}), "")
	assert_eq(PushService.match_id_of({"matchId": 5}), "")
	assert_eq(PushService.match_id_of({"matchId": "../../etc"}), "", "path characters are refused")
	assert_eq(PushService.match_id_of({"matchId": "a b"}), "")
	assert_eq(PushService.match_id_of({"matchId": "x".repeat(65)}), "", "too long")
