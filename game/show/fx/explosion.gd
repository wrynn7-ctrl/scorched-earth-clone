class_name Explosion
extends Node2D
## Explosion: additive flash, expanding shockwave ring and a CPUParticles2D spark burst.
##
## CPUParticles2D rather than GPUParticles2D: on GLES3 mobile the burst is only ~40
## particles, so CPU simulation is trivial, it avoids the transform-feedback/shader-compile
## hitch on the first explosion, and it behaves identically on every Android GL driver.
## One node is reusable: call play() again to re-trigger.

signal finished

const PARTICLES: int = 40
const DURATION: float = 0.9

var _flash: Sprite2D = null
var _ring: Sprite2D = null
var _sparks: CPUParticles2D = null
var _tween: Tween = null


func _ready() -> void:
	_flash = Sprite2D.new()
	_flash.name = "Flash"
	_flash.texture = FxTextures.glow()
	_flash.material = FxTextures.additive()
	_flash.modulate = NeonPalette.HOT
	add_child(_flash)
	_ring = Sprite2D.new()
	_ring.name = "Ring"
	_ring.texture = FxTextures.ring()
	_ring.material = FxTextures.additive()
	_ring.modulate = NeonPalette.CYAN
	add_child(_ring)
	_sparks = CPUParticles2D.new()
	_sparks.name = "Sparks"
	_sparks.amount = PARTICLES
	_sparks.one_shot = true
	_sparks.explosiveness = 1.0
	_sparks.emitting = false
	_sparks.lifetime = 0.7
	_sparks.texture = FxTextures.glow()
	_sparks.material = FxTextures.additive()
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.gravity = Vector2(0, 260)
	_sparks.damping_min = 40.0
	_sparks.damping_max = 90.0
	_sparks.scale_amount_min = 0.08
	_sparks.scale_amount_max = 0.22
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([NeonPalette.HOT, NeonPalette.SUNSET, Color(NeonPalette.MAGENTA, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	_sparks.color_ramp = ramp
	add_child(_sparks)
	_flash.visible = false
	_ring.visible = false


## Plays at `at` (parent coordinates) with the blast radius in world units.
func play(at: Vector2, radius: float) -> void:
	position = at
	if _tween != null:
		_tween.kill()
	var r: float = maxf(4.0, radius)
	var gl_px: float = float(FxTextures.glow().get_width())
	var ring_px: float = float(FxTextures.ring().get_width())
	var flash_peak: float = 0.3 if ShowSettings.reduce_flashing else 1.0

	_flash.visible = true
	_flash.scale = Vector2.ONE * (r * 2.6 / gl_px)
	_flash.modulate.a = flash_peak
	_ring.visible = true
	_ring.scale = Vector2.ONE * (r * 0.4 / ring_px * 2.0)
	_ring.modulate.a = 0.9

	_sparks.initial_velocity_min = r * 1.2
	_sparks.initial_velocity_max = r * 4.5
	_sparks.restart()
	_sparks.emitting = true

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_flash, "modulate:a", 0.0, 0.22).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_flash, "scale", _flash.scale * 1.4, 0.22)
	_tween.tween_property(_ring, "scale", Vector2.ONE * (r * 3.2 / ring_px * 2.0), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(_ring, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	_tween.chain().tween_interval(DURATION - 0.55)
	_tween.chain().tween_callback(_on_done)


func _on_done() -> void:
	_flash.visible = false
	_ring.visible = false
	finished.emit()
