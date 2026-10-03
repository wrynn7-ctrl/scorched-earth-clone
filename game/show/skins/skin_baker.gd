class_name SkinBaker
extends RefCounted
## Bakes a skin's hull art (base colour, picture, pattern, decal) into one small texture, once,
## with plain Image operations (so it also works headless and costs nothing per frame). TankView
## draws the hull as a textured polygon with it, with the identity outline on top.
##
## The texture covers SkinShapes.BAKE_RECT (24 x 9 units) at `ppu` pixels per unit: 4 in battle
## (96 x 36 px), more for the big studio preview, less for the list cards.

const DEFAULT_PPU: int = 4
const MIN_PPU: int = 1
const MAX_PPU: int = 16
## The hull shades from the top (lit) to the bottom (dark) by this much.
const SHADE: float = 0.32
const PATTERN_ALPHA: float = 0.9
const PATTERN_ALPHA_OVER_IMAGE: float = 0.5

## Camouflage blobs (cx, cy, rx, ry) in hull units.
const CAMO: Array[Vector4] = [
	Vector4(-8.0, -6.0, 3.4, 2.2), Vector4(-3.5, -2.6, 3.0, 2.0), Vector4(2.0, -6.5, 3.2, 2.1),
	Vector4(7.0, -3.0, 3.6, 2.2), Vector4(9.5, -7.0, 2.2, 1.6), Vector4(-10.0, -1.4, 2.4, 1.5),
	Vector4(0.0, -8.6, 2.6, 1.2), Vector4(4.5, -0.9, 2.6, 1.3), Vector4(-6.5, -8.2, 1.8, 1.0),
]
## Circuit traces in hull units; every end gets a round pad.
const CIRCUIT: Array = [
	[Vector2(-11.0, -2.0), Vector2(-7.0, -2.0), Vector2(-5.0, -4.0), Vector2(1.5, -4.0)],
	[Vector2(-11.0, -6.0), Vector2(-8.0, -6.0), Vector2(-6.0, -8.0)],
	[Vector2(11.0, -3.0), Vector2(7.5, -3.0), Vector2(5.5, -5.0), Vector2(3.5, -5.0)],
	[Vector2(11.0, -7.0), Vector2(8.5, -7.0), Vector2(7.0, -8.5)],
	[Vector2(-2.0, -0.8), Vector2(2.5, -0.8), Vector2(4.0, -2.0), Vector2(8.0, -2.0)],
]


static func texture_size(ppu: int) -> Vector2i:
	var k: int = clampi(ppu, MIN_PPU, MAX_PPU)
	return Vector2i(roundi(SkinShapes.BAKE_RECT.size.x) * k, roundi(SkinShapes.BAKE_RECT.size.y) * k)


static func bake(skin: SkinData, ppu: int = DEFAULT_PPU) -> ImageTexture:
	return ImageTexture.create_from_image(bake_image(skin, ppu))


static func bake_image(skin: SkinData, ppu: int = DEFAULT_PPU) -> Image:
	var k: int = clampi(ppu, MIN_PPU, MAX_PPU)
	var size: Vector2i = texture_size(k)
	var img: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	_fill_base(img, skin.base)
	if skin.image != null:
		_blit_picture(img, skin.image)
	_apply_pattern(img, skin, k)
	_apply_decal(img, skin, k)
	return img


# --- layers -------------------------------------------------------------------------------

static func _fill_base(img: Image, base: Color) -> void:
	var h: int = img.get_height()
	for j: int in range(h):
		var f: float = 1.0 - SHADE * float(j) / float(maxi(1, h - 1))
		img.fill_rect(Rect2i(0, j, img.get_width(), 1), Color(base.r * f, base.g * f, base.b * f, 1.0))


static func _blit_picture(img: Image, picture: Image) -> void:
	var im: Image = picture.duplicate() as Image
	im.convert(Image.FORMAT_RGBA8)
	im.resize(img.get_width(), img.get_height(), Image.INTERPOLATE_BILINEAR)
	img.blit_rect(im, Rect2i(0, 0, img.get_width(), img.get_height()), Vector2i.ZERO)


static func _apply_pattern(img: Image, skin: SkinData, ppu: int) -> void:
	if skin.pattern == SkinData.Pattern.NONE:
		return
	var col := Color(skin.pattern_color, PATTERN_ALPHA_OVER_IMAGE if skin.image != null else PATTERN_ALPHA)
	match skin.pattern:
		SkinData.Pattern.CIRCUIT:
			for raw: Array in CIRCUIT:
				var trace := PackedVector2Array(raw)
				_stamp_polyline(img, trace, 0.45, col, ppu)
				_stamp_disc(img, trace[0], 0.6, col, ppu)
				_stamp_disc(img, trace[trace.size() - 1], 0.6, col, ppu)
		SkinData.Pattern.CAMO:
			for blob: Vector4 in CAMO:
				_stamp_ellipse(img, Vector2(blob.x, blob.y), Vector2(blob.z, blob.w), col, ppu)
		_:
			for j: int in range(img.get_height()):
				for i: int in range(img.get_width()):
					var p: Vector2 = _unit(i, j, ppu)
					if _formula_hit(skin.pattern, p.x, p.y):
						_blend(img, i, j, col)


## Stripes, grid and chevrons are simple repeating functions of the hull position.
static func _formula_hit(pattern: int, x: float, y: float) -> bool:
	match pattern:
		SkinData.Pattern.STRIPES:
			return fposmod(x * 0.9 - y * 0.9, 4.2) < 1.7
		SkinData.Pattern.GRID:
			return fposmod(x + 1.5, 3.0) < 0.42 or fposmod(y, 3.0) < 0.42
		SkinData.Pattern.CHEVRONS:
			return fposmod(-y + absf(x) * 0.7, 3.4) < 1.3
	return false


static func _apply_decal(img: Image, skin: SkinData, ppu: int) -> void:
	var col := Color(skin.accent, 1.0)
	var c: Vector2 = SkinShapes.DECAL_CENTER
	var r: float = SkinShapes.DECAL_RADIUS
	for shape: Dictionary in SkinShapes.decal_shapes(skin.decal):
		var pts := PackedVector2Array()
		for p: Vector2 in (shape["p"] as PackedVector2Array):
			pts.append(c + p * r)
		if shape["k"] == "poly":
			_fill_polygon(img, pts, col, ppu)
		else:
			if shape.get("closed", false):
				pts.append(pts[0])
			_stamp_polyline(img, pts, float(shape["w"]) * r, col, ppu)


# --- rasterising helpers (hull units in, pixels out) ----------------------------------------

## Hull-unit position of the centre of pixel (i, j).
static func _unit(i: int, j: int, ppu: int) -> Vector2:
	return SkinShapes.BAKE_RECT.position + Vector2(float(i) + 0.5, float(j) + 0.5) / float(ppu)


static func _px(p: Vector2, ppu: int) -> Vector2:
	return (p - SkinShapes.BAKE_RECT.position) * float(ppu)


static func _blend(img: Image, i: int, j: int, col: Color) -> void:
	if i < 0 or j < 0 or i >= img.get_width() or j >= img.get_height():
		return
	var dst: Color = img.get_pixel(i, j)
	img.set_pixel(i, j, Color(dst.blend(col), 1.0))


static func _bbox(img: Image, a: Vector2, b: Vector2, pad: float) -> Rect2i:
	var x0: int = clampi(floori(minf(a.x, b.x) - pad), 0, img.get_width() - 1)
	var x1: int = clampi(ceili(maxf(a.x, b.x) + pad), 0, img.get_width() - 1)
	var y0: int = clampi(floori(minf(a.y, b.y) - pad), 0, img.get_height() - 1)
	var y1: int = clampi(ceili(maxf(a.y, b.y) + pad), 0, img.get_height() - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


static func _stamp_disc(img: Image, c: Vector2, r: float, col: Color, ppu: int) -> void:
	_stamp_ellipse(img, c, Vector2(r, r), col, ppu)


static func _stamp_ellipse(img: Image, c: Vector2, radii: Vector2, col: Color, ppu: int) -> void:
	var cp: Vector2 = _px(c, ppu)
	var rp: Vector2 = radii * float(ppu)
	var box: Rect2i = _bbox(img, cp - rp, cp + rp, 1.0)
	for j: int in range(box.position.y, box.end.y):
		for i: int in range(box.position.x, box.end.x):
			var d := Vector2((float(i) + 0.5 - cp.x) / rp.x, (float(j) + 0.5 - cp.y) / rp.y)
			if d.length_squared() <= 1.0:
				_blend(img, i, j, col)


static func _stamp_polyline(img: Image, pts: PackedVector2Array, width: float, col: Color, ppu: int) -> void:
	var half: float = maxf(0.5, width * float(ppu) * 0.5)
	for n: int in range(pts.size() - 1):
		var a: Vector2 = _px(pts[n], ppu)
		var b: Vector2 = _px(pts[n + 1], ppu)
		var box: Rect2i = _bbox(img, a, b, half + 1.0)
		var ab: Vector2 = b - a
		var len2: float = maxf(0.0001, ab.length_squared())
		for j: int in range(box.position.y, box.end.y):
			for i: int in range(box.position.x, box.end.x):
				var p := Vector2(float(i) + 0.5, float(j) + 0.5)
				var t: float = clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				if p.distance_to(a + ab * t) <= half:
					_blend(img, i, j, col)


static func _fill_polygon(img: Image, pts: PackedVector2Array, col: Color, ppu: int) -> void:
	var px := PackedVector2Array()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in pts:
		var q: Vector2 = _px(p, ppu)
		px.append(q)
		lo = lo.min(q)
		hi = hi.max(q)
	var box: Rect2i = _bbox(img, lo, hi, 1.0)
	for j: int in range(box.position.y, box.end.y):
		for i: int in range(box.position.x, box.end.x):
			if Geometry2D.is_point_in_polygon(Vector2(float(i) + 0.5, float(j) + 0.5), px):
				_blend(img, i, j, col)
