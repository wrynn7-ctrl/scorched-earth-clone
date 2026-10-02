class_name DemoBattlefield
extends Node2D
## Standalone show-layer demo with FAKE data (no simulation): a sine-hill terrain built here,
## two tanks, wind, and the touch HUD. Drag to aim the active tank; FIRE flies a fake
## parabola, explodes and carves the terrain. Floats are fine here (visual layer only).
##
## Debug/screenshot user args (after `--`):
##   --shot=<png>       save the viewport to <png> after --shot-time seconds, then quit
##   --shot-time=<s>    default 1.5
##   --auto-fire        fire automatically shortly after start
##   --dpi=<n>          emulate a screen density (e.g. 500 for a phone) for UiScale

const W: int = 1600
const H: int = 900
const TANK_HALF_W: int = 12
const TANK_H_CELLS: int = 12
const BLAST_RADIUS: int = 28
const GRAVITY: float = 0.15
const MAX_SPEED: float = 17.0
const WIND_ACCEL_PER_UNIT: float = 13.0 / 65536.0
const MAX_TICKS: int = 1500
const SHELL_SAMPLES_PER_SEC: float = 150.0

var _cells: PackedByteArray = PackedByteArray()
var _tank_x: Array[int] = [320, 1260]
var _angles: Array[int] = [450, 1350]
var _powers: Array[int] = [600, 600]
var _health: Array[int] = [100, 100]
var _active: int = 0
var _wind: int = 28
var _busy: bool = false
var _elapsed: float = 0.0
var _shot_path: String = ""
var _shot_time: float = 1.5
var _auto_fire_at: float = -1.0
var _shot_taken: bool = false
var _rng := RandomNumberGenerator.new()

@onready var _sky: NeonSky = $Sky
@onready var _terrain: TerrainView = $World/Terrain
@onready var _tanks: Array[TankView] = [$World/Tank0, $World/Tank1]
@onready var _trail: ShellTrail = $World/ShellTrail
@onready var _explosion: Explosion = $World/Explosion
@onready var _camera: CameraShake = $Camera
@onready var _hud: BattleHud = $HudLayer/Hud


func _init() -> void:
	# Before children's _ready so the HUD sees the emulated DPI.
	_parse_user_args()


func _ready() -> void:
	_rng.seed = 7
	_build_terrain()
	_terrain.setup(_cells, W, H)
	for i: int in range(2):
		_tanks[i].set_color_index(i)
		_tanks[i].set_angle_tenths(_angles[i])
		_tanks[i].set_health(_health[i], 100)
	_seat_tanks()
	_hud.angle_changed.connect(_on_angle_changed)
	_hud.power_changed.connect(func(p: int) -> void: _powers[_active] = p)
	_hud.fire_pressed.connect(_on_fire)
	_trail.finished.connect(_on_trail_finished)
	_hud.set_wind(_wind)
	_begin_turn(0)
	get_viewport().size_changed.connect(_frame_camera)
	_frame_camera()


func _process(delta: float) -> void:
	_elapsed += delta
	# Keep the aim pivot glued to the active tank's screen position (camera may move/shake).
	var t: TankView = _tanks[_active]
	_hud.set_aim_pivot(get_viewport().get_canvas_transform() * (t.position + Vector2(0, -TANK_H_CELLS) * TankView.VISUAL_SCALE))
	_sky.set_parallax(_camera.get_screen_center_position())
	if _auto_fire_at >= 0.0 and _elapsed >= _auto_fire_at and not _busy:
		_auto_fire_at = -1.0
		_on_fire()
	if _shot_path != "" and not _shot_taken and _elapsed >= _shot_time:
		_shot_taken = true
		_take_screenshot()


func _parse_user_args() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-time="):
			_shot_time = a.substr(12).to_float()
		elif a == "--auto-fire":
			_auto_fire_at = 0.4
		elif a.begins_with("--dpi="):
			UiScale.dpi_override = a.substr(6).to_float()


func _take_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(_shot_path)
	print("demo: saved screenshot ", _shot_path, " size=", img.get_size(), " err=", err)
	get_tree().quit()


func _frame_camera() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var f: Dictionary = BattleFraming.frame(vis)
	_camera.zoom = Vector2.ONE * float(f["zoom"])
	_camera.position = f["center"] as Vector2


# --- Fake terrain -------------------------------------------------------------------

func _surface_for(x: int) -> int:
	var fx: float = float(x)
	var y: float = 560.0 + 85.0 * sin(fx * 0.0065) + 38.0 * sin(fx * 0.019 + 1.0) + 14.0 * sin(fx * 0.05 + 2.0)
	return clampi(int(y), 270, 765)


func _build_terrain() -> void:
	_cells.resize(W * H)
	_cells.fill(0)
	for x: int in range(W):
		var s: int = _surface_for(x)
		for y: int in range(s, H):
			# Material bands by depth below the surface (1..15), slightly wavy.
			var depth: int = y - s + int(6.0 * sin(float(x) * 0.03))
			_cells[x * H + y] = clampi(1 + depth / 28, 1, 15)


func _is_solid(x: int, y: int) -> bool:
	if y >= H:
		return true
	if x < 0 or x >= W or y < 0:
		return false
	return _cells[x * H + y] != 0


func _top_solid(x: int) -> int:
	for y: int in range(H):
		if _cells[x * H + y] != 0:
			return y
	return H


func _seat_tanks() -> void:
	for i: int in range(2):
		var gy: int = H
		for dx: int in range(-TANK_HALF_W, TANK_HALF_W):
			gy = mini(gy, _top_solid(clampi(_tank_x[i] + dx, 0, W - 1)))
		_tanks[i].position = Vector2(_tank_x[i], gy)


func _carve(cx: int, cy: int, r: int) -> void:
	for x: int in range(maxi(0, cx - r), mini(W, cx + r + 1)):
		var dx: int = x - cx
		for y: int in range(maxi(0, cy - r), mini(H, cy + r + 1)):
			var dy: int = y - cy
			if dx * dx + dy * dy <= r * r:
				_cells[x * H + y] = 0


# --- Turn flow ----------------------------------------------------------------------

func _begin_turn(i: int) -> void:
	_active = i
	_busy = false
	_hud.show_turn(i, "")
	_hud.set_angle_tenths(_angles[i])
	_hud.set_power(_powers[i])
	_hud.set_fire_enabled(true)


func _on_angle_changed(a: int) -> void:
	_angles[_active] = a
	_tanks[_active].set_angle_tenths(a)


func _on_fire() -> void:
	if _busy:
		return
	_busy = true
	_hud.set_fire_enabled(false)
	var path: PackedVector2Array = _fake_flight()
	_trail.play(path, SHELL_SAMPLES_PER_SEC)
	_camera.shake(0.12)


## Float re-implementation of the planned ballistics, only to give the demo a believable arc.
func _fake_flight() -> PackedVector2Array:
	var tank: TankView = _tanks[_active]
	var a: float = deg_to_rad(float(_angles[_active]) / 10.0)
	var speed: float = float(_powers[_active]) * MAX_SPEED / 1000.0
	var pos: Vector2 = tank.position + Vector2(0, -TANK_H_CELLS) + Vector2(cos(a), -sin(a)) * 14.0
	var vel := Vector2(cos(a), -sin(a)) * speed
	var path := PackedVector2Array()
	path.append(pos)
	for tick: int in range(MAX_TICKS):
		vel.x += float(_wind) * WIND_ACCEL_PER_UNIT
		vel.y += GRAVITY
		pos += vel
		path.append(pos)
		if pos.x < 0.0 or pos.x >= float(W):
			break
		if _is_solid(int(pos.x), int(pos.y)):
			break
	return path


func _on_trail_finished() -> void:
	var path_end: Vector2 = _trail.head_position()
	var inside: bool = path_end.x >= 0.0 and path_end.x < float(W) and _is_solid(int(path_end.x), int(path_end.y))
	if inside:
		_impact(path_end)
	else:
		_next_turn()


func _impact(at: Vector2) -> void:
	_explosion.play(at, float(BLAST_RADIUS))
	_camera.shake(0.45)
	_carve(int(at.x), int(at.y), BLAST_RADIUS)
	_terrain.update_cells(_cells)
	for i: int in range(2):
		var centre: Vector2 = _tanks[i].position + Vector2(0, -TANK_H_CELLS * 0.5)
		var d: float = centre.distance_to(at) - float(TANK_HALF_W)
		if d < float(BLAST_RADIUS):
			_health[i] = maxi(0, _health[i] - maxi(1, int(55.0 * (float(BLAST_RADIUS) - d) / float(BLAST_RADIUS))))
			_tanks[i].set_health(_health[i], 100)
	_seat_tanks()
	for i: int in range(2):
		if _health[i] <= 0:
			_tanks[i].set_dead(true)
	get_tree().create_timer(0.9).timeout.connect(_next_turn)


func _next_turn() -> void:
	if _health[0] <= 0 or _health[1] <= 0:
		_restart_round()
	_wind = clampi(_wind + _rng.randi_range(-6, 6), -100, 100)
	_hud.set_wind(_wind)
	_begin_turn(1 - _active)


func _restart_round() -> void:
	_health = [100, 100]
	_build_terrain()
	_terrain.update_cells(_cells)
	for i: int in range(2):
		_tanks[i].set_dead(false)
		_tanks[i].set_health(100, 100)
	_seat_tanks()
