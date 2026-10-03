class_name HeartConfetti
extends Node2D
## Heart confetti for the Love Edition win: one CPUParticles2D that rains soft pink, peach and white
## hearts from above the top of the screen. Lives in a screen-space layer, so it covers the picture
## whatever the camera does. Reduced motion: fewer, slower hearts.

const COUNT: int = 64
const COUNT_CALM: int = 24
const LIFETIME: float = 5.0
## Random start colours (the particle colour is picked from this ramp, then the fade ramp applies).
const COLORS: Array[Color] = [
	Color(1.0, 0.45, 0.72), Color(1.0, 0.7, 0.56), Color(1.0, 0.88, 0.94),
	Color(0.85, 0.6, 1.0), Color(1.0, 0.4, 0.55),
]

var _particles: CPUParticles2D = null
var _active: bool = false


func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.name = "Hearts"
	_particles.texture = FxTextures.heart()
	_particles.material = FxTextures.additive()
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.local_coords = true
	_particles.emitting = false
	_particles.direction = Vector2(0.0, 1.0)
	_particles.spread = 18.0
	_particles.angle_min = -30.0
	_particles.angle_max = 30.0
	_particles.angular_velocity_min = -60.0
	_particles.angular_velocity_max = 60.0
	_particles.scale_amount_min = 0.2
	_particles.scale_amount_max = 0.5
	var pick := Gradient.new()
	var offsets := PackedFloat32Array()
	for i: int in range(COLORS.size()):
		offsets.append(float(i) / float(COLORS.size() - 1))
	pick.offsets = offsets
	pick.colors = PackedColorArray(COLORS)
	_particles.color_initial_ramp = pick
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.8, 1.0])
	_particles.color_ramp = fade
	add_child(_particles)
	visible = false
	get_viewport().size_changed.connect(_fit)


## Starts raining (call again to restart).
func start() -> void:
	_active = true
	visible = true
	var calm: bool = ShowSettings.reduce_motion
	_particles.amount = COUNT_CALM if calm else COUNT
	_particles.lifetime = LIFETIME * (1.5 if calm else 1.0)
	_particles.initial_velocity_min = 25.0 if calm else 55.0
	_particles.initial_velocity_max = 55.0 if calm else 130.0
	_particles.gravity = Vector2(0.0, 18.0 if calm else 55.0)
	_fit()
	_particles.preprocess = 0.0
	_particles.restart()
	_particles.emitting = true


func stop() -> void:
	_active = false
	visible = false
	if _particles != null:
		_particles.emitting = false


func is_active() -> bool:
	return _active


func particle_count() -> int:
	return _particles.amount if _particles != null else 0


## Emits from a strip just above the visible area, as wide as it.
func _fit() -> void:
	if _particles == null:
		return
	var size: Vector2 = get_viewport().get_visible_rect().size
	_particles.position = Vector2(size.x * 0.5, -24.0)
	_particles.emission_rect_extents = Vector2(size.x * 0.5, 8.0)
