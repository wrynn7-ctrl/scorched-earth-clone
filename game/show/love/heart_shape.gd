class_name HeartShape
extends RefCounted
## One drawn heart used by everything in the Love Edition (HUD icons, meters, popups, the title
## button): the classic parametric curve, scaled to fit a unit box. Never a font glyph, so it looks
## the same on every device. Visual only.

const POINTS: int = 36
## y of the top lobes and of the bottom tip in the unit outline (screen coordinates, y down).
const TOP: float = -0.906
const TIP: float = 0.906

static var _unit: PackedVector2Array = PackedVector2Array()
static var _icons: Dictionary = {}


## The outline of a heart of "radius" 1 centred on the origin (x spans -1..1, y -0.91..0.91).
static func unit_outline() -> PackedVector2Array:
	if _unit.is_empty():
		for i: int in range(POINTS):
			var t: float = TAU * float(i) / float(POINTS)
			var x: float = 16.0 * pow(sin(t), 3.0)
			var y: float = 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
			_unit.append(Vector2(x, -(y + 2.5)) / 16.0)
	return _unit


## The outline scaled by `size` (the half-width) and moved to `center`.
static func outline(center: Vector2, size: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in unit_outline():
		out.append(center + p * size)
	return out


## The part of the heart below the line that is `frac` of the way from the tip (0) up to the
## top (1): a heart that fills from the bottom. Several polygons when the cut passes between the
## lobes. Built with Geometry2D so a concave cut can never break the triangulation.
static func filled_part(center: Vector2, size: float, frac: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var f: float = clampf(frac, 0.0, 1.0)
	if f <= 0.0:
		return out
	if f >= 1.0:
		out.append(outline(center, size))
		return out
	var cut: float = lerpf(TIP, TOP, f) * size + center.y
	var box := PackedVector2Array([
		Vector2(center.x - size * 1.5, cut), Vector2(center.x + size * 1.5, cut),
		Vector2(center.x + size * 1.5, center.y + size * 1.5), Vector2(center.x - size * 1.5, center.y + size * 1.5)])
	for poly: PackedVector2Array in Geometry2D.intersect_polygons(outline(center, size), box):
		if poly.size() >= 3:
			out.append(poly)
	return out


## Draws a neon heart on `item`: a soft halo, a dark body, the outline, and (fill < 1) only the
## lower part tinted. `fill` 1 = a solid heart.
static func draw(item: CanvasItem, center: Vector2, size: float, color: Color, fill: float = 1.0,
		halo: bool = true) -> void:
	var body: PackedVector2Array = outline(center, size)
	var closed: PackedVector2Array = body.duplicate()
	closed.append(body[0])
	if halo:
		item.draw_polyline(closed, Color(color, 0.18), maxf(2.0, size * 0.5), true)
	if fill >= 1.0:
		item.draw_colored_polygon(body, color)
	else:
		item.draw_colored_polygon(body, Color(NeonPalette.BG_DEEP, 0.85))
		for part: PackedVector2Array in filled_part(center, size, fill):
			item.draw_colored_polygon(part, color)
	item.draw_polyline(closed, color.lightened(0.25) if fill >= 1.0 else color, maxf(1.0, size * 0.14), true)


## A crisp heart as a texture for Button.icon (cached per colour and size).
static func icon_texture(color: Color, px: int = 64) -> ImageTexture:
	var key: String = "%s_%d" % [color.to_html(true), px]
	if _icons.has(key):
		return _icons[key] as ImageTexture
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var half: float = float(px) * 0.5
	for y: int in range(px):
		for x: int in range(px):
			var f: float = implicit(Vector2((float(x) + 0.5 - half) / half, (float(y) + 0.5 - half) / half))
			var a: float = clampf(0.5 - f * float(px) * 0.09, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, color.a * a))
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## The implicit heart function on a -1..1 box (negative inside), shared by the textures. The box is
## stretched to 1.3 so the heart leaves room for a halo.
static func implicit(u: Vector2) -> float:
	var x: float = u.x * 1.3
	var y: float = -u.y * 1.3 + 0.12
	var a: float = x * x + y * y - 1.0
	return a * a * a - x * x * y * y * y
