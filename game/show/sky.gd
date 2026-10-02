class_name NeonSky
extends CanvasLayer
## Background: gradient sky, synthwave sun or moon, perspective grid horizon, parallax stars.
## A single ColorRect + cheap shader on a CanvasLayer behind the world (not affected by the camera).

const SHADER: Shader = preload("res://show/sky.gdshader")

@export var moon: bool = false:
	set(v):
		moon = v
		_apply_moon()

var _rect: ColorRect = null
var _material: ShaderMaterial = null


func _ready() -> void:
	layer = -10
	_rect = ColorRect.new()
	_rect.name = "SkyRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)
	_rect.resized.connect(_on_resized)
	_on_resized()
	_apply_moon()


## Camera position (world units); stars/grid shift slightly for depth.
func set_parallax(cam_pos: Vector2) -> void:
	if _material != null:
		_material.set_shader_parameter("parallax", cam_pos * 0.01)


func _on_resized() -> void:
	if _rect.size.y > 0.0:
		_material.set_shader_parameter("aspect", _rect.size.x / _rect.size.y)


func _apply_moon() -> void:
	if _material != null:
		_material.set_shader_parameter("moon_mix", 1.0 if moon else 0.0)
