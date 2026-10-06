extends "res://tests/net/net_it_base.gd"
## Accounts, names, friends, blocks, reports, lobbies and invites against the emulators.


func test_sign_up_persist_refresh_and_sign_out() -> void:
	if not _need_emulator():
		return
	var path: String = "user://net_it_persist_%d.cfg" % randi()
	var cfg: NetConfig = NetConfig.from_environment()
	var http := NetHttp.new()
	var auth := NetAuth.new(cfg, http, path)
	var r: NetResult = await auth.ensure_signed_in()
	assert_true(r.ok, str(r))
	var uid: String = auth.uid
	assert_ne(uid, "")
	assert_true(auth.anonymous)
	assert_true(FileAccess.file_exists(path))
	var token1: String = await auth.token()
	assert_ne(token1, "")
	# a second instance restores the same account from the file
	var again := NetAuth.new(cfg, http, path)
	assert_true(again.restore())
	var r2: NetResult = await again.ensure_signed_in()
	assert_true(r2.ok, str(r2))
	assert_eq(again.uid, uid)
	# a token close to expiry is refreshed by token()
	again._expires_at_ms = NetClock.local_ms() + 1000
	var token2: String = await again.token()
	assert_ne(token2, "")
	assert_gt(again._expires_at_ms, NetClock.local_ms() + 600000)
	again.sign_out()
	assert_false(FileAccess.file_exists(path))
	assert_eq(again.uid, "")
	assert_eq(await again.token(), "")


func test_profile_name_and_public_names() -> void:
	if not _need_emulator():
		return
	var a: NetSession = await _phone("Anna")
	assert_eq(a.account.friend_code().length(), 8)
	assert_eq(a.account.profile["protocol"], NetProtocol.VERSION)
	var bad: NetResult = await a.account.set_name("   ")
	assert_true(bad.is_code(NetError.Code.NAME_REJECTED))
	var b: NetSession = await _phone("Bob")
	var seen: NetResult = await b.account.fetch_public(a.uid())
	assert_true(seen.ok, str(seen))
	assert_eq(seen.dict()["display"], "Anna")
	assert_eq(NetAccount.public_name("x", true, "abcdef"), "PLAYER ABCD")
	# the clock was synced from the server
	assert_lt(absi(a.clock.now_ms() - NetClock.local_ms()), 5000)


func test_friends_requests_blocks_and_reports() -> void:
	if not _need_emulator():
		return
	var a: NetSession = await _phone("Ann")
	var b: NetSession = await _phone("Ben")
	var c: NetSession = await _phone("Cat")
	var own: NetResult = await a.friends.send_request(a.account.friend_code())
	assert_true(own.is_code(NetError.Code.PRECONDITION))
	assert_eq(own.reason, "own_code")
	var badcode: NetResult = await a.friends.send_request("nope")
	assert_eq(badcode.reason, "bad_code")
	var seen: Array = []
	b.friends.requests_changed.connect(func(l: Array) -> void: seen.append(l))
	b.friends.watch()
	var sent: NetResult = await a.friends.send_request(b.account.friend_code().to_lower())
	assert_true(sent.ok, str(sent))
	assert_eq(sent.dict()["status"], "sent")
	assert_true(await _until(func() -> bool: return b.friends.requests.size() == 1), "request streamed")
	assert_eq(b.friends.requests[0]["uid"], a.uid())
	var acc: NetResult = await b.friends.respond(a.uid(), true)
	assert_true(acc.ok, str(acc))
	var list: NetResult = await a.friends.list_friends()
	assert_eq(list.list().size(), 1)
	assert_eq(list.list()[0]["display"], "Ben")
	# blocks hide a player: a blocked friend code looks unknown
	var blocked: NetResult = await b.friends.block(a.uid())
	assert_true(blocked.ok)
	assert_eq((await a.friends.list_friends()).list().size(), 0)
	var hidden: NetResult = await a.friends.send_request(b.account.friend_code())
	assert_true(hidden.is_code(NetError.Code.NOT_FOUND), str(hidden))
	assert_eq(hidden.reason, "unknown_code")
	assert_eq((await b.friends.list_blocks()).list(), [a.uid()])
	assert_true((await b.friends.unblock(a.uid())).ok)
	# three different reporters hide a name (a report needs a friendship or a shared match with the target)
	await _befriend(a, c)
	await _befriend(b, c)
	assert_true((await a.friends.report(c.uid())).ok)
	assert_true((await b.friends.report(c.uid())).ok)
	var dup: NetResult = await b.friends.report(c.uid())
	assert_true(dup.ok)
	assert_true(dup.dict()["duplicate"])
	var d: NetSession = await _phone("Dan")
	var stranger_report: NetResult = await d.friends.report(c.uid())
	assert_true(stranger_report.is_code(NetError.Code.NOT_FOUND), "a stranger cannot report: %s" % str(stranger_report))
	await _befriend(d, c)
	var third: NetResult = await d.friends.report(c.uid())
	assert_true(third.ok, str(third))
	assert_true(await _until(func() -> bool:
		return (await d.account.fetch_public(c.uid(), true)).dict().get("hidden", false) == true), "name hidden after 3 reports")
	assert_eq((await d.account.fetch_public(c.uid())).dict()["display"], "PLAYER %s" % c.uid().substr(0, 4).to_upper())


func test_lobby_create_join_start_invite_and_protocol() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hope", false)
	var free_try: NetResult = await host.lobby.create(NetLobby.settings(), [NetLobby.seat_human(true), NetLobby.seat_cpu()])
	assert_true(free_try.is_code(NetError.Code.PERMISSION))
	assert_eq(free_try.reason, "full_required")
	var h: NetSession = await _phone("Host", true)
	var g: NetSession = await _phone("Guest")
	await _befriend(h, g)
	var made: NetResult = await h.lobby.create(NetLobby.settings({"rounds": 1}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
	assert_true(made.ok, str(made))
	var id: String = made.dict()["matchId"]
	var code: String = made.dict()["code"]
	var changes: Array = []
	var started_flag: Array = [false]
	h.lobby.lobby_changed.connect(func(m: Dictionary) -> void: changes.append(m))
	h.lobby.watch(id)
	assert_true(await _until(func() -> bool: return changes.size() >= 1))
	assert_eq((changes[0]["seats"] as Array).size(), 3)
	var early: NetResult = await h.lobby.start(id)
	assert_eq(early.reason, "seats_not_filled")
	assert_true((await h.lobby.invite(g.uid(), id)).ok)
	assert_true(await _until(func() -> bool: return g.friends.invites.size() == 1 or (await g.friends.list_invites()).list().size() == 1))
	var inv: Dictionary = (await g.friends.list_invites()).list()[0]
	assert_eq(inv["code"], code)
	assert_eq(NetFriends.visible_invites([inv], false).size(), 1)
	assert_eq(NetFriends.visible_invites([{"mode": 1}], false).size(), 0)
	var wrong: NetResult = await g.lobby.join("ZZZZZZ")
	assert_true(wrong.is_code(NetError.Code.NOT_FOUND))
	var bad: NetResult = await g.lobby.join("abc")
	assert_eq(bad.reason, "bad_code")
	h.lobby.lobby_started.connect(func(_m: Dictionary) -> void: started_flag[0] = true)
	var joined: NetResult = await g.lobby.join(code.to_lower())
	assert_true(joined.ok, str(joined))
	assert_eq(joined.dict()["seats"], [1])
	assert_true((await g.friends.dismiss_invite(id)).ok)
	var starts: NetResult = await h.lobby.start(id)
	assert_true(starts.ok, str(starts))
	assert_true(await _until(func() -> bool: return started_flag[0] as bool), "lobby_started streamed")
	# "Your matches" lists it for both
	assert_true(await _until(func() -> bool: return (await g.matches.refresh()).list().size() == 1))
	assert_eq((g.matches.list[0] as Dictionary)["matchId"], id)
	# a client of another protocol version is refused by the join
	await h.functions.call_function("ensureProfile", {"protocol": NetProtocol.VERSION})
	var old: NetSession = await _phone("Old")
	await old.functions.call_function("ensureProfile", {"protocol": NetProtocol.VERSION + 1})
	var made2: NetResult = await h.lobby.create(NetLobby.settings(), [NetLobby.seat_human(true), NetLobby.seat_human()])
	var refused: NetResult = await old.lobby.join(made2.dict()["code"] as String)
	assert_true(refused.is_code(NetError.Code.PROTOCOL_MISMATCH), str(refused))
	assert_eq(refused.details["hostProtocol"], NetProtocol.VERSION)


func test_open_match_refuses_a_lobby_and_an_outsider() -> void:
	if not _need_emulator():
		return
	var h: NetSession = await _phone("Hh", true)
	var o: NetSession = await _phone("Out")
	var made: NetResult = await h.lobby.create(NetLobby.settings(), [NetLobby.seat_human(true), NetLobby.seat_cpu()])
	var id: String = made.dict()["matchId"]
	var lobby_open: NetResult = await h.open_match(id)
	assert_true(lobby_open.is_code(NetError.Code.NOT_STARTED), str(lobby_open))
	var out: NetResult = await o.open_match(id)
	assert_false(out.ok)
	assert_true(out.is_code(NetError.Code.PERMISSION), str(out))


func test_link_google_with_the_fake_sheet() -> void:
	if not _need_emulator():
		return
	var a: NetSession = await _phone("Gina")
	var uid: String = a.uid()
	a.config.web_client_id = "test-client.apps.googleusercontent.com"
	var fake := GoogleSignInFake.new()
	var email: String = "gina%d@example.com" % randi()
	fake.fake_id_token = JSON.stringify({"sub": "g-%d" % randi(), "email": email, "email_verified": true})
	var wrapper := GoogleSignIn.new(fake)
	wrapper.start()
	var linked: NetResult = await a.account.link_google(wrapper)
	assert_true(linked.ok, str(linked))
	assert_eq(a.uid(), uid, "linking keeps the uid")
	assert_false(a.auth.anonymous)
	assert_eq(a.auth.email, email)
	# the same Google identity cannot be linked to a second account
	var b: NetSession = await _phone("Gil")
	b.config.web_client_id = a.config.web_client_id
	var clash: NetResult = await b.account.link_google(wrapper)
	assert_true(clash.is_code(NetError.Code.PRECONDITION), str(clash))
	assert_eq(clash.reason, "google_already_linked")
	var restored: NetResult = await b.account.restore_with_google(wrapper)
	assert_true(restored.ok, str(restored))
	assert_eq(b.uid(), uid, "restore_with_google signs in to the account that owns the identity")
	# cancelled and unavailable sheets map to typed codes
	fake.next_result = "cancelled"
	assert_true((await a.account.link_google(wrapper)).is_code(NetError.Code.CANCELLED))
	fake.available_flag = false
	wrapper.start()
	assert_true((await a.account.link_google(wrapper)).is_code(NetError.Code.UNAVAILABLE))


func test_push_token_registration_and_delete_my_data() -> void:
	if not _need_emulator():
		return
	var a: NetSession = await _phone("Pia")
	var fake := PushFake.new()
	var push := PushService.new(fake)
	push.start()
	a.account.bind_push(push)
	var key: String = NetAccount.push_key(fake.token_value + "-padding-padding")
	var direct: NetResult = await a.account.register_push_token(fake.token_value + "-padding-padding")
	assert_true(direct.ok, str(direct))
	var read: NetResult = await a.db.get_value("users/%s/fcm/%s" % [a.uid(), key])
	assert_eq(read.value, fake.token_value + "-padding-padding")
	assert_true((await a.account.register_push_token("short")).is_code(NetError.Code.INVALID))
	var uid: String = a.uid()
	var del: NetResult = await a.account.delete_my_data()
	assert_true(del.ok, str(del))
	assert_eq(a.uid(), "", "signed out after deleting")
	assert_eq(await a.auth.token(), "")
	var admin: NetResult = await _admin(HTTPClient.METHOD_GET, "users/%s" % uid)
	assert_null(admin.value)
