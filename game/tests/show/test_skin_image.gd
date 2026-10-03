extends GutTest
## Picture import maths and filter: crop box, 128x64 neon posterize, file decoding.


func _gradient(w: int, h: int) -> Image:
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y: int in range(h):
		for x: int in range(w):
			img.set_pixel(x, y, Color.from_hsv(float(x) / float(w), 0.6, 0.15 + 0.85 * float(y) / float(h)))
	return img


# --- crop ---------------------------------------------------------------------------------

func test_crop_box_has_the_hull_window_shape() -> void:
	for src: Vector2 in [Vector2(1000, 1000), Vector2(2000, 200), Vector2(300, 900), Vector2(64, 64), Vector2(4000, 3000)]:
		var box: Vector2 = SkinImage.crop_box(src, 1.0)
		assert_almost_eq(box.x / box.y, SkinImage.CROP_ASPECT, 0.001, "aspect for %s" % str(src))
		assert_lte(box.x, src.x + 0.001)
		assert_lte(box.y, src.y + 0.001)
		assert_true(is_equal_approx(box.x, src.x) or is_equal_approx(box.y, src.y), "the box is as large as fits: %s" % str(src))


func test_zoom_shrinks_the_box_and_is_clamped() -> void:
	var src := Vector2(1000, 1000)
	var full: Vector2 = SkinImage.crop_box(src, 1.0)
	assert_eq(SkinImage.crop_box(src, 2.0), full / 2.0)
	assert_eq(SkinImage.crop_box(src, 0.1), full, "below the minimum zoom counts as 1")
	assert_eq(SkinImage.crop_box(src, 99.0), full / SkinImage.MAX_ZOOM)


func test_the_crop_rect_always_stays_inside_the_picture() -> void:
	var src := Vector2(800, 600)
	for zoom: float in [1.0, 1.5, 3.0, 6.0]:
		for c: Vector2 in [Vector2.ZERO, Vector2(-500, -500), Vector2(10000, 10000), Vector2(400, 300), Vector2(799, 1)]:
			var r: Rect2 = SkinImage.crop_rect(src, c, zoom)
			assert_true(Rect2(Vector2.ZERO, src).grow(0.001).encloses(r), "zoom %s centre %s -> %s" % [zoom, c, r])
			assert_almost_eq(r.size.x / r.size.y, SkinImage.CROP_ASPECT, 0.001)


func test_clamp_center_keeps_a_centred_box_where_it_is() -> void:
	var src := Vector2(800, 600)
	assert_eq(SkinImage.clamp_center(Vector2(400, 300), src, 2.0), Vector2(400, 300))
	var box: Vector2 = SkinImage.crop_box(src, 2.0)
	assert_eq(SkinImage.clamp_center(Vector2(0, 0), src, 2.0), box * 0.5)
	assert_eq(SkinImage.clamp_center(Vector2(900, 900), src, 2.0), src - box * 0.5)
	# At zoom 1 on a wide picture the box fills the height, so only x moves.
	var wide := Vector2(2000, 200)
	var c: Vector2 = SkinImage.clamp_center(Vector2(1000, 50), wide, 1.0)
	assert_eq(c.y, 100.0)


func test_pinch_zoom_follows_the_finger_distance() -> void:
	assert_almost_eq(CropOverlay.pinch_zoom(1.0, 100.0, 200.0), 2.0, 0.001, "fingers spread: zoom in")
	assert_almost_eq(CropOverlay.pinch_zoom(3.0, 200.0, 100.0), 1.5, 0.001, "fingers close: zoom out")
	assert_eq(CropOverlay.pinch_zoom(1.0, 100.0, 10.0), 1.0, "clamped at the minimum")
	assert_eq(CropOverlay.pinch_zoom(5.0, 100.0, 1000.0), SkinImage.MAX_ZOOM)
	assert_eq(CropOverlay.pinch_zoom(2.0, 0.0, 100.0), 2.0, "no previous distance: unchanged")


func test_process_crops_then_filters_to_128x64() -> void:
	var src: Image = _gradient(640, 480)
	var rect: Rect2 = SkinImage.crop_rect(Vector2(640, 480), Vector2(320, 240), 2.0)
	var out: Image = SkinImage.process(src, rect)
	assert_eq(out.get_size(), Vector2i(128, 64))
	# The crop is really used: a left-half and a right-half crop give different pictures.
	var left: Image = SkinImage.process(src, SkinImage.crop_rect(Vector2(640, 480), Vector2(0, 240), 4.0))
	var right: Image = SkinImage.process(src, SkinImage.crop_rect(Vector2(640, 480), Vector2(640, 240), 4.0))
	assert_ne(left.get_data(), right.get_data())
	# A degenerate rect falls back to the whole picture instead of failing.
	assert_eq(SkinImage.process(src, Rect2(5, 5, 0, 0)).get_size(), Vector2i(128, 64))


# --- neon filter --------------------------------------------------------------------------

func test_the_filter_outputs_128x64_whatever_the_input() -> void:
	for size: Vector2i in [Vector2i(10, 10), Vector2i(128, 64), Vector2i(1000, 300), Vector2i(64, 400), Vector2i(2, 2)]:
		var out: Image = SkinImage.neon(_gradient(size.x, size.y))
		assert_eq(out.get_size(), Vector2i(128, 64), str(size))
		assert_eq(out.get_format(), Image.FORMAT_RGBA8)


func test_the_filter_reduces_brightness_to_six_tones() -> void:
	var src: Image = _gradient(512, 256)
	assert_gt(SkinImage.tone_count(src), 40, "the source has a smooth range of tones")
	var out: Image = SkinImage.neon(src)
	var tones: int = SkinImage.tone_count(out)
	assert_lte(tones, SkinImage.TONES, "at most %d brightness tones, got %d" % [SkinImage.TONES, tones])
	assert_gte(tones, 4, "but it is not flattened")
	# A photo-like noisy image too.
	var noisy: Image = Image.create(200, 100, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y: int in range(100):
		for x: int in range(200):
			noisy.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	assert_lte(SkinImage.tone_count(SkinImage.neon(noisy)), SkinImage.TONES)


func test_the_filter_boosts_saturation() -> void:
	var dull: Image = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	dull.fill(Color.from_hsv(0.6, 0.3, 0.8))
	var out: Image = SkinImage.neon(dull)
	assert_gt(out.get_pixel(30, 15).s, 0.3 * SkinImage.SATURATION_GAIN * 0.95)


func test_black_stays_visible_not_black() -> void:
	var black: Image = Image.create(64, 32, false, Image.FORMAT_RGBA8)
	black.fill(Color.BLACK)
	var c: Color = SkinImage.neon(black).get_pixel(10, 10)
	assert_gte(c.v, SkinImage.MIN_VALUE - 0.01, "the darkest tone is not pure black")


func test_edges_get_a_bright_rim() -> void:
	var img: Image = Image.create(128, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color.from_hsv(0.8, 0.9, 0.1))
	for y: int in range(64):
		for x: int in range(64, 128):
			img.set_pixel(x, y, Color.from_hsv(0.8, 0.9, 1.0))
	var out: Image = SkinImage.neon(img)
	var flat_dark: float = out.get_pixel(10, 32).v
	var rim: float = out.get_pixel(64, 32).v
	assert_gt(rim, flat_dark + 0.5, "the tone edge is drawn at full brightness")
	assert_lte(SkinImage.tone_count(out), SkinImage.TONES)
	# A flat picture has no rim at all.
	var flat: Image = SkinImage.neon(Image.create(128, 64, false, Image.FORMAT_RGBA8))
	assert_eq(SkinImage.tone_count(flat), 1)


# --- reading files ------------------------------------------------------------------------

func test_decode_reads_png_jpg_and_webp_by_content() -> void:
	var src: Image = _gradient(200, 120)
	for bytes: PackedByteArray in [src.save_png_to_buffer(), src.save_jpg_to_buffer(0.9), src.save_webp_to_buffer(true)]:
		var img: Image = SkinImage.decode(bytes)
		assert_not_null(img)
		assert_eq(img.get_size(), Vector2i(200, 120))
		assert_eq(img.get_format(), Image.FORMAT_RGBA8)


func test_decode_rejects_garbage() -> void:
	assert_null(SkinImage.decode(PackedByteArray()))
	assert_null(SkinImage.decode("hello, this is text, not a picture".to_utf8_buffer()))
	# Too short to be a picture, and a header-less blob of bytes: both are refused before any decoder runs.
	assert_null(SkinImage.decode(PackedByteArray([0x89, 0x50, 0x4E, 0x47])))
	assert_null(SkinImage.decode(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])))


func test_large_pictures_are_shrunk_on_read() -> void:
	var big: Image = _gradient(3000, 1000)
	var img: Image = SkinImage.decode(big.save_png_to_buffer())
	assert_not_null(img)
	assert_eq(maxi(img.get_width(), img.get_height()), SkinImage.MAX_SOURCE_EDGE)
	assert_almost_eq(float(img.get_width()) / float(img.get_height()), 3.0, 0.02)


func test_load_file_handles_missing_and_unreadable_files() -> void:
	assert_null(SkinImage.load_file(""))
	assert_null(SkinImage.load_file("user://definitely_not_here.png"))
	var path: String = "user://test_skin_image_fake.png"
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("I am a text file called .png")
	f.close()
	assert_null(SkinImage.load_file(path))
	_gradient(32, 16).save_png(path)
	var ok: Image = SkinImage.load_file(path)
	assert_not_null(ok)
	assert_eq(ok.get_size(), Vector2i(32, 16))
	DirAccess.remove_absolute(path)
