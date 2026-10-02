extends GutTest
## Every show scene instantiates, plus behaviour of tank view, effects, shake and framing.

const SCENES: Array[String] = [
	"res://show/sky.tscn",
	"res://show/tank_view.tscn",
	"res://show/fx/explosion.tscn",
	"res://show/demo_battlefield.tscn",
]


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()


func test_all_show_scenes_instantiate() -> void:
	for path: String in SCENES:
		var packed: PackedScene = load(path)
		assert_not_null(packed, path)
		var node: Node = packed.instantiate()
		assert_not_null(node, path)
		add_child_autofree(node)
		await wait_frames(2)
		assert_true(node.is_inside_tree(), path)


func test_tank_view_api() -> void:
	var t: TankView = add_child_autofree(load("res://show/tank_view.tscn").instantiate())
	await wait_frames(1)
	t.set_angle_tenths(900)
	assert_almost_eq(t.get_node("Turret").rotation, -PI / 2.0, 0.0001)
	t.set_angle_tenths(0)
	assert_almost_eq(t.get_node("Turret").rotation, 0.0, 0.0001)
	t.set_angle_tenths(1800)
	assert_almost_eq(absf(t.get_node("Turret").rotation), PI, 0.0001)
	t.set_color_index(3)
	assert_eq(t.get_color_index(), 3)
	t.set_health(250, 100)
	assert_eq(t.get_health(), 100, "health clamped to max")
	t.set_dead(true)
	assert_true(t.is_dead())
	assert_false((t.get_node("Turret") as Node2D).visible)
	t.set_dead(false)
	assert_true((t.get_node("Turret") as Node2D).visible)


func test_tank_muzzle_points_up_at_900() -> void:
	var t: TankView = add_child_autofree(load("res://show/tank_view.tscn").instantiate())
	await wait_frames(1)
	t.position = Vector2(100, 500)
	t.set_angle_tenths(900)
	var m: Vector2 = t.muzzle_position()
	assert_almost_eq(m.x, 100.0, 0.01)
	assert_lt(m.y, 500.0 - TankView.TANK_H)


func test_shell_trail_plays_and_finishes() -> void:
	var tr_node: ShellTrail = add_child_autofree(ShellTrail.new())
	await wait_frames(1)
	var path := PackedVector2Array()
	for i: int in range(60):
		path.append(Vector2(i * 4.0, 100.0 - i))
	watch_signals(tr_node)
	tr_node.play(path, 0.001)
	tr_node.set_progress(30.5)
	assert_almost_eq(tr_node.head_position().x, 122.0, 0.01)
	tr_node.play(path, 6000.0)
	assert_true(tr_node.is_playing())
	await wait_frames(6)
	assert_signal_emitted(tr_node, "finished")
	assert_false(tr_node.is_playing())


func test_explosion_plays_and_finishes() -> void:
	var e: Explosion = add_child_autofree(load("res://show/fx/explosion.tscn").instantiate())
	await wait_frames(1)
	watch_signals(e)
	e.play(Vector2(10, 20), 28.0)
	assert_eq(e.position, Vector2(10, 20))
	assert_true((e.get_node("Flash") as Sprite2D).visible)
	assert_not_null(e.get_node("Sparks") as CPUParticles2D)
	await wait_seconds(1.1)
	assert_signal_emitted(e, "finished")


func test_camera_shake_respects_reduce_motion() -> void:
	var cam: CameraShake = add_child_autofree(CameraShake.new())
	await wait_frames(1)
	ShowSettings.reduce_motion = true
	cam.shake(1.0)
	assert_false(cam.is_shaking(), "no shake when reduce_motion is on")
	ShowSettings.reduce_motion = false
	cam.shake(0.5)
	assert_true(cam.is_shaking())
	await wait_seconds(1.0)
	assert_false(cam.is_shaking(), "shake decays")
	assert_eq(cam.offset, Vector2.ZERO)


func test_battle_framing_fits_width_and_anchors_bottom() -> void:
	var f: Dictionary = BattleFraming.frame(Vector2(1600, 900))
	assert_almost_eq(float(f["zoom"]), 1.0, 0.001)
	assert_eq(f["center"], Vector2(800, 450))
	var tall: Dictionary = BattleFraming.frame(Vector2(1600, 1200))
	assert_almost_eq(float(tall["zoom"]), 1.0, 0.001)
	assert_almost_eq((tall["center"] as Vector2).y + 600.0, 900.0, 0.01, "bottom edge anchored")
	var wide: Dictionary = BattleFraming.frame(Vector2(2400, 900))
	assert_gte(900.0 / float(wide["zoom"]), BattleFraming.MIN_VISIBLE_H - 0.01)
