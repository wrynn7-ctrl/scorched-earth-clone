extends GutTest
## The shot-follow camera: keeps a high shell in the picture, is smooth, returns to rest, and
## stands down with reduce motion / the setting off (the off-screen marker is the fallback).

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const FRAME: float = 1.0 / 60.0
# Visible rectangles (canvas units) of typical screens: 16:9 and 19.5:9 phones, a 4:3 tablet,
# and a 21:9 phone where the world is cropped to the minimum height.
const VIEWS: Array[Vector2] = [Vector2(1600, 900), Vector2(1950, 900), Vector2(1600, 1200), Vector2(2400, 900)]


var _old_size: Vector2i = Vector2i.ZERO


func before_each() -> void:
	_old_size = get_window().size


func after_each() -> void:
	get_window().size = _old_size
	ShowSettings.reset()
	CameraSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


## Per-tick positions of a shell fired from (x0, y0): the real gravity (0.15 cell/tick^2) and
## muzzle speed (17 cells/tick at power 1000), no wind, until it comes back down to y_end.
func _lob(angle_deg: float, power: int, x0: float, y0: float, y_end: float) -> PackedVector2Array:
	var speed: float = float(power) * 17.0 / 1000.0
	var v := Vector2(cos(deg_to_rad(angle_deg)), -sin(deg_to_rad(angle_deg))) * speed
	var p := Vector2(x0, y0)
	var out := PackedVector2Array()
	while out.size() < 1500:
		v.y += 0.15
		p += v
		out.append(p)
		if v.y > 0.0 and p.y >= y_end:
			break
	return out


## Plays the lob frame by frame like the battle does. Returns {worst: how far the shell got
## from being inside the rect (<= 0 means always inside), clamps, peak_pan, cam}.
func _fly(view: Vector2, path: PackedVector2Array, speed: float) -> Dictionary:
	var cam := FollowCam.new(view)
	var worst: float = -INF
	var peak: float = 0.0
	var playhead: float = 0.0
	var ticks_ahead: float = FollowCam.LOOKAHEAD_SECONDS * 60.0 * speed
	while playhead < float(path.size() - 1):
		playhead += speed
		var head: Vector2 = FollowCam.head_at(path, playhead)
		cam.update(FRAME, PackedVector2Array([head]), FollowCam.lookahead(path, playhead, ticks_ahead))
		var r: Rect2 = cam.get_visible_rect()
		worst = maxf(worst, maxf(r.position.y - head.y, head.y - r.end.y))
		peak = maxf(peak, cam.get_rest_center().y - cam.get_center().y)
	return {"worst": worst, "clamps": cam.clamp_hits, "peak": peak, "cam": cam}


func test_high_shell_stays_inside_the_visible_rect_on_every_screen() -> void:
	for view: Vector2 in VIEWS:
		for speed: float in [1.0, 2.0]:
			for angle: float in [90.0, 75.0, 60.0, 115.0]:
				var path: PackedVector2Array = _lob(angle, 1000, 700.0, 500.0, 600.0)
				var res: Dictionary = _fly(view, path, speed)
				var label: String = "%s speed %.0f angle %.0f" % [view, speed, angle]
				assert_lt(res["worst"] as float, 0.0, "shell inside the picture: " + label)
				assert_eq(res["clamps"], 0, "the safety clamp was not needed: " + label)
	# The straight-up lob really does leave the normal picture, so the camera had to move.
	var res2: Dictionary = _fly(Vector2(1600, 900), _lob(90.0, 1000, 700.0, 500.0, 600.0), 1.0)
	assert_gt(res2["peak"] as float, 300.0, "the camera panned up for a high lob")


func test_low_shot_does_not_move_the_camera() -> void:
	var cam := FollowCam.new(Vector2(1600, 900))
	var path: PackedVector2Array = _lob(40.0, 500, 300.0, 600.0, 650.0)
	var playhead: float = 0.0
	while playhead < float(path.size() - 1):
		playhead += 1.0
		cam.update(FRAME, PackedVector2Array([FollowCam.head_at(path, playhead)]),
				FollowCam.lookahead(path, playhead, 30.0))
		assert_true(cam.is_at_rest(), "a shot that stays in view leaves the framing alone")
	assert_eq(cam.get_center(), cam.get_rest_center())


func test_never_zooms_out_past_the_whole_world_width() -> void:
	for view: Vector2 in VIEWS:
		var res: Dictionary = _fly(view, _lob(90.0, 1000, 700.0, 500.0, 600.0), 1.0)
		var cam: FollowCam = res["cam"]
		assert_gte(cam.get_zoom(), cam.get_min_zoom() - 0.0001)
		assert_lte(cam.get_zoom(), cam.get_rest_zoom() + 0.0001)
		assert_lte(cam.get_min_zoom(), cam.get_rest_zoom() + 0.0001)
	# On a very wide screen the rest zoom is above the world-width zoom, so there is room to zoom out.
	var wide := FollowCam.new(Vector2(2400, 900))
	var path: PackedVector2Array = _lob(90.0, 1000, 700.0, 500.0, 600.0)
	var low_zoom: float = wide.get_zoom()
	var playhead: float = 0.0
	while playhead < float(path.size() - 1):
		playhead += 1.0
		wide.update(FRAME, PackedVector2Array([FollowCam.head_at(path, playhead)]), FollowCam.lookahead(path, playhead, 30.0))
		low_zoom = minf(low_zoom, wide.get_zoom())
	assert_gte(low_zoom, wide.get_min_zoom() - 0.0001)


func test_camera_motion_is_smooth() -> void:
	# Critically damped: no overshoot past the target and bounded acceleration frame to frame.
	var cam := FollowCam.new(Vector2(1600, 900))
	var path: PackedVector2Array = _lob(90.0, 1000, 700.0, 500.0, 600.0)
	var playhead: float = 0.0
	var prev_y: float = cam.get_center().y
	var prev_v: float = 0.0
	var max_jerk: float = 0.0
	var top_seen: float = INF
	while playhead < float(path.size() - 1):
		playhead += 1.0
		cam.update(FRAME, PackedVector2Array([FollowCam.head_at(path, playhead)]), FollowCam.lookahead(path, playhead, 30.0))
		var y: float = cam.get_center().y
		var v: float = y - prev_y
		max_jerk = maxf(max_jerk, absf(v - prev_v))
		prev_y = y
		prev_v = v
		top_seen = minf(top_seen, y)
	assert_lt(max_jerk, 12.0, "per-frame velocity changes stay small (units/frame^2)")
	# The highest the shell gets (plus padding) bounds how far up the camera may ever go.
	var apex: float = INF
	for p: Vector2 in path:
		apex = minf(apex, p.y)
	var allowed_top: float = apex - FollowCam.PAD_TOP - 450.0 - 5.0
	assert_gt(top_seen, allowed_top, "never swings far past what the shell needs")


func test_camera_returns_to_rest_after_the_shot() -> void:
	var res: Dictionary = _fly(Vector2(1600, 900), _lob(90.0, 1000, 700.0, 500.0, 600.0), 1.0)
	var cam: FollowCam = res["cam"]
	var empty := PackedVector2Array()
	# Force a displaced state (the lob already came back down), then the shell ends.
	cam.update(FRAME, PackedVector2Array([Vector2(700, -300)]), PackedVector2Array([Vector2(700, -320)]))
	for i: int in range(20):
		cam.update(FRAME, PackedVector2Array([Vector2(700, -300)]), PackedVector2Array([Vector2(700, -320)]))
	assert_false(cam.is_at_rest(), "displaced while the shell is up")
	var displaced: Vector2 = cam.get_center()
	for i: int in range(int(FollowCam.RETURN_DELAY / FRAME) - 3):
		cam.update(FRAME, empty)
	assert_eq(cam.get_center(), displaced, "holds still for ~0.4 s after the last shell ends")
	for i: int in range(int(2.5 / FRAME)):
		cam.update(FRAME, empty)
	assert_true(cam.is_at_rest(), "back to the normal framing")
	assert_eq(cam.get_center(), cam.get_rest_center())
	assert_almost_eq(cam.get_zoom(), cam.get_rest_zoom(), 0.00001)


func test_disabled_camera_never_moves() -> void:
	var cam := FollowCam.new(Vector2(1600, 900))
	cam.enabled = false
	var path: PackedVector2Array = _lob(90.0, 1000, 700.0, 500.0, 600.0)
	var playhead: float = 0.0
	while playhead < float(path.size() - 1):
		playhead += 1.0
		cam.update(FRAME, PackedVector2Array([FollowCam.head_at(path, playhead)]), FollowCam.lookahead(path, playhead, 30.0))
		assert_true(cam.is_at_rest())
	# Turning it off mid-flight snaps back to rest.
	cam.enabled = true
	cam.update(FRAME, PackedVector2Array([Vector2(700, -400)]), PackedVector2Array([Vector2(700, -420)]))
	for i: int in range(30):
		cam.update(FRAME, PackedVector2Array([Vector2(700, -400)]), PackedVector2Array([Vector2(700, -420)]))
	assert_false(cam.is_at_rest())
	cam.enabled = false
	cam.update(FRAME, PackedVector2Array([Vector2(700, -400)]))
	assert_true(cam.is_at_rest())


func test_camera_settings_default_and_reduce_motion() -> void:
	assert_true(CameraSettings.follow_shots, "default ON")
	assert_true(CameraSettings.follow_active())
	ShowSettings.reduce_motion = true
	assert_false(CameraSettings.follow_active(), "reduce motion: marker only")
	ShowSettings.reset()
	CameraSettings.follow_shots = false
	assert_false(CameraSettings.follow_active())
	var cfg := ConfigFile.new()
	CameraSettings.save_to(cfg)
	CameraSettings.follow_shots = true
	CameraSettings.load_from(cfg)
	assert_false(CameraSettings.follow_shots, "round-trips through a ConfigFile")


func test_lookahead_helper_finds_the_apex() -> void:
	var path: PackedVector2Array = _lob(90.0, 1000, 700.0, 500.0, 600.0)
	var apex_i: int = 0
	for i: int in range(path.size()):
		if path[i].y < path[apex_i].y:
			apex_i = i
	var pts: PackedVector2Array = FollowCam.lookahead(path, float(apex_i - 10), 20.0)
	assert_eq(pts.size(), 2)
	assert_almost_eq(pts[0].y, path[apex_i].y, 0.01, "the highest point in the window")
	assert_gt(pts[1].y, pts[0].y, "and the lowest")
	assert_eq(FollowCam.head_at(PackedVector2Array(), 3.0), Vector2.ZERO)


# --- in the battle -------------------------------------------------------------------------

func _live_battle() -> BattleController:
	get_window().size = Vector2i(1950, 900)  # a 19.5:9 phone (the headless window is square)
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, 4242, false, 2)
	add_child_autofree(c)
	assert_true(c.quick_start())
	await wait_process_frames(3)
	var guard: int = 0
	while c.is_busy() and guard < 900:  # the round_start / wind / turn banner playback
		c.call("_process", FRAME)
		guard += 1
	return c


## Fires straight up at full power and steps the controller by hand (60 fps) while the shell
## is in the air. Returns the lowest camera centre y reached and whether a chevron showed.
func _shoot_up(c: BattleController, frames: int) -> Dictionary:
	c.set_aim(900, 1000)
	c.select_weapon("spark_dart")
	assert_eq(c.fire_current(), "")
	var cam_top: float = INF
	var chevron: bool = false
	for i: int in range(frames):
		c.call("_process", FRAME)
		cam_top = minf(cam_top, c.get_node("Camera").position.y)
		chevron = chevron or c.get_markers().shell_count() > 0
	return {"cam_top": cam_top, "chevron": chevron}


func test_battle_camera_follows_a_high_shot_and_comes_back() -> void:
	var c: BattleController = await _live_battle()
	var rest: Vector2 = c.get_follow_cam().get_rest_center()
	var res: Dictionary = await _shoot_up(c, 200)
	assert_lt(res["cam_top"] as float, rest.y - 100.0, "the camera rose with the shell")
	assert_false(res["chevron"] as bool, "while following, the shell never leaves the picture")
	for i: int in range(600):
		c.call("_process", FRAME)
	assert_eq((c.get_node("Camera") as Camera2D).position, rest, "and returns to the normal framing")


func test_reduce_motion_uses_the_marker_only() -> void:
	ShowSettings.reduce_motion = true
	var c: BattleController = await _live_battle()
	var rest: Vector2 = c.get_follow_cam().get_rest_center()
	var res: Dictionary = await _shoot_up(c, 200)
	assert_eq(res["cam_top"], rest.y, "the camera never moved")
	assert_true(res["chevron"] as bool, "the off-screen marker shows instead")
