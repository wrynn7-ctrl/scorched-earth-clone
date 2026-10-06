extends GutTest
## Net client pieces that need no emulator: JSON ints, config, error mapping, NetHttp retry rules with a fake transport,
## NetFunctions answers, NetAuth with a fake backend, the SSE parser and its cache, and the list helpers.


# --- NetJson -----------------------------------------------------------------------------------------------------------

func test_json_whole_floats_become_ints() -> void:
	var v: Variant = NetJson.parse('{"a": 5, "b": [1, 2.5, {"c": 1700000000000}], "d": "x", "e": null}')
	var d: Dictionary = v as Dictionary
	assert_eq(typeof(d["a"]), TYPE_INT)
	assert_eq((d["b"] as Array)[0], 1)
	assert_eq(typeof((d["b"] as Array)[0]), TYPE_INT)
	assert_eq(typeof((d["b"] as Array)[1]), TYPE_FLOAT)
	assert_eq((((d["b"] as Array)[2]) as Dictionary)["c"], 1700000000000)
	assert_null(NetJson.parse(""))
	assert_false(NetJson.try_parse("{bad")["ok"])


func test_json_indexed_and_lists() -> void:
	assert_eq(NetJson.indexed(["a", null, "c"]), {0: "a", 2: "c"})
	assert_eq(NetJson.indexed({"0": "a", "10": "b", "x": "no"}), {0: "a", 10: "b"})
	assert_eq(NetJson.as_list({"1": "b", "0": "a"}), ["a", "b"])
	assert_eq(NetJson.as_list(null), [])


# --- NetConfig / NetError / NetResult --------------------------------------------------------------------------------------

func test_config_defaults_to_the_emulator_ports_of_firebase_json() -> void:
	var c: NetConfig = NetConfig.emulator()
	assert_eq(c.database_url, "http://127.0.0.1:9000")
	assert_eq(c.identity_url, "http://127.0.0.1:9099/identitytoolkit.googleapis.com")
	assert_eq(c.callable_url("joinMatch"), "http://127.0.0.1:5001/demo-craterline/europe-west1/joinMatch")
	assert_eq(c.database_namespace, "demo-craterline-default-rtdb")
	assert_true(c.is_configured())
	assert_false(c.production)
	var fb: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../firebase/firebase.json")) as Dictionary
	var emu: Dictionary = fb["emulators"] as Dictionary
	assert_eq(int((emu["auth"] as Dictionary)["port"]), NetConfig.PORT_AUTH)
	assert_eq(int((emu["database"] as Dictionary)["port"]), NetConfig.PORT_DATABASE)
	assert_eq(int((emu["functions"] as Dictionary)["port"]), NetConfig.PORT_FUNCTIONS)


func test_production_is_unconfigured_until_the_owner_fills_it_in() -> void:
	var p: NetConfig = NetConfig.production_config()
	assert_true(p.production)
	assert_eq(p.database_namespace, "")
	assert_true(p.identity_url.begins_with("https://"))
	if NetConfig.PRODUCTION_PROJECT_ID == "":
		assert_false(p.is_configured())
	assert_ne(p.endpoint_key(), NetConfig.emulator().endpoint_key())
	assert_false(NetConfig.USE_PRODUCTION, "the shipped default is the emulator until the lead flips the build switch")


func test_error_mapping() -> void:
	assert_eq(NetError.from_function_status("NOT_FOUND", "unknown_code"), NetError.Code.NOT_FOUND)
	assert_eq(NetError.from_function_status("FAILED_PRECONDITION", "protocol_mismatch"), NetError.Code.PROTOCOL_MISMATCH)
	assert_eq(NetError.from_function_status("PERMISSION_DENIED", "full_required"), NetError.Code.PERMISSION)
	assert_eq(NetError.from_function_status("RESOURCE_EXHAUSTED", "match_full"), NetError.Code.EXHAUSTED)
	assert_eq(NetError.from_function_status("UNAUTHENTICATED", ""), NetError.Code.SIGN_IN_REQUIRED)
	assert_eq(NetError.from_function_status("INTERNAL", ""), NetError.Code.SERVER)
	assert_eq(NetError.from_http_status(401, "Permission denied"), NetError.Code.PERMISSION)
	assert_eq(NetError.from_http_status(401, "Auth token is expired"), NetError.Code.SIGN_IN_REQUIRED)
	assert_eq(NetError.from_http_status(503, ""), NetError.Code.SERVER)
	assert_eq(NetError.name_of(NetError.Code.OFFLINE), "OFFLINE")
	assert_true(NetResult.failure(NetError.Code.TIMEOUT).is_transient())
	assert_false(NetResult.failure(NetError.Code.PERMISSION).is_transient())


# --- NetHttp -----------------------------------------------------------------------------------------------------------

## A transport that plays back `script` (one entry per attempt) and records the requests.
class FakeTransport:
	var plan: Array = []
	var seen: Array = []

	func send(method: int, url: String, _headers: PackedStringArray, body: String, _timeout: float) -> Dictionary:
		seen.append({"method": method, "url": url, "body": body})
		var step: Dictionary = plan.pop_front() if not plan.is_empty() else {"result": 0, "code": 200, "body": "null"}
		return {"result": step.get("result", HTTPRequest.RESULT_SUCCESS), "code": step.get("code", 200),
				"headers": PackedStringArray(), "body": (step.get("body", "null") as String).to_utf8_buffer()}


func _http(script: Array) -> Array:
	var t := FakeTransport.new()
	t.plan = script
	var h := NetHttp.new()
	h.backoff_ms = 1
	h.transport = Callable(t, "send")
	return [h, t]


func test_http_parses_json_and_maps_status_codes() -> void:
	var pair: Array = _http([{"code": 200, "body": '{"a": 1}'}, {"code": 401, "body": '{"error": "Permission denied"}'},
			{"code": 404, "body": "not json"}, {"code": 400, "body": '{"error": {"message": "BAD_THING"}}'}, {"code": 500, "body": ""}])
	var h: NetHttp = pair[0]
	var ok: NetResult = await h.request(HTTPClient.METHOD_GET, "http://x/a")
	assert_true(ok.ok)
	assert_eq(ok.dict(), {"a": 1})
	var denied: NetResult = await h.request(HTTPClient.METHOD_GET, "http://x/b")
	assert_true(denied.is_code(NetError.Code.PERMISSION))
	assert_eq(denied.reason, "Permission denied")
	assert_true((await h.request(HTTPClient.METHOD_GET, "http://x/c")).is_code(NetError.Code.NOT_FOUND))
	var bad: NetResult = await h.request(HTTPClient.METHOD_GET, "http://x/d")
	assert_true(bad.is_code(NetError.Code.INVALID))
	assert_eq(bad.reason, "BAD_THING")
	assert_true((await h.request(HTTPClient.METHOD_GET, "http://x/e")).is_code(NetError.Code.SERVER))
	assert_eq(h.sent, 5, "HTTP error answers are never retried")


func test_http_retries_network_errors_only() -> void:
	var pair: Array = _http([{"result": HTTPRequest.RESULT_CANT_CONNECT}, {"result": HTTPRequest.RESULT_TIMEOUT}, {"code": 200, "body": "7"}])
	var h: NetHttp = pair[0]
	var r: NetResult = await h.request(HTTPClient.METHOD_GET, "http://x/a")
	assert_true(r.ok)
	assert_eq(r.value, 7)
	assert_eq(h.sent, 3)
	var down: Array = _http([{"result": HTTPRequest.RESULT_CANT_CONNECT}, {"result": HTTPRequest.RESULT_CANT_CONNECT}, {"result": HTTPRequest.RESULT_CANT_CONNECT}, {"code": 200}])
	var h2: NetHttp = down[0]
	var failed: NetResult = await h2.request(HTTPClient.METHOD_GET, "http://x/a")
	assert_true(failed.is_code(NetError.Code.OFFLINE))
	assert_eq(h2.sent, 3, "gives up after max_attempts")
	var slow: Array = _http([{"result": HTTPRequest.RESULT_TIMEOUT}, {"result": HTTPRequest.RESULT_TIMEOUT}, {"result": HTTPRequest.RESULT_TIMEOUT}])
	assert_true((await (slow[0] as NetHttp).request(HTTPClient.METHOD_GET, "http://x/a")).is_code(NetError.Code.TIMEOUT))


func test_http_post_is_only_retried_when_it_never_left() -> void:
	var lost: Array = _http([{"result": HTTPRequest.RESULT_TIMEOUT}, {"code": 200, "body": "1"}])
	var h: NetHttp = lost[0]
	var r: NetResult = await h.request(HTTPClient.METHOD_POST, "http://x/a", PackedStringArray(), "{}", false)
	assert_true(r.is_code(NetError.Code.TIMEOUT))
	assert_eq(h.sent, 1)
	var refused: Array = _http([{"result": HTTPRequest.RESULT_CANT_RESOLVE}, {"code": 200, "body": "1"}])
	var h2: NetHttp = refused[0]
	assert_true((await h2.request(HTTPClient.METHOD_POST, "http://x/a", PackedStringArray(), "{}", false)).ok)
	assert_eq(h2.sent, 2)


func test_http_sends_json_bodies() -> void:
	var pair: Array = _http([{"code": 200, "body": "{}"}])
	await (pair[0] as NetHttp).json_request(HTTPClient.METHOD_PATCH, "http://x/p", {"actions/3": {"kind": "pass", "tank": 0}, "meta/actionCount": 4})
	var seen: Dictionary = (pair[1] as FakeTransport).seen[0]
	var body: Dictionary = JSON.parse_string(seen["body"]) as Dictionary
	assert_eq(body["meta/actionCount"], 4.0)
	assert_eq(seen["method"], HTTPClient.METHOD_PATCH)


# --- NetFunctions ------------------------------------------------------------------------------------------------------

func _functions(script: Array) -> Array:
	var cfg: NetConfig = NetConfig.emulator()
	var pair: Array = _http(script)
	var http: NetHttp = pair[0]
	var auth := NetAuth.new(cfg, http, "user://net_unit_fn_%d.cfg" % randi())
	auth._id_token = "tok"
	auth._refresh_token = "r"
	auth.uid = "u1"
	auth._expires_at_ms = NetClock.local_ms() + 3600000
	var fns := NetFunctions.new(cfg, http, auth)
	fns.loading_retries = 3
	return [fns, pair[1], auth]


func test_functions_unwrap_results_and_errors() -> void:
	var f: Array = _functions([
		{"code": 200, "body": '{"result": {"matchId": "m1", "seats": [1]}}'},
		{"code": 404, "body": '{"error": {"status": "NOT_FOUND", "message": "unknown_code"}}'},
		{"code": 412, "body": '{"error": {"status": "FAILED_PRECONDITION", "message": "protocol_mismatch", "details": {"hostProtocol": 2, "yourProtocol": 1}}}'},
		{"code": 200, "body": '{"nothing": 1}'},
	])
	var fns: NetFunctions = f[0]
	var ok: NetResult = await fns.call_function("joinMatch", {"code": "ABCDEF"})
	assert_true(ok.ok)
	assert_eq(ok.dict()["matchId"], "m1")
	var seen: Dictionary = (f[1] as FakeTransport).seen[0]
	assert_eq(seen["url"], "http://127.0.0.1:5001/demo-craterline/europe-west1/joinMatch")
	assert_eq(JSON.parse_string(seen["body"]), {"data": {"code": "ABCDEF"}})
	var nf: NetResult = await fns.call_function("joinMatch", {})
	assert_true(nf.is_code(NetError.Code.NOT_FOUND))
	assert_eq(nf.reason, "unknown_code")
	var pm: NetResult = await fns.call_function("joinMatch", {})
	assert_true(pm.is_code(NetError.Code.PROTOCOL_MISMATCH))
	assert_eq(pm.details, {"hostProtocol": 2, "yourProtocol": 1})
	assert_true((await fns.call_function("x", {})).is_code(NetError.Code.BAD_RESPONSE))


func test_functions_wait_for_a_loading_emulator() -> void:
	var f: Array = _functions([{"code": 404, "body": "Function not found"}, {"code": 404, "body": "Function not found"}, {"code": 200, "body": '{"result": {"ok": true}}'}])
	var r: NetResult = await (f[0] as NetFunctions).call_function("ensureProfile", {})
	assert_true(r.ok)
	assert_eq((f[1] as FakeTransport).seen.size(), 3)


# --- NetAuth with a fake backend ------------------------------------------------------------------------------------------------

func test_auth_signs_up_refreshes_and_forgets() -> void:
	var path: String = "user://net_unit_auth_%d.cfg" % randi()
	var pair: Array = _http([
		{"code": 200, "body": '{"idToken": "id1", "refreshToken": "ref1", "localId": "uid1", "expiresIn": "3600"}'},
		{"code": 200, "body": '{"id_token": "id2", "refresh_token": "ref2", "user_id": "uid1", "expires_in": "3600"}'},
	])
	var auth := NetAuth.new(NetConfig.emulator(), pair[0], path)
	var r: NetResult = await auth.ensure_signed_in()
	assert_true(r.ok)
	assert_eq(auth.uid, "uid1")
	assert_eq(await auth.token(), "id1")
	var seen: Dictionary = (pair[1] as FakeTransport).seen[0]
	assert_true((seen["url"] as String).contains("accounts:signUp?key=fake-api-key"))
	auth._expires_at_ms = NetClock.local_ms() + 1000
	assert_eq(await auth.token(), "id2", "refreshed shortly before it expires")
	var refresh_call: Dictionary = (pair[1] as FakeTransport).seen[1]
	assert_eq(refresh_call["body"], "grant_type=refresh_token&refresh_token=ref1")
	var again := NetAuth.new(NetConfig.emulator(), pair[0], path)
	assert_true(again.restore())
	assert_eq(again.uid, "uid1")
	var other_backend := NetAuth.new(NetConfig.production_config(), pair[0], path)
	assert_false(other_backend.restore(), "tokens of one backend are never reused for another")
	auth.sign_out()
	assert_false(FileAccess.file_exists(path))


func test_auth_replaces_an_account_that_no_longer_exists() -> void:
	var path: String = "user://net_unit_auth_%d.cfg" % randi()
	var cf := ConfigFile.new()
	cf.set_value("auth", "endpoint", NetConfig.emulator().endpoint_key())
	cf.set_value("auth", "uid", "old")
	cf.set_value("auth", "refresh_token", "dead")
	cf.save(path)
	var pair: Array = _http([
		{"code": 400, "body": '{"error": {"message": "INVALID_REFRESH_TOKEN"}}'},
		{"code": 200, "body": '{"idToken": "n", "refreshToken": "nr", "localId": "new", "expiresIn": "3600"}'},
	])
	var auth := NetAuth.new(NetConfig.emulator(), pair[0], path)
	var replaced: Array = []
	auth.account_replaced.connect(func(o: String, n: String) -> void: replaced.append([o, n]))
	var r: NetResult = await auth.ensure_signed_in()
	assert_true(r.ok, str(r))
	assert_eq(auth.uid, "new")
	assert_eq(replaced, [["old", "new"]])
	auth.sign_out()


func test_auth_does_not_discard_the_account_on_a_network_error() -> void:
	var path: String = "user://net_unit_auth_%d.cfg" % randi()
	var cf := ConfigFile.new()
	cf.set_value("auth", "endpoint", NetConfig.emulator().endpoint_key())
	cf.set_value("auth", "uid", "keep")
	cf.set_value("auth", "refresh_token", "tok")
	cf.save(path)
	var pair: Array = _http([{"result": HTTPRequest.RESULT_CANT_CONNECT}, {"result": HTTPRequest.RESULT_CANT_CONNECT}, {"result": HTTPRequest.RESULT_CANT_CONNECT}])
	var auth := NetAuth.new(NetConfig.emulator(), pair[0], path)
	var r: NetResult = await auth.ensure_signed_in()
	assert_true(r.is_code(NetError.Code.OFFLINE))
	assert_true(FileAccess.file_exists(path), "the saved sign-in survives a bad connection")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_auth_maps_google_linking_failures() -> void:
	var pair: Array = _http([
		{"code": 400, "body": '{"error": {"message": "FEDERATED_USER_ID_ALREADY_LINKED"}}'},
		{"code": 400, "body": '{"error": {"message": "OPERATION_NOT_ALLOWED"}}'},
	])
	var auth := NetAuth.new(NetConfig.emulator(), pair[0], "user://net_unit_auth_%d.cfg" % randi())
	auth._id_token = "t"
	auth._refresh_token = "r"
	auth.uid = "u"
	auth._expires_at_ms = NetClock.local_ms() + 3600000
	var linked: NetResult = await auth.link_google("g")
	assert_true(linked.is_code(NetError.Code.PRECONDITION))
	assert_eq(linked.reason, "google_already_linked")
	var anon: NetResult = await auth.sign_up_anonymous()
	assert_true(anon.is_code(NetError.Code.UNAVAILABLE))
	assert_eq(anon.reason, "anonymous_disabled")
	assert_true((await auth.link_google("")).is_code(NetError.Code.INVALID))


func test_google_failures_map_to_typed_codes() -> void:
	assert_true(NetAccount.google_failure(GoogleSignIn.Error.CANCELLED, "").is_code(NetError.Code.CANCELLED))
	assert_true(NetAccount.google_failure(GoogleSignIn.Error.NETWORK, "").is_code(NetError.Code.OFFLINE))
	assert_true(NetAccount.google_failure(GoogleSignIn.Error.UNAVAILABLE, "").is_code(NetError.Code.UNAVAILABLE))
	assert_eq(NetAccount.google_failure(GoogleSignIn.Error.CONFIG, "x").reason, "config")


# --- NetDb helpers, NetStream parser ------------------------------------------------------------------------------------------

func test_db_urls_and_queries() -> void:
	var db := NetDb.new(NetConfig.emulator(), NetHttp.new(), null)
	assert_eq(db.url("matches/m1/meta", {}, "tok"), "http://127.0.0.1:9000/matches/m1/meta.json?ns=demo-craterline-default-rtdb&auth=tok")
	var q: String = db.url("matches/m1/actions", NetDb.from_index(5), "t")
	assert_true(q.contains("orderBy=%22%24key%22") and q.contains("startAt=%225%22"), q)
	var prod := NetDb.new(NetConfig.production_config(), NetHttp.new(), null)
	assert_false(prod.url("x", {}, "t").contains("ns="), "the real database needs no namespace")
	assert_eq(NetDb.server_timestamp(), {".sv": "timestamp"})


func _stream_with(text: String) -> NetStream:
	var s := NetStream.new()
	s.setup(null, "a/b", {}, true)
	s.state = NetStream.State.STREAMING
	s._buf = text.to_utf8_buffer()
	return s


func test_sse_parser_handles_put_patch_keepalive_and_split_chunks() -> void:
	var events: Array = []
	var s: NetStream = _stream_with('event: put\ndata: {"path":"/","data":{"a":1,"b":{"c":2}}}\n\nevent: keep-alive\ndata: null\n\nevent: patch\r\ndata: {"path":"/b","data":{"c":3,"d":null}}\r\n\r\nevent: put\ndata: {"path":"/x/y","da')
	s.event_received.connect(func(k: String, p: String, d: Variant) -> void: events.append([k, p, d]))
	s._consume()
	assert_eq(events.size(), 2)
	assert_eq(events[0], ["put", "/", {"a": 1, "b": {"c": 2}}])
	assert_eq(events[1][0], "patch")
	assert_eq(s.value, {"a": 1, "b": {"c": 3}})
	# the rest of the split event arrives in the next chunk
	s._buf.append_array('ta":"hi"}\n\n'.to_utf8_buffer())
	s._consume()
	assert_eq(events.size(), 3)
	assert_eq(s.value, {"a": 1, "b": {"c": 3}, "x": {"y": "hi"}})
	assert_true(s.is_connected_now)
	s.free()


func test_sse_cache_deletes_with_null_and_converts_arrays() -> void:
	var s: NetStream = _stream_with('event: put\ndata: {"path":"/","data":{"seats":[{"k":"a"},{"k":"b"}],"n":1}}\n\nevent: put\ndata: {"path":"/seats/1","data":{"k":"z"}}\n\nevent: put\ndata: {"path":"/n","data":null}\n\n')
	s._consume()
	assert_eq(NetJson.as_list((s.value as Dictionary)["seats"]), [{"k": "a"}, {"k": "z"}])
	assert_false((s.value as Dictionary).has("n"))
	s.free()


func test_sse_patch_with_deep_paths() -> void:
	var s: NetStream = _stream_with('event: put\ndata: {"path":"/","data":{"meta":{"actionCount":2}}}\n\nevent: patch\ndata: {"path":"/","data":{"meta/actionCount":3,"meta/turn":{"tank":1}}}\n\n')
	s._consume()
	assert_eq(s.value, {"meta": {"actionCount": 3, "turn": {"tank": 1}}})
	s.free()


func test_url_splitting() -> void:
	var p: Dictionary = NetStream._split_url("http://127.0.0.1:9000/a/b.json?x=1")
	assert_eq([p["tls"], p["host"], p["port"], p["request"]], [false, "127.0.0.1", 9000, "/a/b.json?x=1"])
	var q: Dictionary = NetStream._split_url("https://db.europe-west1.firebasedatabase.app/m.json?auth=t")
	assert_eq([q["tls"], q["host"], q["port"]], [true, "db.europe-west1.firebasedatabase.app", 443])


# --- lists -----------------------------------------------------------------------------------------------------------------

func test_your_matches_sorting() -> void:
	var raw: Dictionary = {
		"old": {"status": "over", "updated": 5, "yourTurn": false},
		"wait": {"status": "playing", "updated": 9, "yourTurn": false},
		"mine": {"status": "playing", "updated": 1, "yourTurn": true},
		"lobby": {"status": "lobby", "updated": 7, "yourTurn": false},
		"newer": {"status": "over", "updated": 8, "yourTurn": false},
	}
	var ids: Array = []
	for e: Variant in NetMatches.sorted(raw):
		ids.append((e as Dictionary)["matchId"])
	assert_eq(ids, ["mine", "wait", "lobby", "newer", "old"])
	assert_eq(NetMatches.sorted(null), [])


func test_friend_list_helpers() -> void:
	var inv: Array = NetFriends.invites_from({"m1": {"fromUid": "u", "at": 5, "mode": 1}, "m2": {"fromUid": "v", "at": 9, "mode": 0}})
	assert_eq((inv[0] as Dictionary)["matchId"], "m2")
	assert_eq(NetFriends.visible_invites(inv, false).size(), 1)
	assert_eq(NetFriends.visible_invites(inv, true).size(), 2)
	var req: Array = NetFriends.requests_from({"u1": {"name": "A", "at": 9}, "u2": {"name": "B", "at": 3}})
	assert_eq((req[0] as Dictionary)["uid"], "u2")


func test_lobby_builders_and_meta_normalising() -> void:
	assert_eq(NetLobby.seat_human(true, "Me"), {"kind": "human", "mine": true, "name": "Me"})
	assert_eq(NetLobby.seat_cpu(9), {"kind": "cpu", "level": 4})
	assert_eq(NetLobby.settings({"rounds": 5})["rounds"], 5)
	assert_eq(NetLobby.timers(0, 24, "end"), {"liveSec": 0, "asyncHours": 24, "asyncTimeout": "end"})
	var m: Dictionary = NetLobby.normalize_meta({"seats": {"0": {"kind": "human"}, "1": {"kind": "cpu"}}, "settings": {"controllers": {"0": 0, "1": 2}}})
	assert_eq((m["seats"] as Array).size(), 2)
	assert_eq((m["settings"] as Dictionary)["controllers"], [0, 2])


func test_push_key_is_a_hash_of_the_token() -> void:
	var key: String = NetAccount.push_key("some-fcm-token-value-123456")
	assert_eq(key.length(), 32)
	assert_true(key.is_valid_hex_number())
	assert_eq(key, NetAccount.push_key("some-fcm-token-value-123456"))
	assert_ne(key, NetAccount.push_key("another-fcm-token-value-12345"))
	assert_eq(NetAccount.public_name("", false, "abcd1234"), "PLAYER ABCD")
	assert_eq(NetAccount.public_name("Zed", false, "abcd1234"), "Zed")
