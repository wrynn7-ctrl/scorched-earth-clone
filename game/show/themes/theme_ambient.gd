class_name ThemeAmbient
extends Node2D
## One reusable CPUParticles2D that gives a theme its ambient life: embers rising over Magma
## City, spores drifting over the Toxic Marsh. A single node (<= 40 particles, additive glow
## texture, one draw call) lives under the sky, so it sits behind the terrain and can never
## hide a shell or a tank. Off with reduce motion.

const EMBER_COUNT: int = 36
const SPORE_COUNT: int = 28

var _particles: CPUParticles2D = null
var _style: String = ThemeDefs.AMBIENT_NONE
var _color: Color = Color.WHITE
var _area: Vector2 = Vector2(1600.0, 900.0)


func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.name = "Particles"
	_particles.texture = FxTextures.glow()
	_particles.material = FxTextures.additive()
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.emitting = false
	_particles.local_coords = false
	add_child(_particles)
	_restyle()


## Switches the effect (a ThemeDefs.AMBIENT_* style and its tint).
func set_style(style: String, color: Color) -> void:
	_style = style
	_color = color
	if _particles != null:
		_restyle()


## The screen area (canvas units) the particles live in.
func set_area(size: Vector2) -> void:
	_area = size
	if _particles != null:
		_restyle()


func get_style() -> String:
	return _style


func is_emitting() -> bool:
	return _particles != null and _particles.emitting


func particle_count() -> int:
	return _particles.amount if _particles != null else 0


func _restyle() -> void:
	var on: bool = _style != ThemeDefs.AMBIENT_NONE and not ShowSettings.reduce_motion
	_particles.emitting = on
	visible = on
	if not on:
		return
	var ramp := Gradient.new()
	if _style == ThemeDefs.AMBIENT_EMBERS:
		_particles.amount = EMBER_COUNT
		_particles.lifetime = 7.0
		_particles.position = Vector2(_area.x * 0.5, _area.y * 0.62)
		_particles.emission_rect_extents = Vector2(_area.x * 0.5, 30.0)
		_particles.direction = Vector2(0.15, -1.0)
		_particles.spread = 25.0
		_particles.gravity = Vector2(6.0, -8.0)
		_particles.initial_velocity_min = 22.0
		_particles.initial_velocity_max = 60.0
		_particles.scale_amount_min = 0.05
		_particles.scale_amount_max = 0.13
		ramp.colors = PackedColorArray([Color(1.0, 0.9, 0.55, 0.0), Color(_color, 0.85), Color(_color.darkened(0.5), 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	else:
		_particles.amount = SPORE_COUNT
		_particles.lifetime = 10.0
		_particles.position = _area * 0.5
		_particles.emission_rect_extents = _area * 0.5
		_particles.direction = Vector2(1.0, -0.3)
		_particles.spread = 180.0
		_particles.gravity = Vector2(3.0, -2.0)
		_particles.initial_velocity_min = 5.0
		_particles.initial_velocity_max = 16.0
		_particles.scale_amount_min = 0.07
		_particles.scale_amount_max = 0.2
		ramp.colors = PackedColorArray([Color(_color, 0.0), Color(_color, 0.5), Color(_color, 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_particles.color_ramp = ramp
	_particles.preprocess = _particles.lifetime  # already populated on the first frame
	_particles.restart()
	_particles.emitting = true
