class_name ShopFlow
extends Control
## The shop between rounds. Computer players shop first and instantly (CpuShop). Then, for each
## human who is not ready yet, a hand-over screen ("PLAYER N - YOUR SHOP", tap to continue) and
## that human's shop. Hand-overs only exist when two or more humans share the device: with one
## human (or none) there is no hand-over at all. READY submits a `ready` action and moves on;
## after the last READY it emits `all_ready` and the battle controller asks the simulation to
## start the round.

signal all_ready

var _state: MatchState = null
var _submit: Callable = Callable()
var _player: int = -1
var _handover: HandoverScreen = null
var _screen: ShopScreen = null
var _toast: Toast = null
var _unlock: UnlockScreen = null
var _bought: bool = false
var _tab: int = 0
var _select: String = ""
## What the CPUs bought when this flow opened: [{tank, level, items}] (see CpuShop.run).
var _cpu_buys: Array[Dictionary] = []


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
	_screen.locked_tapped.connect(_on_locked_tapped)
	_unlock = UnlockScreen.new()
	_unlock.set_in_match(true)
	_unlock.unlocked.connect(func() -> void: _bought = true)
	_unlock.closed.connect(_on_unlock_closed)
	add_child(_unlock)  # last child: it covers the shop and the item popup
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
	_cpu_buys = CpuShop.run(state, submit)
	_player = start_player if start_player >= 0 else first_unready()
	if _player < 0:
		all_ready.emit()
		return
	if skip_handover or not CpuShop.needs_handover(state):
		_show_shop()
	else:
		_show_handover()


func close() -> void:
	visible = false
	_unlock.close()
	_handover.hide_screen()
	_screen.visible = false
	_screen.close_popup()


## The lowest human player id that has not pressed READY, or -1 when everyone has (computer
## players never get a shop screen; CpuShop readies them).
func first_unready() -> int:
	for t: TankState in _state.tanks:
		if not t.ready and not CpuShop.is_cpu(_state, t.id):
			return t.id
	return -1


## What the computer players bought when the flow opened (empty if none shopped).
func get_cpu_purchases() -> Array[Dictionary]:
	return _cpu_buys


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


func get_unlock_screen() -> UnlockScreen:
	return _unlock


func _on_locked_tapped(kind: String, _id: String) -> void:
	_unlock.open_for(kind)


## A purchase made during a match applies from the NEXT match: the running match keeps the tier it
## started with (only Simulation changes a match, and a replay from its starting settings must
## reproduce it). The shop's locks therefore stay; tell the player once.
func _on_unlock_closed() -> void:
	if _bought:
		_bought = false
		_toast.show_message(tr("UNLOCK_NEXT_MATCH"))


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
	if CpuShop.needs_handover(_state):
		_show_handover()
	else:
		_show_shop()
