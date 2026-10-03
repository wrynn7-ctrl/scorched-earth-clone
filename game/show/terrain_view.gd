class_name TerrainView
extends Node2D
## Draws terrain bytes with the neon shader.
##
## Input is the simulation layout (ARCHITECTURE §5): column-major, index = x * height + y.
## The bytes are uploaded as-is as an R8 image of size (height wide, width tall) with no
## CPU transpose; terrain.gdshader swaps the coordinates.

const SHADER: Shader = preload("res://show/terrain.gdshader")

var world_width: int = 0
var world_height: int = 0

var _image: Image = null
var _texture: ImageTexture = null
var _material: ShaderMaterial = null
var _theme_id: String = ""
var _strata_image: Image = null
var _strata_texture: ImageTexture = null


## (Re)creates the texture for a new terrain (new round, different size).
func setup(cells: PackedByteArray, width: int, height: int) -> void:
	assert(cells.size() == width * height, "cells must hold width*height bytes")
	world_width = width
	world_height = height
	_image = Image.create_from_data(height, width, false, Image.FORMAT_R8, cells)
	_texture = ImageTexture.create_from_image(_image)
	_ensure_material()
	_material.set_shader_parameter("cells", _texture)
	_material.set_shader_parameter("world_size", Vector2i(width, height))
	queue_redraw()


func _ensure_material() -> void:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		material = _material
		apply_theme(_theme_id if _theme_id != "" else ThemeDefs.DEFAULT_ID)


## Restyles for ThemeDefs theme `id`: the 15 strata colours (a 16x1 texture, index = material),
## the rim glow colours and its strength. Cheap enough to call on every round start.
func apply_theme(id: String) -> void:
	var def: Dictionary = ThemeDefs.get_def(id)
	_theme_id = def["id"] as String
	if _material == null:
		_ensure_material()
		return
	if _strata_image == null:
		_strata_image = Image.create(16, 1, false, Image.FORMAT_RGBA8)
		_strata_texture = ImageTexture.create_from_image(_strata_image)
	var strata: Array[Color] = def["strata"]
	_strata_image.set_pixel(0, 0, Color.BLACK)
	for i: int in range(ThemeDefs.STRATA_COUNT):
		_strata_image.set_pixel(i + 1, 0, strata[i])
	_strata_texture.update(_strata_image)
	_material.set_shader_parameter("strata_tex", _strata_texture)
	_material.set_shader_parameter("edge_a", def["edge_a"] as Color)
	_material.set_shader_parameter("edge_b", def["edge_b"] as Color)
	_material.set_shader_parameter("glow_strength", def["glow"] as float)


func get_theme_id() -> String:
	return _theme_id


## The 16x1 strata image (tests): pixel m is the colour of material m.
func get_strata_image() -> Image:
	if _material == null:
		_ensure_material()
	return _strata_image


## Re-uploads after the terrain changed (full upload; fine at 1600x900 = 1.4 MB).
func update_cells(cells: PackedByteArray) -> void:
	assert(cells.size() == world_width * world_height, "size changed: call setup()")
	_image.set_data(world_height, world_width, false, Image.FORMAT_R8, cells)
	_texture.update(_image)


func get_texture_size() -> Vector2i:
	return Vector2i(_texture.get_width(), _texture.get_height()) if _texture != null else Vector2i.ZERO


## CPU-side copy of what was uploaded (for tests/debugging).
func get_cells_image() -> Image:
	return _image


func get_cells_texture() -> ImageTexture:
	return _texture


func _draw() -> void:
	if world_width > 0:
		draw_rect(Rect2(0, 0, world_width, world_height), Color.WHITE)
