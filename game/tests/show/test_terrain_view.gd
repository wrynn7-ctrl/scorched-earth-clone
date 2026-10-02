extends GutTest


func _cells(w: int, h: int) -> PackedByteArray:
	var c := PackedByteArray()
	c.resize(w * h)
	for x: int in range(w):
		for y: int in range(h):
			c[x * h + y] = 0 if y < 10 + x % 7 else 1 + (x + y) % 15
	return c


func test_texture_is_height_by_width_without_transpose() -> void:
	var w: int = 64
	var h: int = 40
	var cells: PackedByteArray = _cells(w, h)
	var tv: TerrainView = add_child_autofree(TerrainView.new())
	tv.setup(cells, w, h)
	assert_eq(tv.get_texture_size(), Vector2i(h, w), "texture is (height wide, width tall)")
	var img: Image = tv.get_cells_texture().get_image()
	assert_eq(img.get_format(), Image.FORMAT_R8)
	assert_eq(img.get_data(), cells, "bytes uploaded unchanged (column-major)")
	# Texel (tx=y, ty=x) holds cell (x, y).
	assert_eq(int(img.get_pixel(25, 3).r * 255.0 + 0.5), int(cells[3 * h + 25]))


func test_update_cells_reuploads() -> void:
	var w: int = 32
	var h: int = 20
	var cells: PackedByteArray = _cells(w, h)
	var tv: TerrainView = add_child_autofree(TerrainView.new())
	tv.setup(cells, w, h)
	cells[5 * h + 19] = 0
	tv.update_cells(cells)
	assert_eq(tv.get_cells_image().get_data(), cells)
	assert_eq(tv.get_texture_size(), Vector2i(h, w))


func test_full_size_world() -> void:
	var cells := PackedByteArray()
	cells.resize(1600 * 900)
	var tv: TerrainView = add_child_autofree(TerrainView.new())
	tv.setup(cells, 1600, 900)
	assert_eq(tv.get_texture_size(), Vector2i(900, 1600))
