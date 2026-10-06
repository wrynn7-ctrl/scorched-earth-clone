extends "res://tests/net/net_it_base.gd"
## M7-G against the emulators: the purchase token reaches `verifyPurchase` through the fake billing flow (the emulator's stub
## accepts "test-full"), a verified owner can host, and a friend request can be sent by uid between members of one match.


func before_each() -> void:
	Entitlement.reset_for_tests(false, "user://test_it_full_entitlement.cfg")


func after_each() -> void:
	Entitlement.forget_for_tests()
	super.after_each()


## The stub accepts "test-full" once per account and one account per token; start every test with it free.
func _free_the_test_token() -> void:
	var r: NetResult = await _admin(HTTPClient.METHOD_DELETE, "purchaseTokens")
	assert_true(r.ok, "cleared purchaseTokens: %s" % str(r))


func test_the_fake_billing_flow_sets_the_server_flag_and_the_player_can_host() -> void:
	if not _need_emulator():
		return
	await _free_the_test_token()
	var owner_phone: NetSession = await _phone("Olga")
	assert_false(owner_phone.account.is_full())
	var before: NetResult = await owner_phone.lobby.create(NetLobby.settings(), [NetLobby.seat_human(true), NetLobby.seat_cpu()])
	assert_eq(before.reason, "full_required", "hosting is refused until the purchase is verified")

	Entitlement.purchase_full()  # the fake store, debug build: owned, token "test-full"
	assert_true(Entitlement.is_full())
	assert_eq(Entitlement.purchase_token(), "test-full")
	var synced: NetResult = await owner_phone.account.sync_full(Entitlement.purchase_token())
	assert_true(synced.ok, str(synced))
	assert_true(owner_phone.account.is_full())
	var fresh: NetResult = await owner_phone.account.ensure_profile()
	assert_true(fresh.dict().get("full", false), "the server profile says full")

	var guest: NetSession = await _phone("Gus")
	var info: Dictionary = await _start_match(owner_phone, [guest], NetLobby.settings({"rounds": 1}),
			[NetLobby.seat_human(true), NetLobby.seat_human()])
	assert_true(info.has("seed"), "the verified owner hosted and started a match")


func test_sync_full_sends_nothing_when_already_full_and_needs_a_token_otherwise() -> void:
	if not _need_emulator():
		return
	await _free_the_test_token()
	var s: NetSession = await _phone("Finn", true)
	assert_true(s.account.is_full())
	var again: NetResult = await s.account.sync_full("anything")
	assert_true(again.ok, "already full: nothing to do, nothing sent")
	var t: NetSession = await _phone("Tess")
	var none: NetResult = await t.account.sync_full("")
	assert_eq(none.reason, "no_token")
	assert_false(t.account.is_full())


func test_a_wrong_token_is_refused_and_one_token_unlocks_one_account() -> void:
	if not _need_emulator():
		return
	await _free_the_test_token()
	var a: NetSession = await _phone("Ava")
	var bad: NetResult = await a.account.sync_full("not-a-real-token")
	assert_false(bad.ok)
	assert_false(a.account.is_full())
	var good: NetResult = await a.account.sync_full("test-full")
	assert_true(good.ok, str(good))
	var b: NetSession = await _phone("Bo")
	var second: NetResult = await b.account.sync_full("test-full")
	assert_true(second.is_code(NetError.Code.ALREADY_EXISTS), str(second))
	assert_eq(second.reason, "token_used")
	assert_false(b.account.is_full())


func test_friend_request_by_uid_between_members_of_one_match() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hugo", true)
	var guest: NetSession = await _phone("Gia")
	var outsider: NetSession = await _phone("Omar")
	var made: NetResult = await host.lobby.create(NetLobby.settings({"rounds": 1}), [NetLobby.seat_human(true), NetLobby.seat_human()])
	assert_true(made.ok, str(made))
	var match_id: String = made.dict()["matchId"]
	assert_true((await guest.lobby.join(made.dict()["code"] as String)).ok)

	var sent: NetResult = await guest.friends.request_by_uid(host.uid(), match_id)
	assert_true(sent.ok, str(sent))
	assert_eq(sent.dict()["status"], "sent")
	assert_eq(sent.dict()["name"], "Hugo")
	var pending: NetResult = await host.friends.list_requests()
	assert_eq((pending.list() as Array).size(), 1)
	assert_eq(((pending.list() as Array)[0] as Dictionary)["uid"], guest.uid())
	assert_true((await host.friends.respond(guest.uid(), true)).ok)
	assert_eq((await guest.friends.list_friends()).list().size(), 1)
	var again: NetResult = await guest.friends.request_by_uid(host.uid(), match_id)
	assert_eq(again.reason, "already_friends")

	var stranger: NetResult = await outsider.friends.request_by_uid(host.uid(), match_id)
	assert_true(stranger.is_code(NetError.Code.PERMISSION), str(stranger))
	assert_eq(stranger.reason, "not_a_member")
	var probe: NetResult = await guest.friends.request_by_uid(outsider.uid(), match_id)
	assert_eq(probe.reason, "unknown_code", "a player outside the match looks like an unknown code")
	var bad: NetResult = await guest.friends.request_by_uid("", match_id)
	assert_true(bad.is_code(NetError.Code.INVALID))


func test_a_blocked_pair_gets_the_neutral_error_for_a_uid_request() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hanna", true)
	var guest: NetSession = await _phone("Gil")
	var made: NetResult = await host.lobby.create(NetLobby.settings({"rounds": 1}), [NetLobby.seat_human(true), NetLobby.seat_human()])
	var match_id: String = made.dict()["matchId"]
	assert_true((await guest.lobby.join(made.dict()["code"] as String)).ok)
	assert_true((await host.friends.block(guest.uid())).ok)
	var r: NetResult = await guest.friends.request_by_uid(host.uid(), match_id)
	assert_true(r.is_code(NetError.Code.NOT_FOUND), str(r))
	assert_eq(r.reason, "unknown_code")
	var back: NetResult = await host.friends.request_by_uid(guest.uid(), match_id)
	assert_eq(back.reason, "unknown_code")
	assert_eq((await host.friends.list_requests()).list().size(), 0)
