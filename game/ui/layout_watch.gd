class_name LayoutWatch
extends Node
## Keeps a screen's dp-based layout (or a camera framing) in step with the real display. Android can report the
## window size, the safe area and the density late (after rotating to landscape) or in several
## steps, and the resize signal may fire before DisplayServer has the new numbers. So the
## callback runs on every resize signal, on the host's own `resized`, *and* whenever a cheap
## poll (4x per second) sees that any input of the layout changed.

const POLL_SECONDS: float = 0.25

var _host: Node = null
var _callback: Callable = Callable()
var _signature: String = ""
var _since_poll: float = 0.0
var _viewport: Viewport = null
## When true the host (a Control meant to cover the whole screen) is also checked every frame
## with LayoutGuard.fit().
var _guard: bool = false


## Hooks `callback` (usually the host's apply_scale) to every kind of resize. Call from _ready().
## `guard_rect` also makes the host re-assert full-screen coverage every frame (see LayoutGuard).
static func attach(host: Node, callback: Callable, guard_rect: bool = false) -> LayoutWatch:
	var w := LayoutWatch.new()
	w.name = "LayoutWatch"
	w._host = host
	w._callback = callback
	w._guard = guard_rect
	host.add_child(w)
	return w


func _ready() -> void:
	# Keep running behind a paused tree (pause menu, overlays).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport = _host.get_viewport()
	_viewport.size_changed.connect(_on_signal)
	var root: Window = get_tree().root
	if root != _viewport:
		root.size_changed.connect(_on_signal)
	if _host.has_signal("resized"):
		_host.connect("resized", _on_signal)
	_signature = _compute_signature()


func _process(delta: float) -> void:
	if _guard and _host is Control and LayoutGuard.fit(_host as Control):
		_run()  # the rect was wrong: dp layout inside it may be stale too
	_since_poll += delta
	if _since_poll < POLL_SECONDS:
		return
	_since_poll = 0.0
	if _compute_signature() != _signature:
		_run()


func _on_signal() -> void:
	_run()


func _run() -> void:
	_signature = _compute_signature()
	if _callback.is_valid():
		_callback.call()


## Everything the layout depends on. Cheap string, compared a few times per second.
func _compute_signature() -> String:
	return "%s|%s|%s|%s|%s|%s|%.3f" % [
		str(UiScale.window_px()), str(_viewport.get_visible_rect().size), str((_host as Control).size if _host is Control else Vector2.ZERO),
		str(UiScale.raw_safe_px()), str(UiScale.dpi()), str(UiScale.safe_insets()), UiScale.text_scale]
