extends OnlineTestBase
## Layout rect checks for the online screens from 16:9 to 21:9 phones and 4:3 / 16:10 tablets, also at 150% text: every
## screen fills the visible area, nothing sticks out of it, and every button is at least 48 dp tall.

const TOL: float = 2.0

# [window px, dpi, label]
const CASES: Array = [
	[Vector2(1920, 1080), 420.0, "16:9 phone"],
	[Vector2(2340, 1080), 500.0, "19.5:9 phone"],
	[Vector2(3360, 1440), 450.0, "21:9 phone"],
	[Vector2(2048, 1536), 264.0, "4:3 tablet"],
	[Vector2(2560, 1600), 280.0, "16:10 tablet"],
]

var _net: OnlineFakes.FakeNet = null


func before_each() -> void:
	super.before_each()
	_net = OnlineFakes.net()
	OnlineHub.session = _net
	OnlineHub.set_services(PushService.new(PushFake.new()), GoogleSignIn.new(GoogleSignInFake.new()),
			ShareService.new(ShareFake.new()), DeepLinks.new(ShareFake.new()))
	Entitlement.reset_for_tests(true)
	SettingsStore.love_found = true
	_net.fake_friends.friends = [OnlineFakes.friend("f1", "ANNA"), OnlineFakes.friend("f2", "BO KAI"), OnlineFakes.friend("f3", "CY")]
	_net.fake_friends.requests = [OnlineFakes.request("r1", "EMIL")]
	_net.fake_friends.invites = [OnlineFakes.invite("i1", "ANNA")]
	_net.fake_friends.blocks = ["x1"]
	_net.fake_matches.list = [OnlineFakes.match_entry("m1", "playing", true, "ANNA", 5), OnlineFakes.match_entry("m2", "playing", false, "BO", 4),
			OnlineFakes.match_entry("m3", "over", false, "CY", 3)]


func _window(win: Vector2, dpi: float) -> SubViewport:
	UiScale.dpi_override = dpi
	UiScale.window_px_override = win
	var vis: Vector2 = UiScale.visible_size(win)
	var vp := SubViewport.new()
	vp.size = Vector2i(roundi(vis.x), roundi(vis.y))
	vp.disable_3d = true
	add_child_autofree(vp)
	return vp


func _inside_scroll(c: Control) -> bool:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


## Controls that stick out of the visible area, and buttons that are too small to hit.
func _problems(root: Node, vis: Vector2, label: String) -> Array[String]:
	var out: Array[String] = []
	var area := Rect2(Vector2.ZERO, vis).grow(TOL)
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c is Toast or c is LockBadge or c.size == Vector2.ZERO:
			continue
		var r: Rect2 = c.get_global_rect()
		if _inside_scroll(c):
			if r.position.x < area.position.x or r.end.x > area.end.x:
				out.append("%s: %s sticks out sideways %s" % [label, c.get_path(), r])
		elif not area.encloses(r):
			out.append("%s: %s outside the screen %s (visible %s)" % [label, c.get_path(), r, vis])
		if c is BaseButton and not (c is TeamChip) and c.size.y < UiScale.touch() - 1.5 and (c as BaseButton).get_parent() != null:
			out.append("%s: button %s is %.0f px tall, less than 48 dp (%.0f)" % [label, c.name, c.size.y, UiScale.touch()])
	return out


func _check(root: Node, vis: Vector2, label: String) -> void:
	var problems: Array[String] = _problems(root, vis, label)
	assert_eq(problems.size(), 0, "\n".join(problems))


func test_the_online_home_fits_every_screen() -> void:
	for case: Array in CASES:
		for text: int in [100, 150]:
			ShowSettings.set_text_size(text)
			var vp: SubViewport = _window(case[0] as Vector2, case[1] as float)
			var s: OnlineScreen = (load("res://ui/online/online_screen.tscn") as PackedScene).instantiate()
			vp.add_child(s)
			await settle(4)
			var label: String = "%s %d%%" % [case[2], text]
			assert_eq(s.get_global_rect(), Rect2(Vector2.ZERO, Vector2(vp.size)), label + " fills the screen")
			for tab: int in range(4):
				s.show_tab(tab)
				await settle(3)
				_check(s, Vector2(vp.size), "%s tab %d" % [label, tab])
			s.queue_free()
			await settle()


func test_the_gates_fit() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _window(case[0] as Vector2, case[1] as float)
		_net.start_result = NetResult.failure(NetError.Code.OFFLINE, "offline")
		var s: OnlineScreen = (load("res://ui/online/online_screen.tscn") as PackedScene).instantiate()
		vp.add_child(s)
		await settle(4)
		_check(s, Vector2(vp.size), "%s offline" % case[2])
		s.show_gate(OnlineScreen.Gate.NAME)
		await settle(3)
		_check(s, Vector2(vp.size), "%s name" % case[2])
		s.queue_free()
		_net.start_result = null
		await settle()


func _lobby(vp: SubViewport, host: bool) -> LobbyScreen:
	var seats: Array = [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA"),
			OnlineFakes.cpu_seat(3, "CPU 3"), {"kind": "human"}, OnlineFakes.cpu_seat(2, "CPU 5"), OnlineFakes.cpu_seat(1, "CPU 6")]
	var host_uid: String = OnlineFakes.ME if host else OnlineFakes.OTHER
	_net.fake_lobby.put_lobby("lobby1", OnlineFakes.lobby_meta(seats, {"teams": [0, 0, 1, 1, 1, 0], "theme": "ice_circuit"}, host_uid))
	OnlineHub.lobby_to_show = "lobby1"
	var s: LobbyScreen = (load("res://ui/online/lobby_screen.tscn") as PackedScene).instantiate()
	vp.add_child(s)
	return s


func test_the_lobby_fits_every_screen_for_host_and_joiner() -> void:
	for case: Array in CASES:
		for text: int in [100, 150]:
			ShowSettings.set_text_size(text)
			for host: bool in [true, false]:
				var vp: SubViewport = _window(case[0] as Vector2, case[1] as float)
				var s: LobbyScreen = _lobby(vp, host)
				await settle(5)
				_check(s, Vector2(vp.size), "%s %d%% %s" % [case[2], text, "host" if host else "joiner"])
				s.queue_free()
				await settle()


func test_the_lobby_start_button_stays_on_screen_with_big_text() -> void:
	ShowSettings.set_text_size(150)
	var vp: SubViewport = _window(Vector2(1920, 1080), 420.0)
	var s: LobbyScreen = _lobby(vp, true)
	await settle(5)
	var r: Rect2 = s.get_start_button().get_global_rect()
	assert_lte(r.end.y, float(vp.size.y) + TOL)
	assert_lte(r.end.x, float(vp.size.x) + TOL)


func test_the_online_overlay_fits_with_every_element_showing() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _window(case[0] as Vector2, case[1] as float)
		var o := OnlineOverlay.new()
		vp.add_child(o)
		await settle(3)
		o.set_connection(OnlineOverlay.Conn.WAITING, "WWWWWWWWWWWW")
		o.set_timer(42.0, 60.0)
		o.set_waiting("Waiting for WWWWWWWWWWWW…", "WWWWWWWWWWWW is away. You get a notification when it is your turn.")
		o.tank_pos = func(_seat: int) -> Vector2: return Vector2(vp.size) * 0.5
		o.show_bubble(0, 0, Color.WHITE)
		o.show_bubble(1, 5, Color.WHITE)
		o.open_picker()
		await settle(3)
		_check(o, Vector2(vp.size), str(case[2]))
		o.queue_free()
		await settle()


func test_the_message_picker_buttons_are_touch_sized() -> void:
	phone()
	var p := MessagePicker.new()
	add_child_autofree(p)
	p.open()
	await settle(3)
	for i: int in range(8):
		assert_gte(p.get_button(i).size.y, UiScale.touch() - 1.0)
		assert_gte(p.get_button(i).size.x, UiScale.touch() - 1.0)


func test_the_battle_hud_with_the_online_additions_fits() -> void:
	for case: Array in CASES:
		var vp: SubViewport = _window(case[0] as Vector2, case[1] as float)
		var fm: OnlineFakes.FakeMatch = OnlineFakes.match_for(OnlineFakes.ME, [OnlineFakes.human_seat(OnlineFakes.ME, "HANA"), OnlineFakes.human_seat(OnlineFakes.OTHER, "ANNA")])
		fm.replay.apply_entry({"kind": "ready", "tank": 0})
		fm.replay.apply_entry({"kind": "ready", "tank": 1})
		fm._set_stored_turn(fm.replay.expected_turn())
		var b: OnlineBattleController = (load("res://show/online/online_battle_scene.tscn") as PackedScene).instantiate()
		b.attach_match(fm)
		b.configure(3, 4242, true)
		vp.add_child(b)
		await settle(4)
		var vis: Vector2 = Vector2(vp.size)
		var hud: BattleHud = b.get_hud()
		var msg: Rect2 = b.get_message_button().get_global_rect()
		var pause: Rect2 = hud.get_pause_button().get_global_rect()
		assert_true(Rect2(Vector2.ZERO, vis).grow(TOL).encloses(msg), "%s: the message button is on screen %s" % [case[2], msg])
		assert_false(msg.intersects(pause.grow(-2.0)), "%s: it does not cover the pause button" % case[2])
		assert_gte(msg.size.y, UiScale.touch() - 1.0, "%s: 48 dp" % case[2])
		var o: OnlineOverlay = b.get_online_overlay()
		var strip: Rect2 = o.get_strip().get_global_rect()
		var top_row: Rect2 = hud.get_top_row().get_global_rect()
		assert_false(strip.intersects(top_row.grow(-2.0)), "%s: the indicator sits under the top row" % case[2])
		b.queue_free()
		await settle()
