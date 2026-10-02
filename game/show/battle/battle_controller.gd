class_name BattleController
extends Node2D
## Wires the deterministic simulation to the show layer for a playable 2-player, pass-and-play
## match. The simulation is the single source of truth: this controller submits `fire`
## actions, then *plays back* the returned Timeline (docs/ARCHITECTURE.md section 10) against
## its own display copy of the terrain and the TankViews, and finally verifies that the display
## matches the authoritative state.
##
## Timing: events carry `tick` (ticks since the action started, 60/s). Playback advances a
## playhead by delta * 60 * speed and dispatches every event whose *presentation tick* has been
## reached. Impact consequences are staggered a little (carve now, settle/fall shortly after,
## turn banner last) so the player can follow cause and effect; this only moves the visuals in
## time, never changes outcomes. `instant` mode (tests) applies a whole timeline at once.
##
## Floats and non-determinism are fine here: the seed is just an input to the simulation.

signal timeline_finished
signal round_finished(winner: int)
signal match_finished
signal toast_shown(text: String)

const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const WEAPON: String = "pulse_missile"
const TPS: float = float(SimConstants.TICKS_PER_SECOND)
## Presentation offsets in ticks (see class comment).
const SETTLE_DELAY: int = 14
const POST_DELAY: int = 46
const END_HOLD_TICKS: int = 42
const SHORT_HOLD_TICKS: int = 18
const POPUP_POOL: int = 6
const FX_POOL: int = 3
const SHAKE_PER_RADIUS: float = 1.0 / 80.0

# --- scene nodes ---
@onready var _sky: NeonSky = $Sky
@onready var _world: Node2D = $World
@onready var _terrain_view: TerrainView = $World/Terrain
@onready var _trail: ShellTrail = $World/ShellTrail
@onready var _camera: CameraShake = $Camera
@onready var _hud: BattleHud = $HudLayer/Hud
@onready var _overlay_layer: CanvasLayer = $OverlayLayer

# --- model (authoritative state + display copies) ---
var state: MatchState = null
var display_terrain: Terrain = null
var round_wins: PackedInt32Array = PackedInt32Array()
var mismatch_count: int = 0

# --- configuration (set via configure() before the node enters the tree) ---
var _rounds: int = 3
var _seed: int = 0
var _instant: bool = false
var _configured: bool = false

# --- views ---
var _tank_views: Array[TankView] = []
var _fx: Array[Explosion] = []
var _fx_next: int = 0
var _popups: Array[DamagePopup] = []
var _popup_next: int = 0
var _preview: TrajectoryPreview = null
var _toast: Toast = null
var _pause_overlay: PauseOverlay = null
var _round_overlay: RoundEndOverlay = null
var _match_overlay: MatchEndOverlay = null
var _fall_tweens: Array[Tween] = []

# --- aim (per tank, local to the show layer) ---
var _aim_angle: PackedInt32Array = PackedInt32Array()
var _aim_power: PackedInt32Array = PackedInt32Array()

# --- playback ---
var _events: Array[Dictionary] = []
var _ev_i: int = 0
var _playhead: float = 0.0
var _end_tick: float = 0.0
var _playing: bool = false
var _busy: bool = false
var _speed: float = 1.0
var _shell_active: bool = false
var _shell_points: int = 0
var _round_winner: int = -1
var _timelines_played: int = 0

# --- debug hooks (ShotArgs) ---
var _elapsed: float = 0.0
var _auto_timer: float = 0.0
var _auto_fire_pending: bool = false


func _init() -> void:
	# Before children's _ready so the HUD sees the emulated DPI.
	ShotArgs.parse()


## Test/automation entry: call before add_child(). seed 0 = random. instant = no animation.
func configure(rounds: int, seed_value: int, instant: bool = false) -> void:
	_rounds = rounds
	_seed = seed_value
	_instant = instant
	_configured = true


func _ready() -> void:
	if not _configured:
		_rounds = ShotArgs.rounds if ShotArgs.rounds > 0 else BattleConfig.rounds
		_seed = ShotArgs.seed_value if ShotArgs.seed_value != 0 else BattleConfig.seed_value
		_instant = BattleConfig.instant
	# We handle the Android back button ourselves (opens the pause menu).
	get_tree().set_quit_on_go_back(false)
	_speed = ShowSettings.playback_speed if ShotArgs.speed <= 0.0 else ShotArgs.speed
	_build_support_nodes()
	_hud.angle_changed.connect(_on_hud_angle)
	_hud.power_changed.connect(_on_hud_power)
	_hud.fire_pressed.connect(func() -> void: fire_current())
	_hud.pause_pressed.connect(open_pause)
	_hud.speed_pressed.connect(toggle_speed)
	_hud.set_speed(_speed)
	get_viewport().size_changed.connect(_frame_camera)
	_frame_camera()
	_start_match()
	_auto_fire_pending = ShotArgs.auto_fire
	_auto_timer = 0.4
	ShotHook.attach(self)


func _exit_tree() -> void:
	# Never leave the whole tree paused behind us.
	if is_inside_tree() and get_tree().paused:
		get_tree().paused = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_paused():
			close_pause()
		else:
			open_pause()


# ======================================================================================
# Setup
# ======================================================================================

func _build_support_nodes() -> void:
	_preview = TrajectoryPreview.new()
	_preview.name = "TrajectoryPreview"
	_preview.visible = false
	_world.add_child(_preview)
	_world.move_child(_preview, _trail.get_index())
	var fx_scene: PackedScene = load("res://show/fx/explosion.tscn")
	for i: int in range(FX_POOL):
		var e: Explosion = fx_scene.instantiate()
		e.name = "Explosion%d" % i
		_world.add_child(e)
		_fx.append(e)
	for i: int in range(POPUP_POOL):
		var p := DamagePopup.new()
		p.name = "Popup%d" % i
		_world.add_child(p)
		_popups.append(p)
	_toast = Toast.new()
	_toast.name = "Toast"
	_hud.get_parent().add_child(_toast)
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay = PauseOverlay.new()
	_pause_overlay.resume_pressed.connect(close_pause)
	_pause_overlay.restart_pressed.connect(restart_match)
	_pause_overlay.quit_pressed.connect(quit_to_title)
	_overlay_layer.add_child(_pause_overlay)
	_round_overlay = RoundEndOverlay.new()
	_round_overlay.next_round_pressed.connect(next_round)
	_overlay_layer.add_child(_round_overlay)
	_match_overlay = MatchEndOverlay.new()
	_match_overlay.new_match_pressed.connect(restart_match)
	_match_overlay.title_pressed.connect(quit_to_title)
	_overlay_layer.add_child(_match_overlay)


func _frame_camera() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var f: Dictionary = BattleFraming.frame(vis)
	_camera.zoom = Vector2.ONE * float(f["zoom"])
	_camera.position = f["center"] as Vector2


func _start_match() -> void:
	var settings := MatchSettings.new()
	settings.seed = _seed if _seed != 0 else int(randi())
	settings.num_tanks = 2
	settings.rounds = _rounds
	settings.wind_max = 100
	state = Simulation.new_match(settings)
	round_wins = PackedInt32Array()
	round_wins.resize(settings.num_tanks)
	round_wins.fill(0)
	mismatch_count = 0
	_round_winner = -1
	_close_overlays()
	for v: TankView in _tank_views:
		v.queue_free()
	_tank_views.clear()
	for i: int in range(state.tanks.size()):
		var v: TankView = (load("res://show/tank_view.tscn") as PackedScene).instantiate()
		v.name = "Tank%d" % i
		_world.add_child(v)
		_tank_views.append(v)
	_rebuild_display()
	_hud.set_wind(state.wind)
	_apply_initial_aim_override()
	_begin_turn_ui()
	_set_busy(false)


## Rebuilds everything that mirrors the state: terrain copy, tank views, per-tank aim.
func _rebuild_display() -> void:
	display_terrain = state.terrain.duplicate_terrain()
	if _terrain_view.world_width == 0:
		_terrain_view.setup(display_terrain.cells, display_terrain.width, display_terrain.height)
	else:
		_terrain_view.update_cells(display_terrain.cells)
	_aim_angle.resize(state.tanks.size())
	_aim_power.resize(state.tanks.size())
	for t: TankState in state.tanks:
		var v: TankView = _tank_views[t.id]
		v.set_color_index(t.color_index)
		v.position = Vector2(float(t.x), float(t.y))
		v.set_dead(not t.alive)
		v.set_health(t.health, SimConstants.MAX_HEALTH)
		v.set_angle_tenths(t.angle)
		_aim_angle[t.id] = t.angle
		_aim_power[t.id] = t.power
	_trail.clear()
	_shell_active = false


func _apply_initial_aim_override() -> void:
	if ShotArgs.aim_angle >= 0:
		_aim_angle[state.current_tank] = ShotArgs.aim_angle
		_aim_power[state.current_tank] = ShotArgs.aim_power
		_tank_views[state.current_tank].set_angle_tenths(ShotArgs.aim_angle)


## HUD + preview for whoever's turn it is now.
func _begin_turn_ui() -> void:
	var id: int = state.current_tank
	_hud.show_turn(id)
	_hud.set_angle_tenths(_aim_angle[id])
	_hud.set_power(_aim_power[id])
	_request_preview()


# ======================================================================================
# Public API (also used by tests and the auto-play hooks)
# ======================================================================================

func get_state() -> MatchState:
	return state


func get_tank_view(i: int) -> TankView:
	return _tank_views[i]


func get_hud() -> BattleHud:
	return _hud


func get_preview() -> TrajectoryPreview:
	return _preview


func get_pause_overlay() -> PauseOverlay:
	return _pause_overlay


func get_round_overlay() -> RoundEndOverlay:
	return _round_overlay


func get_match_overlay() -> MatchEndOverlay:
	return _match_overlay


func get_toast() -> Toast:
	return _toast


func get_terrain_view() -> TerrainView:
	return _terrain_view


func get_aim(tank_id: int) -> Vector2i:
	return Vector2i(_aim_angle[tank_id], _aim_power[tank_id])


func get_speed() -> float:
	return _speed


func is_busy() -> bool:
	return _busy


func is_paused() -> bool:
	return _pause_overlay != null and _pause_overlay.visible


func timelines_played() -> int:
	return _timelines_played


## Sets the aim of the tank whose turn it is (ignored while input is locked).
func set_aim(angle: int, power: int) -> void:
	if _busy:
		return
	var id: int = state.current_tank
	_aim_angle[id] = clampi(angle, 0, SimConstants.MAX_ANGLE)
	_aim_power[id] = clampi(power, 0, SimConstants.MAX_POWER)
	_tank_views[id].set_angle_tenths(_aim_angle[id])
	_hud.set_angle_tenths(_aim_angle[id])
	_hud.set_power(_aim_power[id])
	_request_preview()


## Fires the current tank with its remembered aim. Returns "" on success, or the validation
## error key (nothing happens in that case except a toast). "busy" if input is locked.
func fire_current() -> String:
	if _busy:
		return "busy"
	var id: int = state.current_tank
	var action: Dictionary = {
		"kind": "fire", "tank": id, "angle": _aim_angle[id], "power": _aim_power[id], "weapon": WEAPON,
	}
	var err: String = Simulation.validate_action(state, action)
	if err != "":
		_show_toast(tr("ERR_" + err.to_upper()))
		return err
	var events: Array[Dictionary] = Simulation.apply_action(state, action)
	_play(events)
	return ""


## NEXT ROUND: starts the next round and plays round_start / wind / turn.
func next_round() -> void:
	if state.phase != SimConstants.PHASE_ROUND_OVER:
		return
	_round_overlay.close()
	var events: Array[Dictionary] = Simulation.start_round(state)
	_play(events)


## New match with the same settings. A fixed seed (tests, --seed) replays it; otherwise a new
## random seed is drawn.
func restart_match() -> void:
	close_pause()
	_cancel_playback()
	_start_match()


func quit_to_title() -> void:
	close_pause()
	get_tree().change_scene_to_file(TITLE_SCENE)


func open_pause() -> void:
	if is_paused():
		return
	_pause_overlay.open_for(state.round_index + 1, state.settings.rounds)
	_preview.hide_preview()
	get_tree().paused = true


func close_pause() -> void:
	if _pause_overlay != null:
		_pause_overlay.close()
	if is_inside_tree():
		get_tree().paused = false
	_request_preview()


func toggle_speed() -> void:
	set_speed(2.0 if _speed < 1.5 else 1.0)


func set_speed(s: float) -> void:
	_speed = s
	ShowSettings.playback_speed = s
	_hud.set_speed(s)


## Compares the display copy with the authoritative state; snaps the display on mismatch.
func check_consistency() -> bool:
	var ok: bool = true
	if display_terrain.cells != state.terrain.cells:
		ok = false
		var diff: int = 0
		var first: int = -1
		for i: int in range(state.terrain.cells.size()):
			if display_terrain.cells[i] != state.terrain.cells[i]:
				diff += 1
				if first < 0:
					first = i
		push_error("BattleController: display terrain differs from state in %d cells (first index %d = x %d, y %d)"
				% [diff, first, first / state.terrain.height, first % state.terrain.height])
	for t: TankState in state.tanks:
		var v: TankView = _tank_views[t.id]
		var want := Vector2(float(t.x), float(t.y))
		if v.position != want or v.get_health() != t.health or v.is_dead() == t.alive:
			ok = false
			push_error("BattleController: tank %d view (pos %s, hp %d, dead %s) differs from state (pos %s, hp %d, alive %s)"
					% [t.id, v.position, v.get_health(), v.is_dead(), want, t.health, t.alive])
	if not ok:
		mismatch_count += 1
		_snap_display_to_state()
	return ok


func _snap_display_to_state() -> void:
	for tw: Tween in _fall_tweens:
		if tw.is_valid():
			tw.kill()
	_fall_tweens.clear()
	_rebuild_display()
	_hud.set_wind(state.wind)


# ======================================================================================
# Playback
# ======================================================================================

func _play(events: Array[Dictionary]) -> void:
	_events = events
	_ev_i = 0
	_playhead = 0.0
	_timelines_played += 1
	_round_winner = -1
	_set_busy(true)
	_preview.hide_preview()
	var last: int = 0
	var impact: bool = false
	for e: Dictionary in _events:
		last = maxi(last, _present_tick(e))
		if e["type"] == "explosion" or e["type"] == "round_end":
			impact = true
	_end_tick = float(last + (END_HOLD_TICKS if impact else SHORT_HOLD_TICKS))
	if _instant:
		while _ev_i < _events.size():
			_dispatch(_events[_ev_i])
			_ev_i += 1
		_finish_playback()
	else:
		_playing = true


func _cancel_playback() -> void:
	_playing = false
	_events = []
	_ev_i = 0
	_trail.clear()
	_shell_active = false
	for tw: Tween in _fall_tweens:
		if tw.is_valid():
			tw.kill()
	_fall_tweens.clear()


## Tick (since the action started) at which an event is *shown*; monotone in event order.
func _present_tick(e: Dictionary) -> int:
	var t: int = e["tick"]
	match e["type"]:
		"terrain_settle", "tank_fall", "tank_destroyed":
			return t + SETTLE_DELAY
		"damage":
			return t + (SETTLE_DELAY if e["cause"] == "fall" else 0)
		"wind", "turn", "round_end":
			return t + (POST_DELAY if t > 0 else 0)
	return t


func _process(delta: float) -> void:
	_elapsed += delta
	if state == null:
		return
	var t: TankView = _tank_views[state.current_tank]
	_hud.set_aim_pivot(get_viewport().get_canvas_transform() * (t.position + Vector2(0, -TankView.TANK_H * 0.5) * TankView.VISUAL_SCALE))
	_sky.set_parallax(_camera.get_screen_center_position())
	if _playing:
		_playhead += delta * TPS * _speed
		_advance_playback()
	_run_auto_hooks(delta)


func _advance_playback() -> void:
	while _ev_i < _events.size() and float(_present_tick(_events[_ev_i])) <= _playhead:
		_dispatch(_events[_ev_i])
		_ev_i += 1
	if _shell_active:
		_trail.set_progress(clampf(_playhead - 1.0, 0.0, float(_shell_points - 1)))
	if _playhead >= _end_tick and _ev_i >= _events.size():
		_finish_playback()


func _finish_playback() -> void:
	_playing = false
	_shell_active = false
	_trail.clear()
	check_consistency()
	timeline_finished.emit()
	match state.phase:
		SimConstants.PHASE_ROUND_OVER:
			_round_overlay.show_result(_round_winner, round_wins, state.round_index + 1, state.settings.rounds)
			round_finished.emit(_round_winner)
		SimConstants.PHASE_MATCH_OVER:
			_match_overlay.show_result(round_wins)
			round_finished.emit(_round_winner)
			match_finished.emit()
		_:
			_set_busy(false)
			_begin_turn_ui()


func _dispatch(e: Dictionary) -> void:
	match e["type"]:
		"round_start":
			_rebuild_display()
		"projectile":
			_start_shell(e["path"])
		"projectile_end":
			_shell_active = false
			_trail.clear()
		"explosion":
			_on_explosion(e)
		"terrain_carve":
			display_terrain.carve_circle(e["x"], e["y"], e["radius"])
			_terrain_view.update_cells(display_terrain.cells)
		"terrain_settle":
			display_terrain.settle(e["x0"], e["x1"])
			_terrain_view.update_cells(display_terrain.cells)
		"damage":
			_on_damage(e)
		"tank_fall":
			_on_tank_fall(e)
		"tank_destroyed":
			_on_tank_destroyed(e)
		"wind":
			_hud.set_wind(e["wind"])
		"turn":
			var id: int = e["tank"]
			_hud.show_turn(id)
			_hud.set_angle_tenths(_aim_angle[id])
			_hud.set_power(_aim_power[id])
		"round_end":
			_round_winner = e["winner"]
			if _round_winner >= 0:
				round_wins[_round_winner] += 1
		# "fire" has no presentation of its own; the shell appears with "projectile".


func _start_shell(path: PackedInt32Array) -> void:
	if _instant:
		return
	var n: int = path.size() / 2
	var pts := PackedVector2Array()
	pts.resize(maxi(n, 2))
	var inv: float = 1.0 / float(FixedMath.ONE)
	for i: int in range(n):
		pts[i] = Vector2(float(path[i * 2]) * inv, float(path[i * 2 + 1]) * inv)
	if n < 2:
		pts[1] = pts[0]
	_shell_points = pts.size()
	_shell_active = true
	_trail.play(pts)  # self-driven start sets the path; we then drive it by the playhead
	_trail.set_process(false)
	_trail.set_progress(0.0)


func _on_explosion(e: Dictionary) -> void:
	if _instant:
		return
	var radius: float = float(e["radius"])
	_next_fx().play(Vector2(float(e["x"]), float(e["y"])), radius)
	_camera.shake(clampf(radius * SHAKE_PER_RADIUS, 0.15, 0.9))
	_haptic(clampi(roundi(radius * 2.0), 15, 90))


func _on_damage(e: Dictionary) -> void:
	var id: int = e["tank"]
	_tank_views[id].set_health(e["health"], SimConstants.MAX_HEALTH)
	if not _instant:
		var v: TankView = _tank_views[id]
		var at: Vector2 = v.position + Vector2(0, -52.0 * TankView.VISUAL_SCALE)
		_popups[_popup_next].pop("-%d" % int(e["amount"]), NeonPalette.tank_color(state.tanks[id].color_index), at)
		_popup_next = (_popup_next + 1) % _popups.size()


func _on_tank_fall(e: Dictionary) -> void:
	var v: TankView = _tank_views[e["tank"]]
	var to := Vector2(v.position.x, float(e["to_y"]))
	if _instant:
		v.position = to
		return
	var tw: Tween = create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(v, "position", to, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tweens.append(tw)


func _on_tank_destroyed(e: Dictionary) -> void:
	var v: TankView = _tank_views[e["tank"]]
	v.set_dead(true)
	if _instant:
		return
	_next_fx().play(v.position + Vector2(0, -TankView.TANK_H * TankView.VISUAL_SCALE * 0.5), 58.0)
	_camera.shake(0.7)
	_haptic(160)


func _next_fx() -> Explosion:
	var e: Explosion = _fx[_fx_next]
	_fx_next = (_fx_next + 1) % _fx.size()
	return e


func _haptic(ms: int) -> void:
	if ShowSettings.haptics and not _instant:
		Input.vibrate_handheld(ms)


# ======================================================================================
# UI glue
# ======================================================================================

func _set_busy(b: bool) -> void:
	_busy = b
	_hud.set_fire_enabled(not b)
	_hud.set_controls_locked(b)


func _close_overlays() -> void:
	_round_overlay.close()
	_match_overlay.close()


func _show_toast(text: String) -> void:
	_toast.show_message(text)
	toast_shown.emit(text)


func _request_preview() -> void:
	if state == null or _preview == null:
		return
	var id: int = state.current_tank
	if _busy or state.phase != SimConstants.PHASE_AIM or ShowSettings.trajectory_preview == ShowSettings.PREVIEW_OFF:
		_preview.hide_preview()
		return
	_preview.request(state, id, _aim_angle[id], _aim_power[id])


func _on_hud_angle(a: int) -> void:
	if _busy:
		return
	var id: int = state.current_tank
	_aim_angle[id] = a
	_tank_views[id].set_angle_tenths(a)
	_request_preview()


func _on_hud_power(p: int) -> void:
	if _busy:
		return
	_aim_power[state.current_tank] = p
	_request_preview()


func _run_auto_hooks(delta: float) -> void:
	if _busy or is_paused():
		if ShotArgs.auto_play and ShotArgs.auto_next and not _playing and state.phase == SimConstants.PHASE_ROUND_OVER:
			_auto_timer -= delta
			if _auto_timer <= 0.0:
				_auto_timer = 0.6
				next_round()
		return
	if state.phase != SimConstants.PHASE_AIM:
		return
	_auto_timer -= delta
	if _auto_timer > 0.0:
		return
	if ShotArgs.auto_play:
		var id: int = state.current_tank
		var shot: Vector2i = AutoShot.find_shot(state, id)
		set_aim(shot.x, shot.y)
		fire_current()
		_auto_timer = 0.5
	elif ShotArgs.open_pause and _elapsed > 0.5 and not is_paused():
		ShotArgs.open_pause = false
		open_pause()
	elif _auto_fire_pending:
		_auto_fire_pending = false
		fire_current()
