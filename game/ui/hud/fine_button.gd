class_name FineButton
extends Button
## Small precision button. Emits `stepped(multiplier)` once on press, then repeats while held
## (after HOLD_DELAY), speeding up the longer it is held: x1, then x5, then x10.

signal stepped(multiplier: int)

const HOLD_DELAY: float = 0.4
const REPEAT_INTERVAL: float = 0.07
const FAST_AFTER: int = 8
const FASTER_AFTER: int = 24

var _t: float = 0.0
var _next: float = HOLD_DELAY
var _repeats: int = 0
var _holding: bool = false


func _ready() -> void:
	theme_type_variation = &"FineButton"
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	button_down.connect(begin_hold)
	button_up.connect(end_hold)


func begin_hold() -> void:
	if disabled:
		return
	_holding = true
	_t = 0.0
	_next = HOLD_DELAY
	_repeats = 0
	stepped.emit(1)
	set_process(true)


func end_hold() -> void:
	_holding = false
	set_process(false)


func is_holding() -> bool:
	return _holding


func multiplier_for(repeat_count: int) -> int:
	if repeat_count >= FASTER_AFTER:
		return 10
	if repeat_count >= FAST_AFTER:
		return 5
	return 1


func _process(delta: float) -> void:
	if not _holding:
		set_process(false)
		return
	_t += delta
	while _t >= _next:
		stepped.emit(multiplier_for(_repeats))
		_repeats += 1
		_next += REPEAT_INTERVAL


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		end_hold()
