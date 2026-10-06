class_name OnlineBattleController
extends BattleController
## The battle screen of an online match (ARCHITECTURE sections 46 to 48): the same presentation as the local game,
## driven by an OnlineMatch instead of a local MatchSession.
##
## How it stays in step: the OnlineMatch owns the authoritative state and applies every log entry as it arrives. The
## battle keeps its own *display replay*, a fork of the match's NetReplay, and applies the same entries one at a time
## right before it plays their timeline. So `state` here is always exactly one entry ahead of the picture (like offline,
## where the session is one action ahead of the playback) and everything the base class does (HUD, shop, round summary,
## consistency check) keeps working. Entries that arrive while an animation runs wait in a queue. Entries that are
## catch-up (history after a reconnect) or a long backlog play in the base class' instant mode.
##
## Input: the controls are on only when the match says it is one of this phone's seats' turn and nothing is playing or
## being sent. A move goes out through `OnlineMatch.submit`; the entries come back through `entry_applied` and play like
## any other. CPU turns, timeouts and the opponents' shots all play from the log. The shop is private: the player shops
## on a copy and the whole visit is sent at READY (`submit_many`).

signal match_left

## How long a move may wait for the connection ("Offline, actions queued").
const SEND_WAIT_SEC: float = 120.0
## A pause between the steps of one entry (a CPU turn that raises a shield, then fires).
const STEP_GAP_TICKS: int = 30
## More entries than this waiting means we are far behind: play them instantly.
const BACKLOG_INSTANT: int = 6
## Shop actions per update (the backend allows 16 entries per write).
const SHOP_CHUNK: int = 12
const BUBBLE_LIFT: float = 124.0
const INFO_REFRESH_SEC: float = 0.25

var om: OnlineMatch = null

var _display: NetReplay = null
var _queue: Array[int] = []
var _catch_up: Dictionary = {}
var _pumping: bool = false
var _sending: bool = false
var _disputed: bool = false
var _ended_notice: bool = false
var _left: bool = false
var _shop_session: MatchSession = null
var _shop_waiting: bool = false
var _info_timer: float = 0.0
var _last_applied: int = -1

var _overlay: OnlineOverlay = null
var _notice: MatchNotice = null
var _confirm: OnlineConfirm = null
var _menu: PlayerMenu = null
var _players_panel: PlayersPanel = null
var _msg_button: Button = null


## Tests and the scene hand-off: the match to show (call before add_child()). Without it the match OnlineHub kept for
## the battle scene is used.
func attach_match(m: OnlineMatch) -> void:
	om = m


# ======================================================================================
# Setup
# ======================================================================================

func _build_support_nodes() -> void:
	super._build_support_nodes()
	var layer := CanvasLayer.new()
	layer.name = "OnlineLayer"
	layer.layer = 12
	add_child(layer)
	_overlay = OnlineOverlay.new()
	layer.add_child(_overlay)
	_overlay.tank_pos = _tank_screen_pos
	_overlay.message_chosen.connect(_on_message_chosen)
	_msg_button = Button.new()
	_msg_button.name = "Messages"
	_msg_button.accessibility_name = tr("NET_MSG_BUTTON")
	_msg_button.tooltip_text = tr("NET_MSG_BUTTON")
	var icon := MessageIcon.new(MessageDefs.Icon.BUBBLE)
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 8.0
	icon.offset_right = -8.0
	icon.offset_top = 8.0
	icon.offset_bottom = -8.0
	icon.tint = NeonPalette.CYAN
	_msg_button.add_child(icon)
	_msg_button.pressed.connect(open_messages)
	_hud.add_top_button(_msg_button)
	_notice = MatchNotice.new()
	_notice.chosen.connect(_on_notice_chosen)
	_overlay_layer.add_child(_notice)
	_confirm = OnlineConfirm.new()
	_overlay_layer.add_child(_confirm)
	_menu = PlayerMenu.new()
	_menu.toast.connect(_show_toast)
	_overlay_layer.add_child(_menu)
	_players_panel = PlayersPanel.new()
	_players_panel.player_tapped.connect(_on_player_tapped)
	_overlay_layer.add_child(_players_panel)
	_pause_overlay.leave_pressed.connect(ask_leave)
	_pause_overlay.end_pressed.connect(ask_end)
	_pause_overlay.players_pressed.connect(open_players)


## The online match replaces the local session: fork the match's replay for the display and show it.
func _start_match(_resume: bool = false) -> void:
	_autosave_path = ""  # an online match never touches the local save
	if om == null:
		om = OnlineHub.match_to_play
	OnlineHub.match_to_play = null
	if om == null:
		push_error("OnlineBattleController: no match to show")
		go_online.call_deferred()
		return
	PlayerLooks.reset()
	_display = om.replay.fork()
	_sync_seats()
	var sess: MatchSession = _display.session
	sess.meta = {"theme": _match_theme()}
	_pause_overlay.set_online(true, _is_host())
	_match_overlay.set_online(true)
	_connect_match()
	_adopt_session(sess, true)
	_refresh_online_ui()
	if om.is_disputed():
		_show_dispute(om.replay.dispute_reason)
	elif om.status == NetProtocol.STATUS_ABANDONED:
		_show_ended()


func _connect_match() -> void:
	om.entry_applied.connect(_on_entry)
	om.turn_changed.connect(_on_turn_changed)
	om.status_changed.connect(_on_status_changed)
	om.connection_changed.connect(_on_connection_changed)
	om.presence_changed.connect(_on_presence_changed)
	om.disputed.connect(_on_disputed)
	om.message_received.connect(_on_message_received)
	om.seats_changed.connect(_on_seats_changed)
	om.failed.connect(_on_match_failed)


func _disconnect_match() -> void:
	if om == null:
		return
	for pair: Array in [[om.entry_applied, _on_entry], [om.turn_changed, _on_turn_changed],
			[om.status_changed, _on_status_changed], [om.connection_changed, _on_connection_changed],
			[om.presence_changed, _on_presence_changed], [om.disputed, _on_disputed],
			[om.message_received, _on_message_received], [om.seats_changed, _on_seats_changed],
			[om.failed, _on_match_failed]]:
		var sig: Signal = pair[0]
		var cb: Callable = pair[1]
		if sig.is_connected(cb):
			sig.disconnect(cb)


func _exit_tree() -> void:
	_disconnect_match()
	if om != null and not _left:
		om.close()
	super._exit_tree()


func _match_theme() -> String:
	var settings: Variant = om.meta.get("settings", {})
	var id: String = (settings as Dictionary).get("theme", ThemeDefs.DEFAULT_ID) if typeof(settings) == TYPE_DICTIONARY else ThemeDefs.DEFAULT_ID
	return ThemeDefs.sanitize(id)


func _is_host() -> bool:
	return om != null and str(om.meta.get("hostUid", "")) == om.uid


## Seats changed (or the match was just opened): the display replay learns who is a computer now, and the names follow.
func _sync_seats() -> void:
	var seats: Array = om.replay.seats
	_display.set_seats(seats)
	var controllers: PackedInt32Array = _display.state.settings.controllers.duplicate()
	for i: int in range(mini(seats.size(), controllers.size())):
		if _display.seat_is_cpu(i) and controllers[i] == SimConstants.CTRL_HUMAN:
			controllers[i] = _display.seat_level(i)
	_display.state.settings.controllers = controllers
	var names := PackedStringArray()
	for i: int in range(seats.size()):
		names.append("" if _display.seat_is_cpu(i) else str((seats[i] as Dictionary).get("name", "")))
	PlayerNames.set_names(names)


## Only this phone's own tanks may wear a Skin Studio skin: opponents never see skins (ARCHITECTURE section 35).
func _apply_skins() -> void:
	var slot: int = 0
	for t: TankState in state.tanks:
		var skin: SkinData = null
		if om.my_seats.has(t.id):
			skin = SkinStore.skin_for_slot(slot)
			slot += 1
		_tank_views[t.id].set_skin(skin)


func is_cpu_tank(id: int) -> bool:
	return _display != null and _display.seat_is_cpu(id)


# ======================================================================================
# Entries in, timelines out
# ======================================================================================

func _on_entry(index: int, result: Dictionary) -> void:
	if _display == null or index < _display.count or _queue.has(index):
		return
	_catch_up[index] = result.get("catch_up", false) == true
	_queue.append(index)
	_pump()


## Plays the queued entries one after the other (an animation holds the rest back until it finishes).
func _pump() -> void:
	if _pumping or _display == null:
		return
	_pumping = true
	while not _queue.is_empty() and not _playing and not _disputed:
		var index: int = _queue.pop_front()
		if index < _display.count:
			continue
		while _display.count < index and _display.count < om.replay.entries.size() and not _disputed:
			_apply_entry(_display.count, true)  # a gap (should not happen): bring the display up to date at once
		if _disputed:
			break
		var instant: bool = _catch_up.get(index, false) == true or _queue.size() >= BACKLOG_INSTANT
		_catch_up.erase(index)
		_apply_entry(index, instant)
	_pumping = false
	_refresh_online_ui()


## Applies log entry `index` to the display replay and plays what it shows.
func _apply_entry(index: int, instant: bool) -> void:
	var entry: Dictionary = om.replay.entries[index]
	_sync_seats()
	var result: Dictionary = _display.apply_entry(entry)
	if not (result["ok"] as bool):
		_show_dispute(str(result["err"]))
		return
	_last_applied = index
	var steps: Array = result["steps"] as Array
	var starts_round: bool = false
	for step: Variant in steps:
		if ((step as Dictionary)["action"] as Dictionary).get("kind", "") == "start_round":
			starts_round = true
	if starts_round:
		_begin_round_ui()
	var events: Array[Dictionary] = timeline_of(steps)
	if events.is_empty():
		_after_silent_entry(result)
		return
	var was_instant: bool = _instant
	_instant = was_instant or instant
	_play(events)
	_instant = was_instant


## One flat timeline for the steps of an entry: shop steps have nothing to show, and each later step starts a little after
## the one before it ends (an AI turn is often two steps: a shield, then the shot).
static func timeline_of(steps: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var offset: int = 0
	for step: Variant in steps:
		var d: Dictionary = step as Dictionary
		var kind: String = (d["action"] as Dictionary).get("kind", "")
		if kind == "buy" or kind == "sell" or kind == "ready":
			continue
		var last: int = 0
		for e: Dictionary in d["events"] as Array[Dictionary]:
			var copy: Dictionary = e.duplicate()
			copy["tick"] = (e["tick"] as int) + offset
			last = maxi(last, copy["tick"] as int)
			out.append(copy)
		if not (d["events"] as Array[Dictionary]).is_empty():
			offset = last + STEP_GAP_TICKS
	return out


## An entry with nothing to animate (a shop visit, a timeout that ended the match).
func _after_silent_entry(result: Dictionary) -> void:
	if (result["over"] as bool) and state.phase != SimConstants.PHASE_MATCH_OVER:
		_show_match_over()  # the match was ended by a timeout: show the standings as they are
	elif state.phase == SimConstants.PHASE_SHOP and _shop_waiting:
		_show_shop_wait()


func _finish_playback() -> void:
	super._finish_playback()
	_pump()


# --- the base class' computer players and local session are not used online -------------------------------------

func _run_cpu_shop() -> void:
	pass


## A computer's turn: the banner and a locked HUD; the turn itself comes from the log (an `auto` entry).
func _begin_cpu_turn(id: int) -> void:
	_set_busy(true)
	_preview.hide_preview()
	_hud.show_cpu_turn(id, _display.seat_level(id), true)
	_hud.set_angle_tenths(_aim_angle[id])
	_hud.set_power(_aim_power[id])
	_refresh_loadout(id)


func _cpu_step(_delta: float, _force: bool = false) -> bool:
	return false


func autosave_now() -> bool:
	return false


func restart_match() -> void:
	pass


## The round starts because the log says so (the last READY entry): show the field like `_begin_round` does, without
## asking the simulation (the display replay already started it).
func _begin_round() -> void:
	_begin_round_ui()


func _begin_round_ui() -> void:
	_shop_waiting = false
	_overlay.set_waiting("")
	_shop.close()
	_round_overlay.close()
	_hud.visible = true
	_world.visible = true
	_round_money.fill(0)
	shop_finished.emit()


## The big "NAME'S TURN" banner only for this phone's own seats (it is also the hand-over for a shared phone).
func _announce_turn(id: int, announce: bool) -> void:
	var key: Array[int] = [state.round_index, state.turn_number, id]
	var repeat: bool = key == _announced_turn
	_announced_turn = key
	if not announce or repeat or _instant or state.phase != SimConstants.PHASE_AIM or not state.tanks[id].alive:
		return
	if om.my_seats.has(id):
		_hud.show_big_turn(id, PlayerNames.label(id))


## The money and weapon of one of this phone's seats stay on the HUD while an opponent plays.
func _refresh_loadout(id: int) -> void:
	var seat: int = id
	if not om.my_seats.has(id) and not om.my_seats.is_empty():
		seat = om.my_seats[0]
	super._refresh_loadout(seat)


# ======================================================================================
# Input
# ======================================================================================

## True when this phone may act now (see the class comment).
func may_act() -> bool:
	if om == null or _disputed or _ended_notice or _sending or _playing or not _queue.is_empty():
		return false
	if state == null or state.phase != SimConstants.PHASE_AIM:
		return false
	return om.is_my_turn() and om.my_seats.has(state.current_tank)


func _set_busy(b: bool, quiet: bool = false) -> void:
	var lock: bool = b
	if not lock and om != null and state != null and state.phase == SimConstants.PHASE_AIM and not may_act():
		lock = true
	super._set_busy(lock, quiet)


## Unlocks the controls when it has become this phone's turn (the stored turn can arrive after the entries).
func _refresh_input_lock() -> void:
	if state == null or _playing or state.phase != SimConstants.PHASE_AIM:
		return
	if is_cpu_tank(state.current_tank):
		return
	_set_busy(false)
	_request_preview()


## A move, shot or item: checked against the display state, then sent. The result comes back as a log entry.
func _submit_now(action: Dictionary) -> String:
	if om == null:
		return "no_match"
	var a: Dictionary = Simulation.normalize_action(action)
	if not om.my_seats.has(a.get("tank", -1)):
		_show_toast(tr("ERR_NOT_YOUR_TURN"))
		return "not_your_seat"
	var err: String = Simulation.validate_action(state, a)
	if err != "":
		_show_toast(ErrorText.message(err))
		return err
	_send(a)
	return ""


func _send(a: Dictionary) -> void:
	_sending = true
	_set_busy(true)
	_preview.hide_preview()
	_refresh_online_ui()
	var r: NetResult = await om.submit(a, SEND_WAIT_SEC)
	_sending = false
	if not is_inside_tree():
		return
	if not r.ok:
		_show_toast(failure_text(r))
	_refresh_input_lock()
	_refresh_online_ui()
	_pump()


## What to tell the player about a refused move.
static func failure_text(r: NetResult) -> String:
	if (r.code == NetError.Code.ILLEGAL_ACTION or r.code == NetError.Code.STALE) and r.reason != "" and r.reason != "contention":
		var key: String = "ERR_" + r.reason.to_upper()
		if TranslationServer.translate(StringName(key)) != key:
			return ErrorText.message(r.reason)
	if r.is_transient():
		return TranslationServer.translate(&"NET_BATTLE_RESEND")
	return OnlineText.error(r)


# ======================================================================================
# The shop
# ======================================================================================

func _open_shop() -> void:
	_set_busy(true)
	_hud.visible = false
	_world.visible = false
	_preview.hide_preview()
	_shop_waiting = false
	var mine: Array[int] = []
	for id: int in om.my_seats:
		if not state.tanks[id].ready:
			mine.append(id)
	if mine.is_empty():
		_show_shop_wait()
		return
	_overlay.set_waiting("")
	var fork: MatchState = state.duplicate_state()
	_shop_session = MatchSession.new()
	_shop_session.state = fork
	_shop.open_online(fork, _shop_local_submit, om.my_seats)


func _shop_local_submit(action: Dictionary) -> String:
	var res: Dictionary = _shop_session.submit(action)
	return res["err"] as String


## READY of the last seat of this phone: the whole visit goes to the match in one go.
func _on_shop_all_ready() -> void:
	_shop.close()
	_send_shop_visit()


func _send_shop_visit() -> void:
	var actions: Array[Dictionary] = compact_shop_actions(_shop_session.actions, state)
	_shop_waiting = true
	_show_shop_wait()
	var start: int = 0
	while start < actions.size():
		var chunk: Array = actions.slice(start, start + SHOP_CHUNK)
		start += SHOP_CHUNK
		var r: NetResult = await om.submit_many(chunk, SEND_WAIT_SEC)
		if not is_inside_tree():
			return
		if not r.ok:
			_show_toast(failure_text(r))
			_open_shop()  # reopen with the real state: what already went through is in it
			return
	_pump()


## Consecutive identical buys or sells become one action with the summed quantity, so a long shop visit stays within the
## backend's 16 entries per update. Only used when the shorter list is still legal from `from_state`.
static func compact_shop_actions(actions: Array[Dictionary], from_state: MatchState) -> Array[Dictionary]:
	var merged: Array[Dictionary] = []
	for a: Dictionary in actions:
		var kind: String = a.get("kind", "")
		if not merged.is_empty() and (kind == "buy" or kind == "sell"):
			var last: Dictionary = merged[merged.size() - 1]
			if last.get("kind", "") == kind and last.get("tank", -1) == a.get("tank", -2) and last.get("item", "") == a.get("item", "x"):
				var combined: Dictionary = last.duplicate()
				combined["qty"] = (last["qty"] as int) + (a["qty"] as int)
				if (combined["qty"] as int) <= 99:
					merged[merged.size() - 1] = combined
					continue
		merged.append(a.duplicate())
	if merged.size() == actions.size():
		return merged
	var probe: MatchState = from_state.duplicate_state()
	for a2: Dictionary in merged:
		var norm: Dictionary = Simulation.normalize_action(a2)
		if Simulation.validate_action(probe, norm) != "":
			return actions
		Simulation.apply_action(probe, norm)
	return merged


## "Waiting for the others to finish shopping" with the names of the people who still have to press READY.
func _show_shop_wait() -> void:
	var names: PackedStringArray = PackedStringArray()
	for t: TankState in state.tanks:
		if not t.ready and not is_cpu_tank(t.id):
			names.append(PlayerNames.label(t.id))
	_overlay.set_waiting(tr("NET_WAIT_SHOP"), ", ".join(names))
	_hud.visible = false


# ======================================================================================
# Status, indicator, timer
# ======================================================================================

func _on_turn_changed(_turn: Dictionary) -> void:
	_refresh_input_lock()
	_refresh_online_ui()


func _on_connection_changed(_c: int) -> void:
	_refresh_online_ui()


func _on_presence_changed(_uid: String, _online: bool) -> void:
	_refresh_online_ui()


func _on_match_failed(code: int, reason: String) -> void:
	if code == NetError.Code.PROTOCOL_MISMATCH:
		_show_update()
	elif code != NetError.Code.CLOSED:
		push_warning("OnlineBattleController: background write failed (%d %s)" % [code, reason])


func _on_status_changed(status: String) -> void:
	if status == NetProtocol.STATUS_ABANDONED:
		_show_ended()


func _on_seats_changed(_seats: Array) -> void:
	if _display == null:
		return
	_sync_seats()
	for t: TankState in state.tanks:
		_tank_views[t.id].set_name_tag(PlayerNames.typed(t.id) if not is_cpu_tank(t.id) else "")
	_refresh_online_ui()


func _process(delta: float) -> void:
	super._process(delta)
	if om == null or _overlay == null:
		return
	_info_timer -= delta
	var tag: Control = _hud.get_sudden_tag()
	_overlay.strip_extra = tag.size.y + UiScale.dp(4.0) if tag.visible else 0.0
	_update_timer_ring()
	if _info_timer <= 0.0:
		_info_timer = INFO_REFRESH_SEC
		_refresh_online_ui()


func _update_timer_ring() -> void:
	var live: bool = state != null and state.phase == SimConstants.PHASE_AIM and om.status == NetProtocol.STATUS_PLAYING \
			and not _disputed
	var total: float = float(om.replay.timers.get("liveSec", 0))
	_overlay.set_timer(om.live_seconds_left() if live else -1.0, total)


## The indicator pill and the "Waiting for NAME" text.
func _refresh_online_ui() -> void:
	if om == null or _overlay == null or state == null:
		return
	var turn: Dictionary = om.turn_info()
	var waiting_name: String = ""
	var conn: int = OnlineOverlay.Conn.LIVE
	match om.connection:
		OnlineMatch.Connection.RECONNECTING:
			conn = OnlineOverlay.Conn.RECONNECTING
		OnlineMatch.Connection.OFFLINE:
			conn = OnlineOverlay.Conn.OFFLINE
		OnlineMatch.Connection.CLOSED:
			conn = OnlineOverlay.Conn.CLOSED
		_:
			if state.phase == SimConstants.PHASE_AIM and not is_cpu_tank(state.current_tank) and not om.my_seats.has(state.current_tank):
				conn = OnlineOverlay.Conn.WAITING
				waiting_name = PlayerNames.label(state.current_tank)
	_overlay.set_connection(conn, waiting_name)
	_refresh_waiting_text(turn, waiting_name)


func _refresh_waiting_text(turn: Dictionary, waiting_name: String) -> void:
	if _disputed or _ended_notice:
		_overlay.set_waiting("")
	elif _shop_waiting and state.phase == SimConstants.PHASE_SHOP:
		return  # the shop text is set when the shop closes
	elif waiting_name != "" and not _sending and not _playing:
		# The indicator already says "Waiting for NAME"; this text adds that they are away (no live game to expect).
		var holder: String = str(turn.get("uid", ""))
		var away: bool = holder != "" and holder != NetProtocol.UID_ANY and holder != NetProtocol.UID_CPU and not om.is_online(holder)
		if away:
			_overlay.set_waiting(tr("NET_WAIT_TITLE") % waiting_name, tr("NET_WAIT_AWAY") % waiting_name)
		else:
			_overlay.set_waiting("")
	elif _sending:
		_overlay.set_waiting(tr("NET_BATTLE_QUEUED") if om.connection != OnlineMatch.Connection.LIVE else tr("NET_BATTLE_SENDING"))
	elif state.phase != SimConstants.PHASE_SHOP:
		_overlay.set_waiting("")


# ======================================================================================
# Messages
# ======================================================================================

func open_messages() -> void:
	if om == null or om.my_seats.is_empty():
		return
	_overlay.open_picker()


## The seat that speaks: the one whose turn it is when that is one of this phone's, else its first.
func message_seat() -> int:
	if om.my_seats.has(state.current_tank):
		return state.current_tank
	return om.my_seats[0] if not om.my_seats.is_empty() else -1


func _on_message_chosen(msg: int) -> void:
	var r: NetResult = await om.send_message(msg, message_seat())
	if not r.ok and is_inside_tree():
		_show_toast(OnlineText.error(r))


func _on_message_received(seat: int, msg: int, uid: String) -> void:
	if OnlineHub.is_muted(uid) or not MessageDefs.is_valid(msg) or seat < 0 or seat >= _tank_views.size():
		return
	_overlay.show_bubble(seat, msg, PlayerLooks.color(seat))


func _tank_screen_pos(seat: int) -> Vector2:
	if seat < 0 or seat >= _tank_views.size() or not _tank_views[seat].visible or not _world.visible:
		return Vector2(-1.0, -1.0)
	return get_viewport().get_canvas_transform() * (_tank_views[seat].position + Vector2(0.0, -BUBBLE_LIFT))


# ======================================================================================
# Notices, leaving
# ======================================================================================

func _on_disputed(reason: String, _index: int) -> void:
	_show_dispute(reason)


## The copies of the game disagree: play stops (the base class' `_playing` is cut off) and a full-screen message offers
## LEAVE (and, for the host, ending the match for everybody).
func _show_dispute(reason: String) -> void:
	if _disputed:
		return
	_disputed = true
	_queue.clear()
	_set_busy(true)
	_overlay.set_waiting("")
	var buttons: Array = [{"id": "leave", "label": tr("NET_DISPUTE_LEAVE")}]
	if _is_host():
		buttons.append({"id": "end", "label": tr("NET_PAUSE_END")})
	_notice.show_notice(tr("NET_DISPUTE_TITLE"), "%s\n(%s)" % [tr("NET_DISPUTE_TEXT"), reason], buttons)


func is_disputed_shown() -> bool:
	return _disputed and _notice.is_open()


func _show_ended() -> void:
	if _ended_notice or _disputed:
		return
	_ended_notice = true
	_set_busy(true)
	_overlay.set_waiting("")
	_notice.show_notice(tr("NET_ABANDONED_TITLE"), tr("NET_ABANDONED_TEXT"), [{"id": "leave", "label": tr("NET_BACK_TO_ONLINE")}])


func _show_update() -> void:
	_disputed = true
	_set_busy(true)
	_notice.show_notice(tr("NET_UPDATE_TITLE"), tr("NET_UPDATE_TEXT"), [{"id": "leave", "label": tr("NET_BACK_TO_ONLINE")}])


func _on_notice_chosen(id: String) -> void:
	if id == "end":
		ask_end()
	else:
		go_online()


func get_notice() -> MatchNotice:
	return _notice


func get_confirm() -> OnlineConfirm:
	return _confirm


func get_online_overlay() -> OnlineOverlay:
	return _overlay


func get_message_button() -> Button:
	return _msg_button


func get_players_panel() -> PlayersPanel:
	return _players_panel


func get_player_menu() -> PlayerMenu:
	return _menu


func get_display_replay() -> NetReplay:
	return _display


func queue_size() -> int:
	return _queue.size()


func is_sending() -> bool:
	return _sending


## Android Back: the top-most online dialog goes first (a question is answered "no", never "yes"), then the base class'
## dialogs; only with nothing open does Back open the pause menu.
func _on_back_request() -> void:
	if _confirm != null and _confirm.is_open():
		_confirm.close()
	elif _menu != null and _menu.is_open():
		_menu.close()
	elif _players_panel != null and _players_panel.is_open():
		_players_panel.close()
	elif _overlay != null and _overlay.get_picker().is_open():
		_overlay.get_picker().close()
	else:
		super._on_back_request()


func open_pause() -> void:
	# The network keeps running behind the menu, so the tree is never paused online.
	if is_paused():
		return
	_pause_overlay.open_for(_displayed_round_number(), state.settings.rounds)
	_preview.hide_preview()


func open_players() -> void:
	var friends: Array = []
	var session: NetSession = OnlineHub.session
	if session != null:
		friends = session.friends.friends
	_pause_overlay.close_now()
	_players_panel.open_for(om.replay.seats, om.my_seats, state.settings.teams if has_teams() else PackedInt32Array(),
			om.is_online, friends)


func _on_player_tapped(info: Dictionary) -> void:
	_menu.open_for(OnlineHub.session, _with_match_id(info))


## The menu's ADD FRIEND needs the match both players are in: say it instead of letting the menu look for it.
func _with_match_id(info: Dictionary) -> Dictionary:
	var out: Dictionary = info.duplicate()
	if om != null and om.match_id != "":
		out["match_id"] = om.match_id
	return out


func ask_leave() -> void:
	_pause_overlay.close_now()
	_confirm.ask(tr("NET_LEAVE_Q"), do_leave, tr("NET_PAUSE_LEAVE"))


func ask_end() -> void:
	_pause_overlay.close_now()
	_confirm.ask(tr("NET_END_Q"), do_end, tr("NET_PAUSE_END"))


## Gives the seats up (the computer plays them from now on) and goes back to the Online home.
func do_leave() -> void:
	var session: NetSession = OnlineHub.session
	if session != null and om != null:
		await session.lobby.leave(om.match_id)
	go_online()


## The host ends the match for everybody.
func do_end() -> void:
	if om != null:
		await om.abandon()
	go_online()


## Back to the Online home. The match stays in "Your matches" (nothing is given up).
func go_online() -> void:
	if _left:
		return
	_left = true
	_disconnect_match()
	if om != null:
		om.close()
	match_left.emit()
	if is_inside_tree():
		OnlineHub.go_online(get_tree())


func quit_to_title() -> void:
	close_pause()
	go_online()


func _show_match_over() -> void:
	_match_overlay.set_online(true)
	if _love_overlay != null:
		_love_overlay.set_online(true)
	super._show_match_over()
	_overlay.set_waiting("")
	_overlay.set_timer(-1.0, 0.0)
