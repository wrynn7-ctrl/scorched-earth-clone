class_name SkinImage
extends RefCounted
## Picture import for skins (full version only): reading a picked file, the crop maths, and the
## neon filter that makes any photo fit the art. Pure image operations, no nodes and no network;
## the picture only ever ends up as a 128x64 PNG next to the skin file on this device.
##
## Crop: the box has the shape of the hull's skin window (SkinShapes.BAKE_RECT, 24:9), because the
## 128x64 result is stretched back over exactly that window; so what the player frames is what
## the hull shows. Zoom 1 = the largest box that fits the picture, higher zoom = a smaller box.

const MAX_FILE_BYTES: int = 48 * 1024 * 1024
## Pictures are shrunk to this long edge as soon as they are read (crop screen memory and speed).
const MAX_SOURCE_EDGE: int = 1536
const CROP_ASPECT: float = 24.0 / 9.0
const MIN_ZOOM: float = 1.0
const MAX_ZOOM: float = 6.0

## Neon filter settings: ~6 brightness tones, stronger colour, hue snapped to 24 steps, and a
## bright rim with a one-step glow along every strong tone edge.
const TONES: int = 6
const MIN_VALUE: float = 0.16
const SATURATION_GAIN: float = 1.35
const SATURATION_LIFT: float = 0.12
const HUE_STEPS: float = 24.0
const EDGE_STEP: int = 2


# --- reading ------------------------------------------------------------------------------

## Reads a PNG, JPG or WebP (found by its first bytes, not its name) into an RGBA8 image no larger
## than MAX_SOURCE_EDGE. Returns null for a missing, empty, huge, unreadable or non-image file.
static func load_file(path: String) -> Image:
	if path.is_empty():
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12 or bytes.size() > MAX_FILE_BYTES:
		return null
	return decode(bytes)


static func decode(bytes: PackedByteArray) -> Image:
	var img := Image.new()
	var err: int = ERR_FILE_UNRECOGNIZED
	if bytes.size() >= 12:
		if bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
			err = img.load_png_from_buffer(bytes)
		elif bytes[0] == 0xFF and bytes[1] == 0xD8:
			err = img.load_jpg_from_buffer(bytes)
		elif bytes[0] == 0x52 and bytes[1] == 0x49 and bytes[8] == 0x57 and bytes[9] == 0x45:
			err = img.load_webp_from_buffer(bytes)
	if err != OK or img.is_empty() or img.get_width() < 2 or img.get_height() < 2:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_SOURCE_EDGE:
		var k: float = float(MAX_SOURCE_EDGE) / float(longest)
		img.resize(maxi(2, roundi(img.get_width() * k)), maxi(2, roundi(img.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return img


# --- crop maths ---------------------------------------------------------------------------

## Size of the crop box in source pixels at `zoom`.
static func crop_box(src: Vector2, zoom: float) -> Vector2:
	var w: float = minf(src.x, src.y * CROP_ASPECT)
	var box := Vector2(w, w / CROP_ASPECT)
	return box / clampf(zoom, MIN_ZOOM, MAX_ZOOM)


## The centre moved so the whole box stays inside the picture.
static func clamp_center(center: Vector2, src: Vector2, zoom: float) -> Vector2:
	var half: Vector2 = crop_box(src, zoom) * 0.5
	return Vector2(
		clampf(center.x, half.x, maxf(half.x, src.x - half.x)),
		clampf(center.y, half.y, maxf(half.y, src.y - half.y)))


## The crop rectangle in source pixels (always inside the picture).
static func crop_rect(src: Vector2, center: Vector2, zoom: float) -> Rect2:
	var box: Vector2 = crop_box(src, zoom)
	var c: Vector2 = clamp_center(center, src, zoom)
	return Rect2(c - box * 0.5, box)


## Crops `src` to `rect` and runs the neon filter: the result is always 128x64.
static func process(src: Image, rect: Rect2) -> Image:
	var bounds := Rect2i(0, 0, src.get_width(), src.get_height())
	var r: Rect2i = Rect2i(rect.position.round(), rect.size.round()).intersection(bounds)
	if r.size.x < 2 or r.size.y < 2:
		r = bounds
	return neon(src.get_region(r))


# --- the neon filter ----------------------------------------------------------------------

## Any image -> 128x64: posterised to TONES brightness steps, saturation boosted, with a bright
## edge rim and glow. Every output brightness is one of TONES values.
static func neon(src: Image) -> Image:
	var img: Image = src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var shrinking: bool = img.get_width() > SkinData.IMAGE_W or img.get_height() > SkinData.IMAGE_H
	img.resize(SkinData.IMAGE_W, SkinData.IMAGE_H, Image.INTERPOLATE_LANCZOS if shrinking else Image.INTERPOLATE_BILINEAR)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var top: int = TONES - 1
	var levels := PackedInt32Array()
	levels.resize(w * h)
	var hues := PackedFloat32Array()
	hues.resize(w * h)
	var sats := PackedFloat32Array()
	sats.resize(w * h)
	for y: int in range(h):
		for x: int in range(w):
			var c: Color = img.get_pixel(x, y)
			var i: int = y * w + x
			# Transparent pixels (a PNG with holes) read as dark.
			var v: float = c.v * c.a
			levels[i] = clampi(roundi(v * float(top)), 0, top)
			hues[i] = roundf(c.h * HUE_STEPS) / HUE_STEPS
			sats[i] = clampf(c.s * SATURATION_GAIN + SATURATION_LIFT, 0.0, 1.0)
	var edge: PackedByteArray = _edges(levels, w, h)
	var out: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		for x: int in range(w):
			var i: int = y * w + x
			var lv: int = levels[i]
			var s: float = sats[i]
			if edge[i] == 2:
				lv = top
				s *= 0.7
			elif edge[i] == 1:
				lv = mini(top, lv + 1)
			var v2: float = MIN_VALUE + (1.0 - MIN_VALUE) * float(lv) / float(top)
			out.set_pixel(x, y, Color.from_hsv(fposmod(hues[i], 1.0), s, v2, 1.0))
	return out


## 2 = a pixel on a strong tone edge, 1 = next to one (the glow), 0 = neither.
static func _edges(levels: PackedInt32Array, w: int, h: int) -> PackedByteArray:
	var edge := PackedByteArray()
	edge.resize(w * h)
	for y: int in range(h):
		for x: int in range(w):
			var i: int = y * w + x
			var d: int = 0
			if x + 1 < w:
				d = maxi(d, absi(levels[i] - levels[i + 1]))
			if y + 1 < h:
				d = maxi(d, absi(levels[i] - levels[i + w]))
			if d >= EDGE_STEP:
				edge[i] = 2
				# Mark the neighbour on the dimmer side too, so the rim is two pixels wide.
				if x + 1 < w and absi(levels[i] - levels[i + 1]) >= EDGE_STEP:
					edge[i + 1] = 2
				if y + 1 < h and absi(levels[i] - levels[i + w]) >= EDGE_STEP:
					edge[i + w] = 2
	var glow: PackedByteArray = edge.duplicate()
	for y: int in range(h):
		for x: int in range(w):
			var i: int = y * w + x
			if edge[i] != 2:
				continue
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + off.x
				var ny: int = y + off.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and glow[ny * w + nx] == 0:
					glow[ny * w + nx] = 1
	return glow


## Distinct brightness steps in an image (max channel as 0..255), for tests and diagnostics.
static func tone_count(img: Image) -> int:
	var seen: Dictionary = {}
	for y: int in range(img.get_height()):
		for x: int in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			seen[roundi(maxf(c.r, maxf(c.g, c.b)) * 255.0)] = true
	return seen.size()
