class_name NeonPalette
extends RefCounted
## Dark synthwave palette, colour-blind-safe tank colours and procedural tank emblems.
##
## The 8 tank colours were optimised (see tests/show/test_palette.gd) so that every pair
## stays at least ~25 dE (CIE76) apart for protanopia, deuteranopia and tritanopia, while
## all are bright enough for a dark background. Each colour is also paired with an emblem
## shape of the same index, so colour is never the only cue.

# --- Backdrop / UI ---
const BG_DEEP: Color = Color(0.027, 0.012, 0.075)  # #070313
const BG_MID: Color = Color(0.094, 0.035, 0.208)  # #180935
const PANEL: Color = Color(0.067, 0.031, 0.157, 0.82)
const PANEL_EDGE: Color = Color(0.0, 0.9, 1.0, 0.85)
const CYAN: Color = Color(0.0, 0.929, 1.0)
const MAGENTA: Color = Color(1.0, 0.18, 0.62)
const SUNSET: Color = Color(1.0, 0.45, 0.2)
const VIOLET: Color = Color(0.45, 0.25, 1.0)
const TEXT: Color = Color(0.93, 0.96, 1.0)
const TEXT_DIM: Color = Color(0.6, 0.62, 0.85)
const HOT: Color = Color(1.0, 0.95, 0.75)
const GOOD: Color = Color(0.2, 1.0, 0.55)
const WARN: Color = Color(1.0, 0.85, 0.2)
const BAD: Color = Color(1.0, 0.25, 0.3)

# --- Tank colours (index = TankState.color_index) ---
const TANK_COLORS: Array[Color] = [
	Color8(0xC1, 0x91, 0x22),  # 0 amber
	Color8(0x4F, 0xC3, 0xF7),  # 1 sky
	Color8(0x00, 0xFF, 0xAF),  # 2 mint
	Color8(0xBC, 0xFE, 0x38),  # 3 lime
	Color8(0x8D, 0x77, 0xFF),  # 4 violet
	Color8(0xFF, 0x4E, 0x63),  # 5 coral
	Color8(0xD3, 0x63, 0xB2),  # 6 orchid
	Color8(0xF1, 0xD6, 0xEA),  # 7 blush white
]
const TANK_COLOR_NAME_KEYS: Array[String] = [
	"COLOR_AMBER", "COLOR_SKY", "COLOR_MINT", "COLOR_LIME",
	"COLOR_VIOLET", "COLOR_CORAL", "COLOR_ORCHID", "COLOR_BLUSH",
]

enum Emblem { CIRCLE, TRIANGLE, SQUARE, DIAMOND, STAR, HEXAGON, CROSS, CHEVRON }
const EMBLEM_COUNT: int = 8
const EMBLEM_NAME_KEYS: Array[String] = [
	"EMBLEM_CIRCLE", "EMBLEM_TRIANGLE", "EMBLEM_SQUARE", "EMBLEM_DIAMOND",
	"EMBLEM_STAR", "EMBLEM_HEXAGON", "EMBLEM_CROSS", "EMBLEM_CHEVRON",
]


static func tank_color(index: int) -> Color:
	return TANK_COLORS[posmod(index, TANK_COLORS.size())]


static func tank_emblem(index: int) -> int:
	return posmod(index, EMBLEM_COUNT)


## Outline of an emblem centred on the origin, fitting a circle of `radius`.
## Points are in drawing order (counter-clockwise on screen is not guaranteed).
static func emblem_polygon(shape: int, radius: float) -> PackedVector2Array:
	var r: float = radius
	var pts := PackedVector2Array()
	match posmod(shape, EMBLEM_COUNT):
		Emblem.CIRCLE:
			pts = _regular(24, r, 0.0)
		Emblem.TRIANGLE:
			pts = _regular(3, r * 1.1, -PI / 2.0)
		Emblem.SQUARE:
			pts = _regular(4, r * 1.3, PI / 4.0)
		Emblem.DIAMOND:
			pts = PackedVector2Array([Vector2(0, -r * 1.15), Vector2(r * 0.8, 0), Vector2(0, r * 1.15), Vector2(-r * 0.8, 0)])
		Emblem.STAR:
			pts = _star(5, r * 1.15, r * 0.48)
		Emblem.HEXAGON:
			pts = _regular(6, r, 0.0)
		Emblem.CROSS:
			var a: float = r * 0.38
			pts = PackedVector2Array([
				Vector2(-a, -r), Vector2(a, -r), Vector2(a, -a), Vector2(r, -a), Vector2(r, a), Vector2(a, a),
				Vector2(a, r), Vector2(-a, r), Vector2(-a, a), Vector2(-r, a), Vector2(-r, -a), Vector2(-a, -a),
			])
		Emblem.CHEVRON:
			var t: float = r * 0.55
			pts = PackedVector2Array([
				Vector2(-r, -r * 0.2), Vector2(0, -r * 0.95), Vector2(r, -r * 0.2), Vector2(r, -r * 0.2 + t),
				Vector2(0, -r * 0.95 + t), Vector2(-r, -r * 0.2 + t),
			])
			# Shift down so the chevron is vertically centred.
			for i: int in range(pts.size()):
				pts[i].y += r * 0.3
	return pts


## Draws a filled emblem with a dark rim so it reads on any background.
static func draw_emblem(item: CanvasItem, shape: int, center: Vector2, radius: float, color: Color) -> void:
	var poly: PackedVector2Array = emblem_polygon(shape, radius)
	for i: int in range(poly.size()):
		poly[i] += center
	item.draw_colored_polygon(poly, color)
	var closed: PackedVector2Array = poly.duplicate()
	closed.append(poly[0])
	item.draw_polyline(closed, BG_DEEP.lightened(0.15), maxf(1.0, radius * 0.16), true)


static func _regular(n: int, r: float, start: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n):
		var a: float = start + TAU * float(i) / float(n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


static func _star(points: int, r_out: float, r_in: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(points * 2):
		var a: float = -PI / 2.0 + PI * float(i) / float(points)
		var r: float = r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
