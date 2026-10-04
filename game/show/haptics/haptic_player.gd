class_name HapticPlayer
extends Node
## Plays vibration patterns (HapticMapper) on the phone, behind Settings > Vibration (ShowSettings.haptics).
##
## Godot 4.7: Input.vibrate_handheld(duration_ms: int = 500, amplitude: float = -1.0). The amplitude (0..1) is
## honoured on Android 8+ devices with an amplitude-capable motor and ignored elsewhere; on desktop and in
## headless runs the call does nothing. The VIBRATE permission is in the export presets.
##
## Rules:
##  - nothing while the setting is off, and nothing while the app is not focused (a pending pattern is
##    cancelled the moment focus is lost);
##  - rate limit so a multi-warhead weapon does not buzz: a new pattern of the same or lower priority is ignored
##    for LOCKOUT_MS after the last one started, and a budget of BUDGET_MS of vibration per second applies.
##    A higher priority pattern replaces what is running (a nuke cuts a small tick short). Rumble patterns
##    (priority 5) ignore the budget but still obey the priority rule;
##  - the first pulse of a pattern fires at once, the rest are scheduled from _process().
## The sink and the clock can be replaced, which is how the tests run without a device.

## A new pattern of the same or lower priority must wait this long after the last pattern started (ms).
const LOCKOUT_MS: int = 140
## At most this many ms of vibration per BUDGET_WINDOW_MS, except for rumble-class patterns.
const BUDGET_MS: int = 300
const BUDGET_WINDOW_MS: int = 1000
## Quiet time after a pattern ends before another may start (ms).
const GUARD_MS: int = 40

## Callable(duration_ms: int, amplitude: float). The default drives the phone.
var sink: Callable = Callable()
## Callable() -> int, a millisecond clock. The default is Time.get_ticks_msec.
var clock: Callable = Callable()
## False while the app is in the background or has lost focus (set from the notifications below, or by tests).
var focused: bool = true
## Counters for tests and debugging: patterns started and dropped (setting off, unfocused, rate limit).
var stats: Dictionary = {"started": 0, "dropped": 0, "pulses": 0}

var _queue: Array[Vector3] = []
var _next: int = 0
var _base_ms: int = 0
var _busy_until: int = -1
var _last_start: int = -1000000
var _cur_pri: int = 0
## Recent patterns for the budget: Vector2i(start_ms, on_time_ms).
var _recent: Array[Vector2i] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the pause menu must not freeze a heartbeat halfway
	set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			set_focused(false)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			set_focused(true)


func set_focused(on: bool) -> void:
	focused = on
	if not on:
		cancel()


## A timeline event (the same call the AudioDirector gets). Returns true when a pattern started.
func on_event(e: Dictionary, match_over: bool = false, love: bool = false) -> bool:
	var pattern: Dictionary = HapticMapper.for_event(e, match_over, love)
	return not pattern.is_empty() and play_pattern(pattern)


## Plays an AudioDirector sound key's pattern (for callers that have no event).
func play_key(key: String, love: bool = false) -> bool:
	var pattern: Dictionary = HapticMapper.for_sound(key, love)
	return not pattern.is_empty() and play_pattern(pattern)


func play_pattern(pattern: Dictionary) -> bool:
	if not ShowSettings.haptics or not focused:
		stats["dropped"] += 1
		return false
	var now: int = _now()
	var pri: int = pattern["pri"] as int
	var on_time: int = HapticMapper.on_time_ms(pattern)
	if not _allowed(pri, on_time, now):
		stats["dropped"] += 1
		return false
	cancel()  # a stronger pattern replaces the running one
	_cur_pri = pri
	_last_start = now
	_base_ms = now
	_busy_until = now + HapticMapper.length_ms(pattern) + GUARD_MS
	_recent.append(Vector2i(now, on_time))
	_queue.clear()
	for p: Vector3 in (pattern["pulses"] as Array):
		_queue.append(p)
	_next = 0
	stats["started"] += 1
	pump()
	if _next < _queue.size() and is_inside_tree():
		set_process(true)
	return true


## Fires every pulse that is due. _process() calls it; tests call it after moving their fake clock.
func pump() -> void:
	var elapsed: int = _now() - _base_ms
	while _next < _queue.size() and int(_queue[_next].x) <= elapsed:
		var p: Vector3 = _queue[_next]
		_next += 1
		_emit(maxi(int(p.y), 1), clampf(p.z, 0.0, 1.0))
	if _next >= _queue.size():
		set_process(false)


## Drops pending pulses (focus lost, or a stronger pattern arrives).
func cancel() -> void:
	_queue.clear()
	_next = 0
	set_process(false)


func is_busy() -> bool:
	return _next < _queue.size()


func _process(_delta: float) -> void:
	if not focused or not ShowSettings.haptics:
		cancel()
		return
	pump()


func _allowed(pri: int, on_time: int, now: int) -> bool:
	if now < _busy_until and pri <= _cur_pri:
		return false  # something at least as strong is still going
	if now - _last_start < LOCKOUT_MS and pri <= _cur_pri:
		return false
	if pri >= HapticMapper.PRI_RUMBLE:
		return true
	var used: int = 0
	var keep: Array[Vector2i] = []
	for r: Vector2i in _recent:
		if now - r.x < BUDGET_WINDOW_MS:
			used += r.y
			keep.append(r)
	_recent = keep
	return used + on_time <= BUDGET_MS


func _emit(duration_ms: int, amplitude: float) -> void:
	stats["pulses"] += 1
	if sink.is_valid():
		sink.call(duration_ms, amplitude)
	else:
		Input.vibrate_handheld(duration_ms, amplitude)


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()
