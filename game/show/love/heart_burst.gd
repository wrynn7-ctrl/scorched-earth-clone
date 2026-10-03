class_name HeartBurst
extends Node2D
## The heart's impact (`heart_burst` event): a soft pink flash and ring, a burst of twinkling
## sparkles and a few tiny hearts that float up and fade. No terrain change and no shake: the Love
## Edition is gentle. One pooled node, reusable: call play() again to re-trigger. CPUParticles2D
## (about 30 particles) for the same reasons as Explosion.

signal finished

const SPARKS: int = 30
const HEARTS: int = 5
const DURATION: float = 2.0
const PINK: Color = Color(1.0, 0.45, 0.7)

var _flash: Sprite2D = null
var _ring: Sprite2D = null
var _sparks: CPUParticles2D = null
var _hearts: Array[Sprite2D] = []
var _tween: Tween = null
var _active: bool = false
var _radius: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 5150
	_flash = _sprite("Flash", FxTextures.glow())
	_ring = _sprite("Ring", FxTextures.ring())
	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparkles"
	_sparks.amount = SPARKS
	_sparks.one_shot = true
	_sparks.explosiveness = 0.95
	_sparks.emitting = false
	_sparks.lifetime = 1.0
	_sparks.texture = FxTextures.sparkle()
	_sparks.material = FxTextures.additive()
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.gravity = Vector2(0, -24)
	_sparks.damping_min = 40.0
	_sparks.damping_max = 90.0
	_sparks.angle_min = -40.0
	_sparks.angle_max = 40.0
	_sparks.scale_amount_min = 0.25
	_sparks.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.98), PINK, Color(1.0, 0.7, 0.55, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	_sparks.color_ramp = ramp
	add_child(_sparks)
	for i: int in range(HEARTS):
		var h: Sprite2D = _sprite("Heart%d" % i, FxTextures.heart())
		_hearts.append(h)


func _sprite(node_name: String, tex: Texture2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = node_name
	sp.texture = tex
	sp.material = FxTextures.additive()
	sp.visible = false
	add_child(sp)
	return sp


func is_playing() -> bool:
	return _active


## Where the burst is visible, in parent coordinates (empty when idle), for the HUD fade.
func get_world_rect() -> Rect2:
	if not _active:
		return Rect2()
	var r: float = _radius * 1.8
	return Rect2(position - Vector2(r, r * 2.4), Vector2(r * 2.0, r * 3.0))


## Plays at `at` (parent coordinates) with the heart's radius in world units.
func play(at: Vector2, radius: float) -> void:
	position = at
	_active = true
	_radius = radius
	if _tween != null:
		_tween.kill()
	var r: float = maxf(8.0, radius)
	var glow_px: float = float(FxTextures.glow().get_width())
	var ring_px: float = float(FxTextures.ring().get_width())
	var peak: float = 0.22 if ShowSettings.reduce_flashing else 0.7

	_flash.visible = true
	_flash.modulate = Color(PINK, peak)
	_flash.scale = Vector2.ONE * (r * 2.4 / glow_px)
	_ring.visible = true
	_ring.modulate = Color(1.0, 0.7, 0.85, 0.8)
	_ring.scale = Vector2.ONE * (r * 0.5 / ring_px * 2.0)
	_sparks.initial_velocity_min = r * 0.8
	_sparks.initial_velocity_max = r * 3.0
	_sparks.restart()
	_sparks.emitting = true

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_flash, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_ring, "scale", Vector2.ONE * (r * 2.8 / ring_px * 2.0), 0.7) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_ring, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	for i: int in range(HEARTS):
		_float_heart(_hearts[i], i, r)
	_tween.tween_callback(_on_done).set_delay(DURATION)


## One tiny heart: pops in near the centre, drifts up with a little sideways sway, fades out.
func _float_heart(h: Sprite2D, i: int, r: float) -> void:
	var start := Vector2(_rng.randf_range(-r * 0.6, r * 0.6), _rng.randf_range(-4.0, 6.0))
	var rise: float = _rng.randf_range(55.0, 105.0) * (0.6 if ShowSettings.reduce_motion else 1.0)
	var sway: float = _rng.randf_range(-16.0, 16.0)
	var delay: float = 0.08 * float(i)
	var size: float = _rng.randf_range(0.2, 0.32)
	h.visible = true
	h.position = start
	h.scale = Vector2.ZERO
	h.rotation = _rng.randf_range(-0.4, 0.4)
	h.modulate = Color(1.0, _rng.randf_range(0.5, 0.8), _rng.randf_range(0.65, 0.9), 0.0)
	_tween.tween_property(h, "scale", Vector2.ONE * size, 0.3).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(h, "modulate:a", 0.95, 0.25).set_delay(delay)
	_tween.tween_property(h, "position", start + Vector2(sway, -rise), 1.5).set_delay(delay) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(h, "modulate:a", 0.0, 0.6).set_delay(delay + 1.0)


func _on_done() -> void:
	_active = false
	_flash.visible = false
	_ring.visible = false
	for h: Sprite2D in _hearts:
		h.visible = false
	finished.emit()
