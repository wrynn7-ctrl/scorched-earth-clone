class_name TankThumb
extends Control
## A small live view of a skinned tank that scales itself to fit this control: the big preview in
## the studio (with a neon backdrop, a slowly sweeping turret and a pulsing glow), the strip that
## shows the skin in all eight player colours, and the cards of the skin list.
##
## It hosts a normal TankView in compact mode, so what you see is the same drawing code the battle
## uses, identity outline and emblem included.

## Emitted after the skin texture was (re)baked, so other views can share it.
signal baked(texture: Texture2D)

const TANK_VIEW: PackedScene = preload("res://show/tank_view.tscn")
## What has to fit: hull and barrel are about 36 units wide, the emblem sits 33 units up.
const FIT_W: float = 40.0
const FIT_H: float = 44.0
## Minimum seconds between two re-bakes while a slider is dragged.
const REBAKE_GAP: float = 0.07

var backdrop: bool = false
var animated: bool = false

var _holder: Node2D = null
var _view: TankView = null
var _pending: SkinData = null
var _has_pending: bool = false
var _since_bake: float = 1.0
var _t: float = 0.0
var _texture: Texture2D = null


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_holder = Node2D.new()
	_holder.name = "Holder"
	add_child(_holder)
	_view = TANK_VIEW.instantiate() as TankView
	_view.name = "Tank"
	_holder.add_child(_view)
	_view.set_compact(true)
	_view.set_angle_tenths(1050)
	set_process(false)


func _ready() -> void:
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


func get_view() -> TankView:
	return _view


func get_texture() -> Texture2D:
	return _texture


## Sets the high-resolution preview bake (studio) or a small one (cards).
func set_bake_ppu(ppu: int) -> void:
	_view.skin_ppu = ppu


## Shows `skin` now. `shared` skips the bake when another view already baked this skin.
func set_skin(skin: SkinData, shared: Texture2D = null) -> void:
	_has_pending = false
	_view.set_skin(skin, shared)
	_texture = _view.get_skin_texture()
	baked.emit(_texture)


## Shows `skin` soon: the bake waits until REBAKE_GAP has passed since the last one.
func request_skin(skin: SkinData) -> void:
	_pending = skin
	_has_pending = true
	_update_processing()


## Applies a pending skin immediately (tests, and the first show).
func flush() -> void:
	if _has_pending:
		set_skin(_pending)
		_since_bake = 0.0
		_update_processing()


func set_player(color_index: int, emblem_index: int) -> void:
	_view.set_look(color_index, emblem_index)


func set_turret_angle(tenths: int) -> void:
	_view.set_angle_tenths(tenths)


func set_animated(on: bool) -> void:
	animated = on
	if not on:
		_view.set_skin_glow_pulse(1.0)
	_update_processing()


func _update_processing() -> void:
	set_process(is_inside_tree() and (animated or _has_pending))


func _enter_tree() -> void:
	_update_processing()


func _process(delta: float) -> void:
	_since_bake += delta
	if _has_pending and _since_bake >= REBAKE_GAP:
		flush()
	if animated:
		_t += delta
		_animate()


## A slow turret sweep and a breathing glow; with reduce motion the tank holds still, and with
## reduced flashing the glow only breathes a little.
func _animate() -> void:
	if ShowSettings.reduce_motion:
		_view.set_angle_tenths(1050)
		_view.set_skin_glow_pulse(1.0)
		return
	_view.set_angle_tenths(900 + roundi(sin(_t * 0.55) * 420.0))
	var depth: float = 0.12 if ShowSettings.reduce_flashing else 0.4
	_view.set_skin_glow_pulse(1.0 - depth * (0.5 + 0.5 * sin(_t * 2.2)))


func _fit() -> void:
	if _holder == null:
		return
	var ground: float = size.y * 0.84 if backdrop else size.y - 2.0
	var s: float = minf(size.x / FIT_W, maxf(1.0, ground) / FIT_H)
	_holder.scale = Vector2.ONE * maxf(0.05, s) / TankView.VISUAL_SCALE
	_holder.position = Vector2(size.x * 0.5, ground)
	queue_redraw()


func _draw() -> void:
	if not backdrop:
		return
	var ground: float = size.y * 0.84
	draw_rect(Rect2(Vector2.ZERO, size), NeonPalette.BG_DEEP)
	draw_rect(Rect2(0, size.y * 0.35, size.x, ground - size.y * 0.35), Color(NeonPalette.BG_MID, 0.55))
	# A faint perspective grid under the tank: a neutral stage for any skin colour.
	var col := Color(NeonPalette.MAGENTA, 0.28)
	var vanish := Vector2(size.x * 0.5, ground)
	for i: int in range(-6, 7):
		draw_line(vanish, Vector2(size.x * 0.5 + float(i) * size.x * 0.28, size.y), col, 1.0, true)
	for k: int in range(1, 5):
		var y: float = ground + (size.y - ground) * pow(float(k) / 4.0, 1.7)
		draw_line(Vector2(0, y), Vector2(size.x, y), col, 1.0, true)
	draw_line(Vector2(0, ground), Vector2(size.x, ground), Color(NeonPalette.CYAN, 0.7), 2.0, true)
