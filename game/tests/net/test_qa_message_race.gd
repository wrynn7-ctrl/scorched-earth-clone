extends "res://tests/net/net_it_base.gd"
## M7-Q diagnosis of the flaky "the guest sees the host's bubble" (test_it_ui_flow): a quick message that is written before the
## receiver's `msgs` stream has connected used to be dropped by the receiver as "history" (the whole first snapshot was treated as
## what was said before we opened). Fixed in M7-QF-B: OnlineMatch._handle_message keeps a snapshot message whose `at` is newer than
## the server time of opening (minus a 2 s margin). The test sends the message one frame after the guest opened the match, so it
## races the SSE connect.


func _pair() -> Dictionary:
	var host: NetSession = await _phone("Hana", true)
	var guest: NetSession = await _phone("Finn")
	await _befriend(host, guest)
	var info: Dictionary = await _start_match(host, [guest], NetLobby.settings({"rounds": 1, "wind_max": 10}),
			[NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
	var mh: OnlineMatch = await _open(host, info["matchId"] as String)
	var mg: OnlineMatch = await _open(guest, info["matchId"] as String)
	return {"mh": mh, "mg": mg}


func _msg_stream_up(m: OnlineMatch) -> bool:
	return m.streams_ready()


func test_a_message_sent_after_the_receivers_message_stream_is_up_arrives() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair()
	var mh: OnlineMatch = c["mh"]
	var mg: OnlineMatch = c["mg"]
	var got: Array = []
	mg.message_received.connect(func(seat: int, msg: int, _who: String) -> void: got.append([seat, msg]))
	assert_true(await _until(func() -> bool: return _msg_stream_up(mg), 10.0), "the guest's msgs stream connected")
	await get_tree().create_timer(0.3).timeout
	assert_true((await mh.send_message(2, mh.my_seats[0])).ok)
	assert_true(await _until(func() -> bool: return got.size() == 1, 10.0), "control: delivered")


func test_a_message_sent_right_after_the_receiver_opened_the_match_is_not_lost() -> void:
	if not _need_emulator():
		return
	var lost: int = 0
	var tries: int = 6
	for i: int in range(tries):
		var c: Dictionary = await _pair()
		var mh: OnlineMatch = c["mh"]
		var mg: OnlineMatch = c["mg"]
		var got: Array = []
		mg.message_received.connect(func(seat: int, msg: int, _who: String) -> void: got.append([seat, msg]))
		var up_at_send: bool = _msg_stream_up(mg)
		await get_tree().process_frame
		assert_true((await mh.send_message(2, mh.my_seats[0])).ok)
		var delivered: bool = await _until(func() -> bool: return got.size() == 1, 6.0)
		if not delivered:
			lost += 1
		gut.p("try %d: guest msgs stream up at send time: %s, delivered: %s" % [i, up_at_send, delivered])
		mh.close()
		mg.close()
		await get_tree().create_timer(3.2).timeout  # the 3 s limiter belongs to the match, a new match starts fresh anyway
	assert_eq(lost, 0, "%d of %d quick messages sent right after the receiver opened the match were lost" % [lost, tries])


func test_streams_ready_and_the_ready_signal_after_open() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair()
	var mg: OnlineMatch = c["mg"]
	var fired: Array = []
	mg.ready.connect(func() -> void: fired.append(true))
	assert_true(await _until(func() -> bool: return mg.streams_ready(), 15.0), "meta, actions and msgs streams are up with their snapshots")
	assert_true(fired.size() <= 1, "ready is emitted once")
	assert_true(mg.streams_ready())
	mg.close()
	assert_false(mg.streams_ready(), "a closed match is not ready")


func test_a_refused_message_is_a_rate_limit_only_when_the_limiter_explains_it() -> void:
	if not _need_emulator():
		return
	var c: Dictionary = await _pair()
	var mh: OnlineMatch = c["mh"]
	assert_true(await _until(func() -> bool: return mh.streams_ready(), 15.0))
	# a real rate limit: another write of this account's limiter inside 3 s (as a second phone would make) is RATE_LIMITED
	assert_true((await mh.send_message(1, mh.my_seats[0])).ok)
	mh._last_msg_ms = -1000000  # as if this phone did not know about the other message
	var limited: NetResult = await mh.send_message(1, mh.my_seats[0])
	assert_true(limited.is_code(NetError.Code.RATE_LIMITED), str(limited))
	# another reason: the match is no longer running, the limiter is long over: PERMISSION with the rules' reason
	await get_tree().create_timer(3.4).timeout
	assert_true((await mh.abandon()).ok)
	var refused: NetResult = await mh.send_message(1, mh.my_seats[0])
	assert_false(refused.ok)
	assert_true(refused.is_code(NetError.Code.PERMISSION), "not a rate limit: %s" % str(refused))
	assert_false(refused.is_code(NetError.Code.RATE_LIMITED))
	# and the client-side cooldown did not start for a message that was never sent
	var again: NetResult = await mh.send_message(1, mh.my_seats[0])
	assert_true(again.is_code(NetError.Code.PERMISSION), str(again))
