class_name FineButton
extends Button
## Small precision button. Emits `stepped(multiplier)` once on press, then repeats while held
## (after HOLD_DELAY), speeding up the longer it is held: x1, then x5, then x10.

signal stepped(multiplier: int)

## Icon drawn instead of text. NONE keeps the plain text button (power +-1).
enum Arrow { NONE, UP, DOWN }

const HOLD_DELAY: float = 0.4
const REPEAT_INTERVAL: float = 0.07
const FAST_AFTER: int = 8
const FASTER_AFTER: int = 24

## Set before or after entering the tree; redraws immediately.
var arrow: int = Arrow.NONE:
	set(v):
		arrow = v
		queue_redraw()

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


func get_arrow() -> int:
	return arrow


## Procedural neon arrow: stroked shaft + filled head, with a wider translucent glow pass.
## Mirrors the wind arrow's look; colour follows the button state (dim when disabled).
func _draw() -> void:
	if arrow == Arrow.NONE:
		return
	var col: Color = _arrow_color()
	var c: Vector2 = size * 0.5
	var h: float = minf(size.y * 0.56, size.x * 0.56)  # total arrow height
	var dir: float = -1.0 if arrow == Arrow.UP else 1.0  # screen-space y direction of the tip
	var tip: Vector2 = c + Vector2(0.0, dir * h * 0.5)
	var tail: Vector2 = c - Vector2(0.0, dir * h * 0.5)
	var head: float = h * 0.46
	var thick: float = maxf(3.0, h * 0.16)
	var base: Vector2 = tip - Vector2(0.0, dir * head)
	var shaft_end: Vector2 = tip - Vector2(0.0, dir * head * 0.6)
	var tri := PackedVector2Array([tip, base + Vector2(-head * 0.8, 0.0), base + Vector2(head * 0.8, 0.0)])
	var glow := PackedVector2Array([
		tip + Vector2(0.0, dir * thick * 0.9),
		base + Vector2(-head * 0.8 - thick, -dir * thick * 0.5),
		base + Vector2(head * 0.8 + thick, -dir * thick * 0.5),
	])
	var glow_col := Color(col, col.a * 0.28)
	draw_line(tail, shaft_end, glow_col, thick * 2.2, true)
	draw_colored_polygon(glow, glow_col)
	draw_line(tail, shaft_end, col, thick, true)
	draw_colored_polygon(tri, col)


func _arrow_color() -> Color:
	if disabled:
		return get_theme_color(&"font_disabled_color")
	match get_draw_mode():
		DRAW_PRESSED, DRAW_HOVER_PRESSED:
			return NeonPalette.CYAN.lerp(Color.WHITE, 0.7)
		DRAW_HOVER:
			return NeonPalette.CYAN.lerp(Color.WHITE, 0.35)
	return NeonPalette.CYAN


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
