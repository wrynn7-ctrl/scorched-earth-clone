extends Node
## Screenshot runner for the online screens with fake data (no network): `tools/screenshot.sh
## res://tests/ui/online_demo.tscn 2340x1080 500 out.png 1.5 --online-demo=<name>`. Names: home-matches, home-friends,
## home-join, home-host, home-name, home-offline, home-update, lobby-host, lobby-joiner, battle-waiting, battle-turn,
## battle-bubble, battle-dispute, settings. Test-only: it lives under tests and is never part of the game's flow.

const SHOT_CHECK_FRAMES: int = 3

var _demo: String = "home-matches"


func _ready() -> void:
	ShotArgs.parse()
	SettingsStore.path = "user://demo_online_prefs.cfg"
	SettingsStore.online_named = true
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--online-demo="):
			_demo = a.substr(14)
	OnlineHub.reset()
	OnlineHub.intercept_navigation = true
	var net: OnlineFakes.FakeNet = OnlineFakes.net()
	OnlineHub.session = net
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))
	if _demo.begins_with("home") or _demo == "settings":
		_home(net)
	elif _demo.begins_with("lobby"):
		_lobby(net)
	elif _demo.begins_with("battle"):
		_battle(net)


func _fill(net: OnlineFakes.FakeNet) -> void:
	Entitlement.reset_for_tests(true)
	net.fake_account.profile["name"] = "HANA"
	net.fake_friends.friends = [OnlineFakes.friend("f1", "ANNA"), OnlineFakes.friend("f2", "BO"), OnlineFakes.friend("f3", "CY KAI"),
			OnlineFakes.friend("f4", "DEV")]
	net.fake_friends.requests = [OnlineFakes.request("r1", "EMIL")]
	net.fake_friends.blocks = ["x1"]
	net.fake_friends.invites = [OnlineFakes.invite("inv1", "ANNA")]
	var now: int = net.clock.now_ms()
	net.fake_matches.list = [
		OnlineFakes.match_entry("m1", "playing", true, "ANNA", now - 4 * 60000),
		OnlineFakes.match_entry("m2", "playing", false, "BO", now - 3 * 3600000),
		OnlineFakes.match_entry("m3", "lobby", false, "HANA", now - 20 * 60000),
		OnlineFakes.match_entry("m4", "over", false, "CY KAI", now - 2 * 86400000),
	]
	var teams: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat("a", "A"), OnlineFakes.human_seat("b", "B"), OnlineFakes.cpu_seat(), OnlineFakes.cpu_seat()], {"teams": [0, 0, 1, 1]})
	var love: Dictionary = OnlineFakes.lobby_meta([OnlineFakes.human_seat("a", "A"), OnlineFakes.human_seat("b", "B")], {"mode": 1})
	net.fake_lobby.put_lobby("m1", teams)
	net.fake_lobby.put_lobby("m2", love)
	net.fake_lobby.put_lobby("m3", OnlineFakes.lobby_meta([OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), {"kind": "human"}]))
	OnlineHub.open_lobby_id = "m3"


func _home(net: OnlineFakes.FakeNet) -> void:
	_fill(net)
	SettingsStore.love_found = true
	if _demo == "home-name":
		SettingsStore.online_named = false
		net.fake_account.profile["name"] = ""
	elif _demo == "home-offline":
		net.start_result = NetResult.failure(NetError.Code.OFFLINE, "offline")
		net.fake_account.profile = {}
	elif _demo == "home-update":
		net.start_result = NetResult.failure(NetError.Code.PROTOCOL_MISMATCH, "protocol_mismatch")
	var s: OnlineScreen = (load("res://ui/online/online_screen.tscn") as PackedScene).instantiate()
	add_child(s)
	await get_tree().create_timer(0.4).timeout
	match _demo:
		"home-friends":
			s.show_tab(OnlineScreen.Tab.FRIENDS)
		"home-join":
			s.show_tab(OnlineScreen.Tab.JOIN)
			(s.get_tab_page(OnlineScreen.Tab.JOIN) as JoinTab).set_code("K7M2QX")
		"home-host":
			s.show_tab(OnlineScreen.Tab.HOST)
		"settings":
			var so: SettingsOverlay = SettingsOverlay.new()
			add_child(so)
			so.open()
			so.get_online_settings().open_panel()


func _lobby(net: OnlineFakes.FakeNet) -> void:
	_fill(net)
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"),
			OnlineFakes.cpu_seat(3, "CPU 3"), {"kind": "human"}, OnlineFakes.cpu_seat(2, "CPU 5")]
	var host_uid: String = OnlineFakes.ME if _demo == "lobby-host" else OnlineFakes.OTHER
	var meta: Dictionary = OnlineFakes.lobby_meta(seats, {"teams": [0, 0, 1, 1, 1], "theme": "ice_circuit", "rounds": 5}, host_uid)
	net.fake_lobby.put_lobby("lobby1", meta)
	OnlineHub.lobby_to_show = "lobby1"
	var s: LobbyScreen = (load("res://ui/online/lobby_screen.tscn") as PackedScene).instantiate()
	add_child(s)


func _battle(net: OnlineFakes.FakeNet) -> void:
	Entitlement.reset_for_tests(true)
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"), OnlineFakes.cpu_seat(2, "CPU")]
	var base: Dictionary = NetTestUtil.meta(seats, {"rounds": 3, "wind_max": 40}, {"liveSec": 60})
	var scratch: NetReplay = NetReplay.create(base)
	scratch.apply_entry({"kind": "ready", "tank": 0})
	scratch.apply_entry({"kind": "ready", "tank": 1})
	scratch.apply_entry(scratch.pending_cpu_entry())
	var first: int = scratch.state.current_tank
	var me: String = OnlineFakes.ME
	if _demo == "battle-waiting" or _demo == "battle-bubble" or _demo == "battle-dispute":
		me = OnlineFakes.ME if first != 0 else OnlineFakes.OTHER
	else:
		me = OnlineFakes.ME if first == 0 else OnlineFakes.OTHER
	if first == 2:
		scratch.apply_entry(scratch.pending_cpu_entry())
	var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(me, seats, {"rounds": 3, "wind_max": 40}, {"liveSec": 60})
	fm.meta["hostUid"] = OnlineFakes.ME
	for e: Dictionary in scratch.entries:
		fm.replay.apply_entry(e)
	while not fm.replay.pending_cpu_entry().is_empty():
		fm.replay.apply_entry(fm.replay.pending_cpu_entry())
	fm._set_stored_turn(fm.replay.expected_turn())
	fm._turn_raw["liveDeadline"] = fm.fixed_now + 37000
	var b: OnlineBattleController = (load("res://show/online/online_battle_scene.tscn") as PackedScene).instantiate()
	b.attach_match(fm)
	b.configure(3, 4242)
	add_child(b)
	await get_tree().create_timer(0.3).timeout
	if _demo == "battle-bubble":
		var seat: int = 0 if first != 0 else 1
		fm.message_received.emit(seat, 0, OnlineFakes.OTHER)
		fm.message_received.emit(1 - seat, 5, OnlineFakes.THIRD)
	elif _demo == "battle-dispute":
		fm.trigger_dispute("fingerprint_mismatch")
