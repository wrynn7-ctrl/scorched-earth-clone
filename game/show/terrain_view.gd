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


## (Re)creates the texture for a new terrain (new round, different size).
func setup(cells: PackedByteArray, width: int, height: int) -> void:
	assert(cells.size() == width * height, "cells must hold width*height bytes")
	world_width = width
	world_height = height
	_image = Image.create_from_data(height, width, false, Image.FORMAT_R8, cells)
	_texture = ImageTexture.create_from_image(_image)
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		material = _material
	_material.set_shader_parameter("cells", _texture)
	_material.set_shader_parameter("world_size", Vector2i(width, height))
	queue_redraw()


## Re-uploads after the terrain changed (full upload; fine at 1600x900 = 1.4 MB).
func update_cells(cells: PackedByteArray) -> void:
	assert(cells.size() == world_width * world_height, "size changed: call setup()")
	_image.set_data(world_height, world_width, false, Image.FORMAT_R8, cells)
	_texture.update(_image)


func get_texture_size() -> Vector2i:
	return Vector2i(_texture.get_width(), _texture.get_height()) if _texture != null else Vector2i.ZERO


func get_cells_texture() -> ImageTexture:
	return _texture


func _draw() -> void:
	if world_width > 0:
		draw_rect(Rect2(0, 0, world_width, world_height), Color.WHITE)
