class_name TurnRing
extends Control
## The live turn timer (ARCHITECTURE section 48): a ring that empties as the seconds run out, with the number in the
## middle, so the time is readable without colour. Cyan while there is time, yellow under 10 s, red under 5 s. It never
## flashes (it only changes colour at those two steps), whatever the reduced-flashing setting says.

const WARN_SECONDS: float = 10.0
const LOW_SECONDS: float = 5.0

var fraction: float = 1.0
var seconds_left: float = -1.0
var total_seconds: float = 0.0


func _init() -> void:
	name = "TurnRing"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## `left` seconds remain of `total` (left < 0 hides the ring: no live timer on this turn).
func set_time(left: float, total: float) -> void:
	seconds_left = left
	total_seconds = total
	visible = left >= 0.0 and total > 0.0
	fraction = clampf(left / maxf(total, 0.001), 0.0, 1.0) if visible else 1.0
	queue_redraw()


func ring_color() -> Color:
	if seconds_left <= LOW_SECONDS:
		return NeonPalette.BAD
	if seconds_left <= WARN_SECONDS:
		return NeonPalette.WARN
	return NeonPalette.CYAN


func shown_text() -> String:
	return str(ceili(seconds_left)) if visible else ""


func apply_scale() -> void:
	custom_minimum_size = Vector2.ONE * UiScale.dp(44.0)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 - UiScale.dp(4.0)
	var w: float = maxf(3.0, UiScale.dp(4.0))
	draw_circle(c, r + w * 0.5, Color(NeonPalette.BG_DEEP, 0.78))
	draw_arc(c, r, 0.0, TAU, 40, Color(NeonPalette.TEXT_DIM, 0.35), w, true)
	if fraction > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * fraction, 40, ring_color(), w, true)
	var font: Font = get_theme_default_font()
	var fs: int = UiScale.hud_font(15.0)
	var text: String = shown_text()
	var ts: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1.0, fs)
	draw_string(font, Vector2(c.x - ts.x * 0.5, c.y + ts.y * 0.3), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, NeonPalette.TEXT)
