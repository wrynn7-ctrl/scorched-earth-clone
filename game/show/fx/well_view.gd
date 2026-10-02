class_name WellView
extends Node2D
## A gravity well (Singularity Seed): a swirling glowing vortex plus a faint ring at its pull
## radius, so everyone can see where shells will bend. It persists between turns until
## `well_off`. The swirl is drawn once and rotated by a cheap per-frame rotation; with reduce
## motion it stays still.

var owner_id: int = -1
var expires_turn: int = 0

var _radius: float = 300.0
var _swirl: Node2D = null
var _core: Node2D = null
var _t: float = 0.0


func _ready() -> void:
	z_index = 1
	var ring := Node2D.new()
	ring.name = "Ring"
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(NeonPalette.VIOLET, 0.28), 2.0, true)
		ring.draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 96, Color(NeonPalette.VIOLET, 0.07), 10.0, true))
	add_child(ring)
	_swirl = Node2D.new()
	_swirl.name = "Swirl"
	_swirl.material = FxTextures.additive()
	_swirl.draw.connect(_draw_swirl)
	add_child(_swirl)
	_core = Node2D.new()
	_core.name = "Core"
	_core.material = FxTextures.additive()
	_core.draw.connect(func() -> void:
		var glow: Texture2D = FxTextures.glow()
		_core.draw_texture_rect(glow, Rect2(Vector2.ONE * -34.0, Vector2.ONE * 68.0), false, Color(0.7, 0.4, 1.0, 0.9))
		_core.draw_texture_rect(glow, Rect2(Vector2.ONE * -14.0, Vector2.ONE * 28.0), false, Color(1, 1, 1, 0.95)))
	add_child(_core)
	set_process(not ShowSettings.reduce_motion)


## Places the well; `radius` is the pull radius in cells (faint ring).
func place(at: Vector2, radius: float, owner: int, expires: int) -> void:
	position = at
	_radius = radius
	owner_id = owner
	expires_turn = expires
	if is_inside_tree():
		for c: Node in get_children():
			if c is Node2D:
				(c as Node2D).queue_redraw()


func get_pull_radius() -> float:
	return _radius


func _process(delta: float) -> void:
	_t += delta
	_swirl.rotation = _t * 2.2
	var pulse: float = 1.0 + 0.12 * sin(_t * 3.0)
	_core.scale = Vector2.ONE * pulse


func _draw_swirl() -> void:
	for arm: int in range(3):
		var pts := PackedVector2Array()
		for i: int in range(21):
			var u: float = float(i) / 20.0
			var a: float = u * TAU * 0.9 + float(arm) * TAU / 3.0
			pts.append(Vector2(cos(a), sin(a)) * (8.0 + 62.0 * u))
		_swirl.draw_polyline(pts, Color(NeonPalette.VIOLET, 0.25), 9.0, true)
		_swirl.draw_polyline(pts, Color(0.75, 0.55, 1.0, 0.85), 2.5, true)
