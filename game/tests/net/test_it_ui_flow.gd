extends "res://tests/net/net_it_base.gd"
## The online screens against the real backend (emulators): host a lobby from the Host page, join it with the code from the
## Join page on a second phone, start it, and play it to the end through the battle controllers of both phones (the real
## OnlineMatch drives them). Both screens must end in the same state as the log, with no dispute and no mismatch.

var _controllers: Array[OnlineBattleController] = []
var _by_phone: Dictionary = {}


func before_each() -> void:
	OnlineHub.reset()
	OnlineHub.intercept_navigation = true
	SettingsStore.path = "user://test_it_ui_prefs.cfg"
	SettingsStore.delete()
	SettingsStore.online_named = true
	Entitlement.reset_for_tests(true)
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))
	OnlineHub.on_play = func(m: OnlineMatch) -> void: _by_phone[m.uid] = m


func after_each() -> void:
	for c: OnlineBattleController in _controllers:
		if is_instance_valid(c):
			c.queue_free()
	_controllers.clear()
	_by_phone.clear()
	OnlineHub.reset()
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SettingsStore.online_named = false
	Entitlement.forget_for_tests()
	super.after_each()


func _battle(m: OnlineMatch) -> OnlineBattleController:
	var b: OnlineBattleController = (load("res://show/online/online_battle_scene.tscn") as PackedScene).instantiate()
	b.attach_match(m)
	b.configure(1, 1, true)
	add_child(b)
	_controllers.append(b)
	return b


## One step of a phone's player through the screens: READY in the shop, a shot on an aim turn.
func _act(b: OnlineBattleController) -> void:
	if b.is_sending() or b.queue_size() > 0:
		return
	var st: MatchState = b.get_state()
	if st.phase == SimConstants.PHASE_SHOP:
		if b.get_shop().is_showing_shop() and not b.get_shop().is_showing_handover():
			b.get_shop()._on_ready()
		elif b.get_shop().is_showing_handover():
			b.get_shop()._on_continue()
		elif b.get_round_overlay().is_open():
			b.next_round()
		return
	if b.may_act():
		var shot: Vector2i = AutoShot.find_shot(st, st.current_tank)
		b.set_aim(shot.x, shot.y)
		b.fire_current()


func test_host_join_start_and_play_through_the_screens() -> void:
	if not _need_emulator():
		return
	var host: NetSession = await _phone("Hana", true)
	var guest: NetSession = await _phone("Finn")
	await _befriend(host, guest)

	# Host page -> lobby
	var host_tab := HostTab.new()
	add_child_autofree(host_tab)
	host_tab.setup(host)
	var made: Array = []
	host_tab.open_lobby.connect(func(id: String) -> void: made.append(id))
	await host_tab.create()
	assert_eq(made.size(), 1, "the lobby was created")
	var id: String = made[0]
	var host_lobby: LobbyScreen = (load("res://ui/online/lobby_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(host_lobby)
	await host_lobby.open_lobby(host, id)
	assert_true(host_lobby.is_host())
	assert_true(host_lobby.get_start_button().disabled, "the second seat is still open")
	var code: String = host_lobby.get_code_text()
	assert_eq(code.length(), 6)

	# the host adds a CPU and sets a short match
	await host_lobby.add_cpu()
	await host_lobby.set_rule("rounds", 1)
	assert_eq(LobbyModel.seats_of(host_lobby.get_meta_copy()).size(), 3)

	# Join page on the second phone -> lobby
	var join_tab := JoinTab.new()
	add_child_autofree(join_tab)
	join_tab.setup(guest)
	var joined: Array = []
	join_tab.open_lobby.connect(func(match_id: String) -> void: joined.append(match_id))
	join_tab.set_code(code)
	await join_tab.join()
	assert_eq(joined, [id])
	OnlineHub.lobby_to_show = ""  # the scene start of the second screen must not open a lobby by itself
	var guest_lobby: LobbyScreen = (load("res://ui/online/lobby_screen.tscn") as PackedScene).instantiate()
	add_child_autofree(guest_lobby)
	await guest_lobby.open_lobby(guest, id)
	assert_false(guest_lobby.is_host())
	assert_true(await _until(func() -> bool: return not host_lobby.get_start_button().disabled), "the host sees the joiner and may start")

	# START: both phones go to the battle with their own OnlineMatch
	host_lobby.start_match()
	assert_true(await _until(func() -> bool: return _by_phone.size() == 2, 20.0), "both phones were handed a match: have %s of %s / %s; host entering=%s guest entering=%s guest meta status=%s watching=%s stream=%s" % [_by_phone.keys(), host.uid(), guest.uid(), host_lobby._entering, guest_lobby._entering, guest_lobby.get_meta_copy().get("status"), guest_lobby._watching, guest.lobby._stream])
	var mh: OnlineMatch = _by_phone[host.uid()]
	var mg: OnlineMatch = _by_phone[guest.uid()]
	_matches.append(mh)
	_matches.append(mg)
	var bh: OnlineBattleController = _battle(mh)
	var bg: OnlineBattleController = _battle(mg)
	await get_tree().process_frame

	# a quick message crosses over once the guest's streams (msgs included) are up and have delivered their snapshots
	assert_true(await _until(func() -> bool: return mg.streams_ready(), 20.0), "the guest's match is open and its streams are connected")
	assert_true(await _until(func() -> bool: return mh.streams_ready(), 20.0), "the host's streams are connected")
	var sent: NetResult = await mh.send_message(2, mh.my_seats[0])
	assert_true(sent.ok, str(sent))
	assert_true(await _until(func() -> bool: return bg.get_online_overlay().bubble_count() == 1, 10.0), "the guest sees the host's bubble")

	# play to the end, each phone only through its own screen
	var deadline: int = Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline and not (bh.get_match_overlay().is_open() and bg.get_match_overlay().is_open()):
		_act(bh)
		_act(bg)
		await get_tree().create_timer(0.05).timeout
	assert_true(bh.get_match_overlay().is_open(), "the host's phone shows the result")
	assert_true(bg.get_match_overlay().is_open(), "the guest's phone shows the result")
	assert_true(await _until(func() -> bool: return mh.replay.count == mg.replay.count))
	await get_tree().create_timer(0.3).timeout
	for b: OnlineBattleController in [bh, bg]:
		assert_false(b.is_disputed_shown(), "no dispute")
		assert_eq(b.mismatch_count, 0, "the pictures matched the state")
		assert_eq(b.queue_size(), 0)
		assert_eq(Simulation.fingerprint(b.get_state()), mh.replay.fingerprint(), "the display ended in the match's state")
		assert_eq(b.get_match_overlay().get_title_button().text, "BACK TO ONLINE")
	assert_eq(mh.replay.fingerprint(), mg.replay.fingerprint())
