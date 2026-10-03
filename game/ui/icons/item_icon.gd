@warning_ignore_start("integer_division")
class_name ItemIcon
extends Control
## Procedural neon glyph for a catalog entry (weapon or item), one drawing per behaviour.
## Everything is drawn with lines/arcs/polygons: no texture assets, crisp at any size, and
## the shape (not only the colour) tells the behaviours apart.
##
## `draw_glyph()` is static so other nodes (tank views, popups) can reuse it.

var _id: String = ""
var _dim: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(item_id: String) -> void:
	_id = item_id
	queue_redraw()


func get_item() -> String:
	return _id


## Draws the glyph in a muted tone (for entries the player cannot use right now).
func set_dim(dim: bool) -> void:
	_dim = dim
	queue_redraw()


func _draw() -> void:
	var r: float = minf(size.x, size.y) * 0.5
	var col: Color = glyph_color(_id)
	if _dim:
		col = col.darkened(0.45)
	draw_glyph(self, _id, size * 0.5, r * 0.9, col)


## Main colour of an entry's glyph.
static func glyph_color(id: String) -> Color:
	match _behavior(id):
		"explode":
			return NeonPalette.SUNSET
		"splitter":
			return NeonPalette.MAGENTA
		"roller":
			return NeonPalette.VIOLET
		"tunneler":
			return NeonPalette.CYAN
		"dirt":
			return Color(0.85, 0.62, 0.25)
		"sludge":
			return NeonPalette.GOOD
		"fire":
			return Color(1.0, 0.4, 0.15)
		"seeker":
			return NeonPalette.WARN
		"beam":
			return Color(0.55, 0.95, 1.0)
		"static":
			return Color(0.75, 0.6, 1.0)
		"well":
			return Color(0.65, 0.35, 1.0)
		"anchor":
			return Color(0.3, 0.75, 1.0)
		"shield":
			return NeonPalette.CYAN
		"repulsor":
			return Color(0.4, 1.0, 0.85)
		"chute":
			return NeonPalette.WARN
		"fuel":
			return NeonPalette.SUNSET
		"repair":
			return NeonPalette.GOOD
		"love":
			return Color(1.0, 0.42, 0.66)
	return NeonPalette.TEXT


static func _behavior(id: String) -> String:
	var def: Dictionary = Catalog.get_def(id)
	return def.get("behavior", "") as String


## Draws entry `id` centred on `c`, fitting inside a circle of radius `r`.
static func draw_glyph(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color) -> void:
	var def: Dictionary = Catalog.get_def(id)
	match def.get("behavior", "") as String:
		"explode":
			_explode(ci, c, r, col, def)
		"splitter":
			_splitter(ci, c, r, col, def)
		"roller":
			_roller(ci, c, r, col, def)
		"tunneler":
			_tunneler(ci, c, r, col)
		"dirt":
			_dirt(ci, c, r, col, def)
		"sludge":
			_sludge(ci, c, r, col)
		"fire":
			_fire(ci, c, r, col, def)
		"seeker":
			_seeker(ci, c, r, col)
		"beam":
			_beam(ci, c, r, col)
		"static":
			_static(ci, c, r, col)
		"well":
			_well(ci, c, r, col)
		"anchor":
			_anchor(ci, c, r, col)
		"shield":
			_shield(ci, c, r, col, def)
		"repulsor":
			_repulsor(ci, c, r, col)
		"chute":
			_chute(ci, c, r, col)
		"fuel":
			_fuel(ci, c, r, col)
		"repair":
			_repair(ci, c, r, col)
		"love":
			HeartShape.draw(ci, c + Vector2(0.0, r * 0.04), r * 0.88, col)
		_:
			ci.draw_circle(c, r * 0.35, col)


## A padlock (the FULL GAME badge).
static func draw_lock(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var body := Rect2(c + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 0.95))
	ci.draw_rect(body, Color(col, 0.3))
	ci.draw_rect(body, col, false, maxf(1.2, r * 0.18))
	ci.draw_arc(c + Vector2(0, -r * 0.1), r * 0.45, PI, TAU, 14, col, maxf(1.2, r * 0.18), true)
	ci.draw_circle(c + Vector2(0, r * 0.35), r * 0.14, col)


# --- helpers ---------------------------------------------------------------------------

## A line with a soft halo underneath (the neon look).
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(a, b, Color(col, 0.25), w * 2.6, true)
	ci.draw_line(a, b, col, w, true)


static func _poly(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	if pts.size() < 2:
		return
	ci.draw_polyline(pts, Color(col, 0.25), w * 2.6, true)
	ci.draw_polyline(pts, col, w, true)


static func _arc(ci: CanvasItem, c: Vector2, rad: float, a0: float, a1: float, col: Color, w: float) -> void:
	ci.draw_arc(c, rad, a0, a1, 24, Color(col, 0.25), w * 2.6, true)
	ci.draw_arc(c, rad, a0, a1, 24, col, w, true)


static func _w(r: float) -> float:
	return maxf(1.2, r * 0.11)


static func _ground(ci: CanvasItem, c: Vector2, r: float, col: Color, y: float) -> void:
	_line(ci, c + Vector2(-r * 0.9, y), c + Vector2(r * 0.9, y), Color(col, 0.7), _w(r) * 0.8)


# --- glyphs ----------------------------------------------------------------------------

## Burst: a core, rings and rays. The core grows with the blast radius so a Spark Dart
## looks small and a Supernova looks huge.
static func _explode(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var blast: float = clampf(float(def.get("r", 20)) / 160.0, 0.0, 1.0)
	var core: float = r * (0.16 + 0.34 * blast)
	ci.draw_circle(c, core * 1.7, Color(col, 0.2))
	ci.draw_circle(c, core, NeonPalette.HOT)
	var rays: int = 6 + int(blast * 6.0)
	for i: int in range(rays):
		var a: float = TAU * float(i) / float(rays)
		var d: Vector2 = Vector2(cos(a), sin(a))
		_line(ci, c + d * (core + r * 0.14), c + d * r * (0.62 + 0.25 * (i % 2)), col, _w(r))
	if blast > 0.3:
		_arc(ci, c, r * 0.94, 0.0, TAU, Color(col, 0.7), _w(r) * 0.7)


## One stem that fans out into several: children count = number of rays.
static func _splitter(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var n: int = clampi(def.get("children", 5) as int, 3, 9)
	var base := Vector2(c.x, c.y + r * 0.85)
	var fork := Vector2(c.x, c.y + r * 0.1)
	_line(ci, base, fork, col, _w(r))
	for i: int in range(n):
		var t: float = float(i) / float(n - 1) - 0.5
		var tip: Vector2 = c + Vector2(t * r * 1.8, -r * (0.78 - absf(t) * 0.45))
		_line(ci, fork, tip, col, _w(r) * 0.8)
		ci.draw_circle(tip, r * 0.1, NeonPalette.HOT)


## A ball on a slope with motion arcs.
static func _roller(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var heavy: bool = (def.get("speed", 1) as int) > 1
	var a := c + Vector2(-r * 0.95, -r * 0.35)
	var b := c + Vector2(r * 0.95, r * 0.55)
	_line(ci, a, b, Color(col, 0.7), _w(r) * 0.8)
	var slope: Vector2 = (b - a).normalized()
	var normal := Vector2(slope.y, -slope.x)
	var br: float = r * (0.38 if heavy else 0.3)
	var pos: Vector2 = a.lerp(b, 0.55) + normal * (br + 1.0)
	ci.draw_circle(pos, br * 1.5, Color(col, 0.2))
	ci.draw_circle(pos, br, col)
	ci.draw_circle(pos + Vector2(-br * 0.25, -br * 0.3), br * 0.3, NeonPalette.HOT)
	for k: int in range(2 if not heavy else 3):
		var back: Vector2 = pos - slope * (br * 1.6 + r * 0.22 * float(k)) + normal * (br * 0.9)
		_line(ci, back, back - slope * r * 0.18, Color(col, 0.6), _w(r) * 0.6)


## A zig-zag drill path diving into the ground.
static func _tunneler(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	_ground(ci, c, r, col, -r * 0.2)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.7, -r * 0.8), c + Vector2(-r * 0.35, -r * 0.2), c + Vector2(-r * 0.2, r * 0.05),
		c + Vector2(0.0, -r * 0.1), c + Vector2(r * 0.2, r * 0.3), c + Vector2(r * 0.4, r * 0.15),
		c + Vector2(r * 0.65, r * 0.6),
	])
	_poly(ci, pts, col, _w(r))
	ci.draw_circle(pts[pts.size() - 1], r * 0.14, NeonPalette.HOT)


static func _dirt(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var big: float = 1.0 if (def.get("r", 40) as int) >= 60 else 0.78
	var base_y: float = c.y + r * 0.6
	var pts := PackedVector2Array()
	for i: int in range(17):
		var t: float = float(i) / 16.0
		var x: float = lerpf(-r * 0.9, r * 0.9, t)
		var h: float = r * 1.1 * big * (1.0 - pow(2.0 * t - 1.0, 2.0))
		pts.append(Vector2(c.x + x, base_y - h))
	var fill := PackedVector2Array(pts)
	ci.draw_colored_polygon(fill, Color(col, 0.28))
	_poly(ci, pts, col, _w(r))
	_ground(ci, c, r, col, r * 0.6)
	for k: int in range(3):
		ci.draw_circle(c + Vector2((float(k) - 1.0) * r * 0.25, -r * (0.1 + 0.18 * float(k % 2))), r * 0.06, NeonPalette.HOT)


## A droplet over a wavy flow line.
static func _sludge(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var drop := PackedVector2Array()
	for i: int in range(21):
		var t: float = float(i) / 20.0
		var a: float = TAU * t
		var rad: float = r * 0.42 * (1.0 - 0.25 * cos(a)) if sin(a) > -0.2 else r * 0.42
		drop.append(c + Vector2(sin(a) * rad * 0.9, -cos(a) * rad * 0.9 - r * 0.28))
	drop[drop.size() - 1] = drop[0]
	ci.draw_colored_polygon(drop, Color(col, 0.35))
	_poly(ci, drop, col, _w(r))
	var wave := PackedVector2Array()
	for i: int in range(13):
		var t: float = float(i) / 12.0
		wave.append(c + Vector2(lerpf(-r * 0.9, r * 0.9, t), r * 0.68 + sin(t * TAU * 1.5) * r * 0.12))
	_poly(ci, wave, col, _w(r) * 0.8)


## Teardrop flame with an inner flame; heavier fire gets a second tongue.
static func _fire(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var outer := PackedVector2Array([
		c + Vector2(0, -r * 0.95), c + Vector2(r * 0.3, -r * 0.45), c + Vector2(r * 0.62, -r * 0.05),
		c + Vector2(r * 0.55, r * 0.5), c + Vector2(0, r * 0.88), c + Vector2(-r * 0.55, r * 0.5),
		c + Vector2(-r * 0.62, -r * 0.05), c + Vector2(-r * 0.25, -r * 0.4), c + Vector2(0, -r * 0.95),
	])
	ci.draw_colored_polygon(outer.slice(0, 8), Color(col, 0.3))
	_poly(ci, outer, col, _w(r))
	var inner := PackedVector2Array([
		c + Vector2(0, -r * 0.2), c + Vector2(r * 0.25, r * 0.2), c + Vector2(r * 0.18, r * 0.58),
		c + Vector2(0, r * 0.7), c + Vector2(-r * 0.18, r * 0.58), c + Vector2(-r * 0.25, r * 0.2),
	])
	ci.draw_colored_polygon(inner, NeonPalette.HOT)
	if (def.get("points", 60) as int) > 80:
		_line(ci, c + Vector2(r * 0.75, -r * 0.5), c + Vector2(r * 0.55, -r * 0.1), col, _w(r) * 0.8)


## A curving path ending in an arrowhead aimed at a ring.
static func _seeker(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var target := c + Vector2(r * 0.55, r * 0.5)
	_arc(ci, target, r * 0.3, 0.0, TAU, Color(col, 0.7), _w(r) * 0.7)
	var pts := PackedVector2Array()
	for i: int in range(15):
		var t: float = float(i) / 14.0
		var p: Vector2 = Vector2(lerpf(-r * 0.9, r * 0.3, t), r * 0.7 - sin(t * PI * 0.9) * r * 1.5 + t * t * r * 0.7)
		pts.append(c + p)
	_poly(ci, pts, col, _w(r))
	var tip: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (tip - pts[pts.size() - 3]).normalized()
	var side := Vector2(-dir.y, dir.x)
	ci.draw_colored_polygon(PackedVector2Array([tip + dir * r * 0.22, tip - dir * r * 0.1 + side * r * 0.2, tip - dir * r * 0.1 - side * r * 0.2]), NeonPalette.HOT)


static func _beam(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var a := c + Vector2(-r * 0.95, r * 0.3)
	var b := c + Vector2(r * 0.95, -r * 0.3)
	ci.draw_line(a, b, Color(col, 0.2), r * 0.5, true)
	ci.draw_line(a, b, Color(col, 0.55), r * 0.22, true)
	ci.draw_line(a, b, NeonPalette.HOT, _w(r) * 0.8, true)
	ci.draw_circle(a, r * 0.2, NeonPalette.HOT)
	_line(ci, b + Vector2(0, -r * 0.3), b + Vector2(0, r * 0.3), col, _w(r) * 0.8)


static func _static(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var bolt := PackedVector2Array([
		c + Vector2(r * 0.25, -r * 0.95), c + Vector2(-r * 0.5, r * 0.1), c + Vector2(-r * 0.05, r * 0.1),
		c + Vector2(-r * 0.3, r * 0.95), c + Vector2(r * 0.55, -r * 0.2), c + Vector2(r * 0.1, -r * 0.2),
	])
	ci.draw_colored_polygon(bolt, Color(col, 0.35))
	var closed := PackedVector2Array(bolt)
	closed.append(bolt[0])
	_poly(ci, closed, col, _w(r))


static func _well(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	for arm: int in range(2):
		var pts := PackedVector2Array()
		for i: int in range(25):
			var t: float = float(i) / 24.0
			var a: float = t * TAU * 1.25 + float(arm) * PI
			pts.append(c + Vector2(cos(a), sin(a)) * r * (0.1 + 0.85 * t))
		_poly(ci, pts, col, _w(r))
	ci.draw_circle(c, r * 0.12, NeonPalette.HOT)


static func _anchor(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	_arc(ci, c + Vector2(0, -r * 0.7), r * 0.17, 0.0, TAU, col, _w(r))
	_line(ci, c + Vector2(0, -r * 0.53), c + Vector2(0, r * 0.75), col, _w(r))
	_line(ci, c + Vector2(-r * 0.4, -r * 0.2), c + Vector2(r * 0.4, -r * 0.2), col, _w(r))
	_arc(ci, c + Vector2(0, r * 0.1), r * 0.65, 0.35, PI - 0.35, col, _w(r))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.62, r * 0.4), c + Vector2(-r * 0.78, r * 0.18), c + Vector2(-r * 0.4, r * 0.28)]), NeonPalette.HOT)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.62, r * 0.4), c + Vector2(r * 0.78, r * 0.18), c + Vector2(r * 0.4, r * 0.28)]), NeonPalette.HOT)


## A bubble; more rings for stronger shields.
static func _shield(ci: CanvasItem, c: Vector2, r: float, col: Color, def: Dictionary) -> void:
	var hp: int = def.get("hp", 30) as int
	var rings: int = 1 + clampi(hp / 40, 0, 2)
	ci.draw_circle(c, r * 0.9, Color(col, 0.12))
	for k: int in range(rings):
		_arc(ci, c, r * (0.9 - 0.2 * float(k)), 0.0, TAU, Color(col, 1.0 - 0.2 * float(k)), _w(r) * (1.0 - 0.15 * float(k)))
	_arc(ci, c, r * 0.5, PI * 1.05, PI * 1.45, NeonPalette.HOT, _w(r) * 0.8)


static func _repulsor(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r * 0.16, NeonPalette.HOT)
	for k: int in range(3):
		var rad: float = r * (0.36 + 0.27 * float(k))
		for q: int in range(4):
			var a: float = PI * 0.5 * float(q) + PI * 0.25
			_arc(ci, c, rad, a - 0.35, a + 0.35, Color(col, 1.0 - 0.25 * float(k)), _w(r))


static func _chute(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var top := c + Vector2(0, -r * 0.15)
	_arc(ci, top, r * 0.85, PI, TAU, col, _w(r))
	var hook := c + Vector2(0, r * 0.7)
	for x: float in [-0.85, -0.3, 0.3, 0.85]:
		_line(ci, top + Vector2(x * r * 0.85, 0), hook, Color(col, 0.7), _w(r) * 0.6)
	ci.draw_rect(Rect2(hook - Vector2(r * 0.14, 0), Vector2(r * 0.28, r * 0.26)), NeonPalette.HOT)


static func _fuel(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var body := Rect2(c + Vector2(-r * 0.5, -r * 0.65), Vector2(r, r * 1.4))
	ci.draw_rect(body, Color(col, 0.22))
	ci.draw_rect(body, col, false, _w(r))
	ci.draw_rect(Rect2(c + Vector2(-r * 0.22, -r * 0.88), Vector2(r * 0.44, r * 0.2)), col)
	var bolt := PackedVector2Array([
		c + Vector2(r * 0.12, -r * 0.4), c + Vector2(-r * 0.22, r * 0.08), c + Vector2(0, r * 0.08),
		c + Vector2(-r * 0.12, r * 0.55), c + Vector2(r * 0.24, -r * 0.1), c + Vector2(0, -r * 0.1),
	])
	ci.draw_colored_polygon(bolt, NeonPalette.HOT)


static func _repair(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var a: float = r * 0.3
	var cross := PackedVector2Array([
		c + Vector2(-a, -r * 0.8), c + Vector2(a, -r * 0.8), c + Vector2(a, -a), c + Vector2(r * 0.8, -a),
		c + Vector2(r * 0.8, a), c + Vector2(a, a), c + Vector2(a, r * 0.8), c + Vector2(-a, r * 0.8),
		c + Vector2(-a, a), c + Vector2(-r * 0.8, a), c + Vector2(-r * 0.8, -a), c + Vector2(-a, -a),
	])
	ci.draw_colored_polygon(cross, Color(col, 0.35))
	var closed := PackedVector2Array(cross)
	closed.append(cross[0])
	_poly(ci, closed, col, _w(r))
	ci.draw_circle(c + Vector2(r * 0.6, -r * 0.6), r * 0.08, NeonPalette.HOT)
