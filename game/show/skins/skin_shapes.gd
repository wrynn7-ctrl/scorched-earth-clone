class_name SkinShapes
extends RefCounted
## The geometry of every skin part: four hull silhouettes, four turrets, ten decals and the names
## the Skin Studio shows for them. All in TankView's local units (origin = bottom centre of the
## 24x12 footprint, y up is negative; the turret pivot sits at (0, -12)).
##
## The vector data is shared: TankView draws the hull and turret from it, the baker rasterises the
## decals from it, and the studio draws the picker icons from it.

## Part of the hull the baked skin texture covers (every hull polygon fits inside it).
const BAKE_RECT: Rect2 = Rect2(-12.0, -9.0, 24.0, 9.0)
## The barrel tip, in turret-local x (TankView.BARREL_LEN + 2): every turret ends here so shells
## and flashes spawn in the same place whatever the style.
const BARREL_TIP: float = 16.0
const TIP_HALF: Array[float] = [1.6, 3.1, 1.5, 2.3]
## Where decals sit on the hull and how big they are.
const DECAL_CENTER: Vector2 = Vector2(0.0, -4.4)
const DECAL_RADIUS: float = 3.5

const BODY_NAME_KEYS: Array[String] = ["SKIN_BODY_CLASSIC", "SKIN_BODY_SPIRE", "SKIN_BODY_DOME", "SKIN_BODY_BLOCK"]
const TURRET_NAME_KEYS: Array[String] = ["SKIN_TURRET_CLASSIC", "SKIN_TURRET_TWIN", "SKIN_TURRET_CANNON", "SKIN_TURRET_LONG"]
const PATTERN_NAME_KEYS: Array[String] = [
	"SKIN_PATTERN_NONE", "SKIN_PATTERN_STRIPES", "SKIN_PATTERN_CIRCUIT", "SKIN_PATTERN_CAMO", "SKIN_PATTERN_GRID",
	"SKIN_PATTERN_CHEVRONS",
]
const DECAL_NAME_KEYS: Array[String] = [
	"SKIN_DECAL_BOLT", "SKIN_DECAL_STAR", "SKIN_DECAL_BONES", "SKIN_DECAL_WING", "SKIN_DECAL_FLAME", "SKIN_DECAL_EYE",
	"SKIN_DECAL_CROWN", "SKIN_DECAL_WAVE", "SKIN_DECAL_TARGET", "SKIN_DECAL_HEART",
]


# --- hull ---------------------------------------------------------------------------------

## The hull outline, open (the first point is not repeated), clockwise on screen from the bottom left.
static func hull(style: int) -> PackedVector2Array:
	match clampi(style, 0, SkinData.BODY_STYLES - 1):
		1:  # Spire: a tent-shaped skirt rising to a narrow roof.
			return PackedVector2Array([
				Vector2(-12, 0), Vector2(12, 0), Vector2(12, -1.5), Vector2(6.5, -4.5), Vector2(2.8, -8.5),
				Vector2(-2.8, -8.5), Vector2(-6.5, -4.5), Vector2(-12, -1.5),
			])
		2:  # Dome: a half ellipse on a short base.
			var pts := PackedVector2Array([Vector2(-12, 0), Vector2(12, 0), Vector2(12, -2.0)])
			for i: int in range(1, 12):
				var a: float = PI * float(i) / 12.0
				pts.append(Vector2(cos(a) * 11.5, -2.0 - sin(a) * 6.8))
			pts.append(Vector2(-12, -2.0))
			return pts
		3:  # Block: stepped and boxy.
			return PackedVector2Array([
				Vector2(-12, 0), Vector2(12, 0), Vector2(12, -4), Vector2(10, -4), Vector2(10, -7.5),
				Vector2(6.5, -9), Vector2(-6.5, -9), Vector2(-10, -7.5), Vector2(-10, -4), Vector2(-12, -4),
			])
		_:  # Classic: the original trapezoid.
			return PackedVector2Array([
				Vector2(-12, 0), Vector2(12, 0), Vector2(12, -3.5), Vector2(8.5, -8.0),
				Vector2(-8.5, -8.0), Vector2(-12, -3.5),
			])


## `pts` plus its first point, for draw_polyline.
static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out: PackedVector2Array = pts.duplicate()
	out.append(pts[0])
	return out


## UV of a hull point inside the baked texture (0..1 over BAKE_RECT).
static func uv(p: Vector2) -> Vector2:
	return Vector2(
		clampf((p.x - BAKE_RECT.position.x) / BAKE_RECT.size.x, 0.0, 1.0),
		clampf((p.y - BAKE_RECT.position.y) / BAKE_RECT.size.y, 0.0, 1.0))


static func hull_uvs(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in pts:
		out.append(uv(p))
	return out


# --- turret -------------------------------------------------------------------------------

## The turret as filled polygons in turret-local units (pivot at the origin, barrel along +x).
static func turret_polys(style: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	match clampi(style, 0, SkinData.TURRET_STYLES - 1):
		1:  # Twin barrels on a short block.
			out.append(_rect(0.0, -3.1, 16.0, -0.9))
			out.append(_rect(0.0, 0.9, 16.0, 3.1))
			out.append(_rect(-2.0, -3.6, 3.0, 3.6))
		2:  # Cannon: a fat housing tapering to a short muzzle.
			out.append(PackedVector2Array([
				Vector2(-1.5, -3.4), Vector2(5.5, -3.4), Vector2(16, -1.5), Vector2(16, 1.5), Vector2(5.5, 3.4),
				Vector2(-1.5, 3.4),
			]))
		3:  # Longshot: a thin barrel, a round housing and a muzzle brake.
			out.append(_rect(5.0, -1.0, 16.0, 1.0))
			out.append(_rect(-2.5, -2.8, 6.0, 2.8))
			out.append(_rect(12.5, -2.3, 16.0, 2.3))
		_:
			out.append(_rect(0.0, -1.6, 16.0, 1.6))
	return out


## Half height of the glowing muzzle line at the barrel tip.
static func turret_tip_half(style: int) -> float:
	return TIP_HALF[clampi(style, 0, SkinData.TURRET_STYLES - 1)]


## The rectangle that bounds a turret (for its glow).
static func turret_bounds(style: int) -> Rect2:
	var r: Rect2 = Rect2()
	var first: bool = true
	for poly: PackedVector2Array in turret_polys(style):
		for p: Vector2 in poly:
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])


# --- decals -------------------------------------------------------------------------------

## A decal as shapes in a -1..1 box (y down): {k: "poly" | "line", p: points, w: stroke width for
## lines, closed: bool for lines}. Polygons are simple, so they triangulate.
static func decal_shapes(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match clampi(id, 0, SkinData.DECALS - 1):
		0:  # bolt
			out.append(_poly([Vector2(0.28, -1), Vector2(-0.6, 0.1), Vector2(-0.05, 0.1), Vector2(-0.32, 1),
					Vector2(0.62, -0.28), Vector2(0.06, -0.28), Vector2(0.48, -1)]))
		1:  # star
			var star := PackedVector2Array()
			for i: int in range(10):
				var a: float = -PI / 2.0 + PI * float(i) / 5.0
				star.append(Vector2(cos(a), sin(a)) * (1.0 if i % 2 == 0 else 0.42))
			out.append({"k": "poly", "p": star})
		2:  # crossed bones (no skull)
			for s: float in [-1.0, 1.0]:
				var a := Vector2(-0.78, -0.78 * s)
				var b := Vector2(0.78, 0.78 * s)
				var dir: Vector2 = (b - a).normalized()
				var perp := Vector2(-dir.y, dir.x)
				out.append({"k": "line", "p": PackedVector2Array([a, b]), "w": 0.34, "closed": false})
				for end: Vector2 in [a, b]:
					var outward: float = 1.0 if end == b else -1.0
					for side: float in [-1.0, 1.0]:
						out.append({"k": "poly", "p": _circle(end + perp * 0.17 * side + dir * 0.1 * outward, 0.2, 8)})
		3:  # wing
			out.append(_poly([Vector2(-1, -0.9), Vector2(0.2, -0.62), Vector2(1, -0.1), Vector2(0.2, -0.02),
					Vector2(0.9, 0.38), Vector2(0.0, 0.3), Vector2(0.6, 0.85), Vector2(-0.6, 0.62), Vector2(-1, 0.1)]))
		4:  # flame
			out.append(_poly([Vector2(0, -1), Vector2(0.4, -0.4), Vector2(0.8, 0.15), Vector2(0.6, 0.75), Vector2(0, 1),
					Vector2(-0.6, 0.75), Vector2(-0.8, 0.15), Vector2(-0.45, -0.25), Vector2(-0.25, 0.15),
					Vector2(-0.12, -0.5)]))
		5:  # eye
			var lid := PackedVector2Array()
			for i: int in range(13):
				var t: float = float(i) / 12.0
				lid.append(Vector2(lerpf(-1.0, 1.0, t), -sin(t * PI) * 0.62))
			for i: int in range(1, 12):
				var t2: float = 1.0 - float(i) / 12.0
				lid.append(Vector2(lerpf(-1.0, 1.0, t2), sin(t2 * PI) * 0.62))
			out.append({"k": "line", "p": lid, "w": 0.22, "closed": true})
			out.append({"k": "poly", "p": _circle(Vector2.ZERO, 0.3, 12)})
		6:  # crown
			out.append(_poly([Vector2(-1, 0.75), Vector2(-1, -0.65), Vector2(-0.5, 0.0), Vector2(0, -0.95),
					Vector2(0.5, 0.0), Vector2(1, -0.65), Vector2(1, 0.75)]))
		7:  # wave
			for y: float in [-0.45, 0.45]:
				var w := PackedVector2Array()
				for i: int in range(13):
					var x: float = lerpf(-1.0, 1.0, float(i) / 12.0)
					w.append(Vector2(x, y + sin(x * PI * 1.5) * 0.28))
				out.append({"k": "line", "p": w, "w": 0.24, "closed": false})
		8:  # target
			out.append({"k": "line", "p": _circle(Vector2.ZERO, 0.88, 20), "w": 0.2, "closed": true})
			out.append({"k": "line", "p": _circle(Vector2.ZERO, 0.46, 14), "w": 0.2, "closed": true})
			out.append({"k": "poly", "p": _circle(Vector2.ZERO, 0.16, 8)})
		_:  # heart
			var heart := PackedVector2Array()
			for i: int in range(24):
				var t3: float = TAU * float(i) / 24.0
				heart.append(Vector2(
						16.0 * pow(sin(t3), 3.0),
						-(13.0 * cos(t3) - 5.0 * cos(2.0 * t3) - 2.0 * cos(3.0 * t3) - cos(4.0 * t3)) + 2.0) / 16.5)
			out.append({"k": "poly", "p": heart})
	return out


## Draws a decal (vector) centred on `center` inside a circle of `radius`.
static func draw_decal(item: CanvasItem, id: int, center: Vector2, radius: float, color: Color) -> void:
	for shape: Dictionary in decal_shapes(id):
		var pts := PackedVector2Array()
		for p: Vector2 in (shape["p"] as PackedVector2Array):
			pts.append(center + p * radius)
		if shape["k"] == "poly":
			item.draw_colored_polygon(pts, color)
		else:
			if shape.get("closed", false):
				pts.append(pts[0])
			item.draw_polyline(pts, color, maxf(1.0, float(shape["w"]) * radius), true)


## A hull silhouette with its turret, sized to `rect`, for the picker icons.
static func draw_hull_icon(item: CanvasItem, style: int, rect: Rect2, color: Color) -> void:
	var s: float = minf(rect.size.x / 24.0, rect.size.y / 10.0)
	var origin := Vector2(rect.get_center().x, rect.end.y - (rect.size.y - 10.0 * s) * 0.5)
	var pts := PackedVector2Array()
	for p: Vector2 in hull(style):
		pts.append(origin + p * s)
	item.draw_colored_polygon(pts, Color(color, 0.25))
	item.draw_polyline(closed(pts), color, maxf(1.5, s * 1.1), true)


static func draw_turret_icon(item: CanvasItem, style: int, rect: Rect2, color: Color) -> void:
	var s: float = minf(rect.size.x / 20.0, rect.size.y / 8.0)
	var origin := Vector2(rect.position.x + rect.size.x * 0.5 - 6.0 * s, rect.get_center().y)
	for poly: PackedVector2Array in turret_polys(style):
		var pts := PackedVector2Array()
		for p: Vector2 in poly:
			pts.append(origin + p * s)
		item.draw_colored_polygon(pts, Color(color, 0.25))
		item.draw_polyline(closed(pts), color, maxf(1.5, s * 0.7), true)


## A tiny sketch of a pattern inside `rect` (the picker icon).
static func draw_pattern_icon(item: CanvasItem, id: int, rect: Rect2, color: Color) -> void:
	var r: Rect2 = rect.grow(-2.0)
	item.draw_rect(r, Color(color, 0.12))
	var w: float = maxf(1.5, r.size.y * 0.08)
	match clampi(id, 0, SkinData.PATTERNS - 1):
		SkinData.Pattern.STRIPES:
			for i: int in range(5):
				var x: float = r.position.x + r.size.x * (0.1 + 0.2 * float(i))
				item.draw_line(Vector2(x, r.end.y), Vector2(x + r.size.y * 0.6, r.position.y), color, w * 1.6, true)
		SkinData.Pattern.CIRCUIT:
			var a := Vector2(r.position.x + r.size.x * 0.1, r.position.y + r.size.y * 0.7)
			var b := Vector2(r.position.x + r.size.x * 0.45, r.position.y + r.size.y * 0.7)
			var c := Vector2(r.position.x + r.size.x * 0.6, r.position.y + r.size.y * 0.3)
			var d := Vector2(r.position.x + r.size.x * 0.9, r.position.y + r.size.y * 0.3)
			item.draw_polyline(PackedVector2Array([a, b, c, d]), color, w, true)
			item.draw_circle(a, w * 1.4, color)
			item.draw_circle(d, w * 1.4, color)
		SkinData.Pattern.CAMO:
			item.draw_circle(r.position + r.size * Vector2(0.3, 0.4), r.size.y * 0.3, color)
			item.draw_circle(r.position + r.size * Vector2(0.62, 0.62), r.size.y * 0.26, color)
			item.draw_circle(r.position + r.size * Vector2(0.78, 0.3), r.size.y * 0.2, color)
		SkinData.Pattern.GRID:
			for i: int in range(1, 4):
				var gx: float = r.position.x + r.size.x * float(i) / 4.0
				var gy: float = r.position.y + r.size.y * float(i) / 4.0
				item.draw_line(Vector2(gx, r.position.y), Vector2(gx, r.end.y), color, w, true)
				item.draw_line(Vector2(r.position.x, gy), Vector2(r.end.x, gy), color, w, true)
		SkinData.Pattern.CHEVRONS:
			for i: int in range(3):
				var y: float = r.position.y + r.size.y * (0.35 + 0.25 * float(i))
				item.draw_polyline(PackedVector2Array([
					Vector2(r.position.x + r.size.x * 0.15, y), Vector2(r.get_center().x, y - r.size.y * 0.3),
					Vector2(r.end.x - r.size.x * 0.15, y)]), color, w * 1.3, true)
		_:
			item.draw_line(r.position, r.end, color, w, true)
			item.draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), color, w, true)


static func _poly(pts: Array) -> Dictionary:
	return {"k": "poly", "p": PackedVector2Array(pts)}


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i: int in range(n):
		var a: float = TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts
