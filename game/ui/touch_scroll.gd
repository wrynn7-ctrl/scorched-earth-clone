class_name TouchScroll
extends ScrollContainer
## A ScrollContainer made for fingers: a wide neon scrollbar and swipe-to-scroll with inertia.
##
## Scrollbar: track and grabber are BAR_DP wide (plus a transparent GAP_DP strip next to the
## content, which is part of the hit area), the grabber is never shorter than GRABBER_MIN_DP, and
## the sizes are dp-based so they are applied in code (apply_style) and again on every resize.
## ScrollContainer already shrinks its content by the bar's width, so nothing hides under it.
##
## Swipe: a drag that starts anywhere inside (also on a Button, which would otherwise swallow
## it) scrolls the content once the finger has moved more than TAP_SLOP_DP; a movement below that
## stays a tap and reaches the button untouched. When a drag begins the button's pending press is
## cancelled so lifting the finger does not "click" it. After a quick flick the content coasts.
## It works on the (emulated) mouse events every touch produces, so one path serves touch and mouse.

const BAR_DP: float = 22.0
const GAP_DP: float = 6.0
const GRABBER_MIN_DP: float = 56.0
const TAP_SLOP_DP: float = 10.0
## Inertia: speed decays as exp(-FRICTION * t); it stops below STOP_SPEED_DP per second.
const FRICTION: float = 3.0
const STOP_SPEED_DP: float = 40.0
const MAX_SPEED_DP: float = 4000.0
## A finger that rested this long before lifting does not fling.
const REST_MSEC: int = 90

enum State { IDLE, PENDING, DRAGGING, COASTING }

## False while something modal (a popup) sits on top of this list.
var drag_enabled: bool = true

var _state: State = State.IDLE
var _start: Vector2 = Vector2.ZERO
var _last: Vector2 = Vector2.ZERO
var _acc: Vector2 = Vector2.ZERO
var _vel: Vector2 = Vector2.ZERO
var _last_msec: int = 0


func _init() -> void:
	# The built-in finger drag would scroll a second time on the screen-touch events that
	# accompany the mouse events we handle.
	scroll_deadzone = 1000000
	set_process(false)


func _ready() -> void:
	apply_style()
	get_viewport().size_changed.connect(apply_style)


func _exit_tree() -> void:
	var vp: Viewport = get_viewport()
	if vp != null and vp.size_changed.is_connected(apply_style):
		vp.size_changed.disconnect(apply_style)


# ======================================================================================
# Scrollbar look
# ======================================================================================

## Total thickness of a bar (visible part + gap) in canvas units.
static func bar_thickness() -> float:
	return UiScale.dp(BAR_DP + GAP_DP)


func apply_style() -> void:
	style_bar(get_v_scroll_bar())
	style_bar(get_h_scroll_bar())


## Sizes and styles one scrollbar for touch (also usable on bars of other containers).
static func style_bar(bar: ScrollBar) -> void:
	var vertical: bool = bar is VScrollBar
	var w: float = UiScale.dp(BAR_DP)
	var gap: float = UiScale.dp(GAP_DP)
	bar.custom_minimum_size = Vector2(w + gap, 0.0) if vertical else Vector2(0.0, w + gap)
	var track: StyleBoxFlat = _bar_style(vertical, w, gap, Color(NeonPalette.CYAN, 0.10), Color(NeonPalette.CYAN, 0.35), 0.0, 0.0)
	var grab: StyleBoxFlat = _bar_style(vertical, w, gap, Color(NeonPalette.CYAN, 0.85), Color(1, 1, 1, 0.5), 0.45, 5.0)
	var grab_hl: StyleBoxFlat = _bar_style(vertical, w, gap, Color(0.45, 0.97, 1.0, 0.95), Color(1, 1, 1, 0.8), 0.6, 6.0)
	var grab_down: StyleBoxFlat = _bar_style(vertical, w, gap, Color(0.85, 1.0, 1.0, 1.0), Color.WHITE, 0.85, 9.0)
	# ScrollContainer shrinks its content by the bar's own minimum size, which only the track style's
	# content margin can raise (custom_minimum_size is not looked at there).
	if vertical:
		track.content_margin_left = w + gap
	else:
		track.content_margin_top = w + gap
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hl)
	bar.add_theme_stylebox_override("grabber_pressed", grab_down)
	# The grabber's minimum length comes from its style's content margins.
	for sb: StyleBoxFlat in [grab, grab_hl, grab_down]:
		var half: float = UiScale.dp(GRABBER_MIN_DP) * 0.5
		if vertical:
			sb.content_margin_top = half
			sb.content_margin_bottom = half
		else:
			sb.content_margin_left = half
			sb.content_margin_right = half


static func _bar_style(vertical: bool, w: float, gap: float, fill: Color, edge: Color, glow: float, glow_dp: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_border_width_all(maxi(1, roundi(UiScale.dp(1.0))))
	sb.border_color = edge
	sb.set_corner_radius_all(roundi(w * 0.5))
	sb.anti_aliasing = true
	# A negative expand margin keeps the strip next to the content empty.
	if vertical:
		sb.expand_margin_left = -gap
	else:
		sb.expand_margin_top = -gap
	if glow > 0.0:
		sb.shadow_color = Color(NeonPalette.CYAN, glow)
		sb.shadow_size = roundi(UiScale.dp(glow_dp))
	return sb


# ======================================================================================
# Swipe to scroll
# ======================================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_on_press(mb.position)
		else:
			_on_release()
	elif event is InputEventMouseMotion and (_state == State.PENDING or _state == State.DRAGGING):
		var mm: InputEventMouseMotion = event
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_state = State.IDLE  # the release went elsewhere
			return
		_on_motion(mm.position)


func _to_local_point(p: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * p


func _on_press(pos: Vector2) -> void:
	if _state == State.COASTING:
		_stop_coast()
	if not drag_enabled or not is_visible_in_tree() or not _can_scroll():
		return
	var local: Vector2 = _to_local_point(pos)
	if not Rect2(Vector2.ZERO, size).has_point(local) or _on_scrollbar(local) or _on_text_or_slider(pos):
		return
	_state = State.PENDING
	_start = pos
	_last = pos
	_vel = Vector2.ZERO
	_last_msec = Time.get_ticks_msec()


func _on_motion(pos: Vector2) -> void:
	if _state == State.PENDING:
		if pos.distance_to(_start) <= UiScale.dp(TAP_SLOP_DP):
			return
		_state = State.DRAGGING
		_cancel_presses(_start)
		_acc = Vector2(scroll_horizontal, scroll_vertical)
		_last = _start  # the slop distance is not lost: the content follows the finger from the press point
	var now: int = Time.get_ticks_msec()
	var dt: float = maxf(0.004, float(now - _last_msec) / 1000.0)
	var step: Vector2 = pos - _last
	_vel = _vel.lerp(step / dt, 0.4)
	_last = pos
	_last_msec = now
	_scroll_by(-step)


func _on_release() -> void:
	if _state == State.DRAGGING:
		var rested: bool = Time.get_ticks_msec() - _last_msec > REST_MSEC
		var cap: float = UiScale.dp(MAX_SPEED_DP)
		_vel = _vel.limit_length(cap)
		if not rested and _vel.length() > UiScale.dp(STOP_SPEED_DP):
			_state = State.COASTING
			set_process(true)
			return
	_state = State.IDLE


func _process(delta: float) -> void:
	if _state != State.COASTING:
		set_process(false)
		return
	_vel *= exp(-FRICTION * delta)
	var moved: Vector2 = _scroll_by(-_vel * delta)
	var blocked: bool = moved.is_zero_approx()  # hit the end
	if _vel.length() < UiScale.dp(STOP_SPEED_DP) or blocked:
		_stop_coast()


func _stop_coast() -> void:
	_state = State.IDLE
	_vel = Vector2.ZERO
	set_process(false)


## Moves the content by `d` canvas units (positive = further down/right); returns how far it really moved.
func _scroll_by(d: Vector2) -> Vector2:
	var before: Vector2 = _acc
	var max_v: float = maxf(0.0, get_v_scroll_bar().max_value - get_v_scroll_bar().page)
	var max_h: float = maxf(0.0, get_h_scroll_bar().max_value - get_h_scroll_bar().page)
	if vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_acc.y = clampf(_acc.y + d.y, 0.0, max_v)
		scroll_vertical = roundi(_acc.y)
	if horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_acc.x = clampf(_acc.x + d.x, 0.0, max_h)
		scroll_horizontal = roundi(_acc.x)
	return _acc - before


func _can_scroll() -> bool:
	if vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
			and get_v_scroll_bar().max_value - get_v_scroll_bar().page > 0.5:
		return true
	return horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED \
			and get_h_scroll_bar().max_value - get_h_scroll_bar().page > 0.5


func _on_scrollbar(local: Vector2) -> bool:
	var v: VScrollBar = get_v_scroll_bar()
	var h: HScrollBar = get_h_scroll_bar()
	return (v.visible and v.get_rect().has_point(local)) or (h.visible and h.get_rect().has_point(local))


## True when the press landed on something that has its own use for a drag.
func _on_text_or_slider(pos: Vector2) -> bool:
	for type_name: String in ["LineEdit", "TextEdit", "Slider"]:
		for n: Node in find_children("*", type_name, true, false):
			var c: Control = n as Control
			if c != null and c.is_visible_in_tree() and c.get_global_rect().has_point(pos):
				return true
	return false


## Clears the half-finished press of whichever button is under the finger, so it won't fire on release.
## (Toggling `disabled` is the one public way to reset BaseButton's press state.)
func _cancel_presses(pos: Vector2) -> void:
	for n: Node in find_children("*", "BaseButton", true, false):
		var b: BaseButton = n as BaseButton
		if b != null and not b.disabled and b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			b.disabled = true
			b.disabled = false


# --- accessors (tests, tools) ---

func is_dragging() -> bool:
	return _state == State.DRAGGING


func is_coasting() -> bool:
	return _state == State.COASTING
