class_name ShopFlow
extends Control
## The pass-and-play shop between rounds: for each player who is not ready yet, a hand-over
## screen ("PLAYER N - YOUR SHOP", tap to continue) and then that player's shop. READY submits
## a `ready` action and moves on; after the last READY it emits `all_ready` and the battle
## controller asks the simulation to start the round.

signal all_ready

var _state: MatchState = null
var _submit: Callable = Callable()
var _player: int = -1
var _handover: HandoverScreen = null
var _screen: ShopScreen = null
var _toast: Toast = null
var _tab: int = 0
var _select: String = ""


func _init() -> void:
	name = "ShopFlow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_screen = ShopScreen.new()
	_screen.ready_pressed.connect(_on_ready)
	_screen.message.connect(func(text: String) -> void: _toast.show_message(text))
	add_child(_screen)
	_handover = HandoverScreen.new()
	_handover.continued.connect(_on_continue)
	add_child(_handover)
	_toast = Toast.new()
	add_child(_toast)
	visible = false


func _ready() -> void:
	LayoutWatch.attach(self, func() -> void: LayoutGuard.fit(self), true)


## Starts the flow with the first player who is not ready. `start_player` (>= 0) picks a
## specific player and `skip_handover` jumps straight into their shop (screenshots, tests).
func open(state: MatchState, submit: Callable, start_player: int = -1, skip_handover: bool = false,
		tab: int = 0, select_id: String = "") -> void:
	_state = state
	_submit = submit
	_tab = tab
	_select = select_id
	_screen.setup(state, submit)
	visible = true
	_player = start_player if start_player >= 0 else first_unready()
	if _player < 0:
		all_ready.emit()
		return
	if skip_handover:
		_show_shop()
	else:
		_show_handover()


func close() -> void:
	visible = false
	_handover.hide_screen()
	_screen.visible = false
	_screen.close_popup()


## The lowest player id that has not pressed READY, or -1 when everyone has.
func first_unready() -> int:
	for t: TankState in _state.tanks:
		if not t.ready:
			return t.id
	return -1


func current_player() -> int:
	return _player


func is_showing_handover() -> bool:
	return visible and _handover.visible


func is_showing_shop() -> bool:
	return visible and _screen.visible


func get_screen() -> ShopScreen:
	return _screen


func get_handover() -> HandoverScreen:
	return _handover


func get_toast() -> Toast:
	return _toast


func _show_handover() -> void:
	_screen.visible = false
	_handover.show_player(_player)


func _show_shop() -> void:
	_handover.hide_screen()
	_screen.show_player(_player, _tab, _select)
	_tab = 0
	_select = ""


func _on_continue() -> void:
	_show_shop()


## READY: record it with the simulation, then hand over to the next player (or finish).
func _on_ready() -> void:
	var err: String = _submit.call({"kind": "ready", "tank": _player})
	if err != "" and err != "already_ready":
		_toast.show_message(ErrorText.message(err))
		return
	var next: int = first_unready()
	if next < 0:
		close()
		all_ready.emit()
		return
	_player = next
	_show_handover()
