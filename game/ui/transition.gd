class_name Transition
extends CanvasLayer
## A short neon wipe (about 250 ms) between screens, plus tiny fades for overlays. One
## instance lives on the SceneTree root, above everything (layer 100), and is created on first
## use. `Transition.go(tree, scene_path)` covers the screen, swaps the scene while it is
## covered, then uncovers it. While covered the overlay swallows input (so a second tap
## cannot start another navigation); before and after, it is hidden and ignores the mouse.
##
## Reduce motion: a flat fade instead of the moving wipe (same length, no motion).
## Headless runs (the test suite) change scenes immediately unless a test opts in with
## `animate_in_headless`.

const SHADER: Shader = preload("res://ui/transition.gdshader")
const LAYER_INDEX: int = 100
## Whole cover + uncover time in seconds.
const DURATION: float = 0.25
const FADE_SECONDS: float = 0.14

## Test hook: run the animation even without a display.
static var animate_in_headless: bool = false

static var _instance: Transition = null

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _busy: bool = false
var _tween: Tween = null


## Changes to `scene_path` with the wipe (or at once when animations are off). Ignored while a
## transition is already running.
static func go(tree: SceneTree, scene_path: String) -> void:
	if not animates():
		tree.change_scene_to_file(scene_path)
		return
	var t: Transition = of(tree)
	if t._busy:
		return
	t._run(tree, scene_path)


## The shared instance (created under the tree root on first use).
static func of(tree: SceneTree) -> Transition:
	if _instance == null or not is_instance_valid(_instance):
		_instance = Transition.new()
		_instance.name = "Transition"
		tree.root.add_child(_instance)
	return _instance


static func animates() -> bool:
	return animate_in_headless or DisplayServer.get_name() != "headless"


## True while a wipe is running (input is blocked meanwhile).
static func is_busy() -> bool:
	return _instance != null and is_instance_valid(_instance) and _instance._busy


## Forgets the shared instance (tests).
static func reset() -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.queue_free()
	_instance = null


## A panel that just became visible fades in (no motion; skipped when animations are off).
static func fade_in(item: CanvasItem, seconds: float = FADE_SECONDS) -> void:
	if not item.is_inside_tree():
		return
	item.modulate.a = 1.0
	if not animates() or ShowSettings.reduce_motion:
		return
	if item.has_meta("_fade_tween"):
		var old: Variant = item.get_meta("_fade_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	item.modulate.a = 0.0
	var tw: Tween = item.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # overlays open while the tree is paused
	tw.tween_property(item, "modulate:a", 1.0, seconds)
	item.set_meta("_fade_tween", tw)


func _init() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.name = "Wipe"
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.visible = false
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_rect.material = _material
	add_child(_rect)


func _run(tree: SceneTree, scene_path: String) -> void:
	_busy = true
	var half: float = DURATION * 0.5
	_material.set_shader_parameter("plain", 1.0 if ShowSettings.reduce_motion else 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.visible = true
	await _animate(0.0, 1.0, half)
	tree.change_scene_to_file(scene_path)
	# Two frames: the new scene builds itself while it is still covered.
	await tree.process_frame
	await tree.process_frame
	await _animate(1.0, 2.0, half)
	_rect.visible = false
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func _animate(from: float, to: float, seconds: float) -> void:
	_material.set_shader_parameter("progress", from)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _material.set_shader_parameter("progress", v), from, to, seconds)
	await _tween.finished


func get_wipe_rect() -> ColorRect:
	return _rect
