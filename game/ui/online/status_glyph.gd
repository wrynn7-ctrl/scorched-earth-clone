class_name StatusGlyph
extends Control
## A small drawn symbol that says a state by its SHAPE (colour only decorates it): a filled dot (live / your turn),
## a ring (waiting), a broken ring (reconnecting), a cross (offline), a check (done). Used by the match list, the
## connection indicator and the seat rows, so no state is ever carried by colour alone.

enum Kind { DOT, RING, BROKEN, CROSS, CHECK }

var kind: int = Kind.DOT
var color: Color = NeonPalette.GOOD
var size_dp: float = 14.0


func _init(shape: int = Kind.DOT, tint: Color = NeonPalette.GOOD) -> void:
	kind = shape
	color = tint
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2.ONE * UiScale.dp(size_dp)
	OnlineKit.min_size(self, size_dp, size_dp)  # OnlineKit.apply() keeps it in step with the screen


func set_glyph(shape: int, tint: Color) -> void:
	kind = shape
	color = tint
	queue_redraw()


func apply_scale() -> void:
	custom_minimum_size = Vector2.ONE * UiScale.dp(size_dp)
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.42
	var w: float = maxf(1.5, r * 0.28)
	match kind:
		Kind.DOT:
			draw_circle(c, r * 1.25, Color(color, 0.25))
			draw_circle(c, r, color)
		Kind.RING:
			draw_arc(c, r, 0.0, TAU, 24, color, w, true)
		Kind.BROKEN:
			draw_arc(c, r, 0.4, TAU - 1.0, 18, color, w, true)
		Kind.CROSS:
			draw_line(c + Vector2(-r, -r) * 0.8, c + Vector2(r, r) * 0.8, color, w, true)
			draw_line(c + Vector2(-r, r) * 0.8, c + Vector2(r, -r) * 0.8, color, w, true)
		Kind.CHECK:
			draw_polyline(PackedVector2Array([c + Vector2(-r, 0.1 * r), c + Vector2(-0.3 * r, 0.8 * r), c + Vector2(r, -0.7 * r)]),
					color, w, true)
