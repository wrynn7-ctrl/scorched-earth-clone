class_name ShotHook
extends Node
## Saves a screenshot of the viewport after ShotArgs.shot_time seconds and quits.
## Only added when --shot=<png> was given (see attach()).

var _elapsed: float = 0.0
var _done: bool = false
var _host: Node = null
var _held: float = 0.0


func _init() -> void:
	# Keep ticking while the tree is paused (pause-menu screenshots).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Adds a hook to `host` if the command line asked for a screenshot.
static func attach(host: Node) -> void:
	ShotArgs.parse()
	if ShotArgs.shot_path != "":
		var h := ShotHook.new()
		h.name = "ShotHook"
		h._host = host
		host.add_child(h)


func _process(delta: float) -> void:
	_elapsed += delta
	if _done:
		return
	if ShotArgs.freeze_tick >= 0 and _host != null and _host.has_method("is_frozen"):
		# Weapon moments: the battle stops its playhead at the wanted tick; give the effects a
		# moment (real time) to reach their look, then capture. shot-time is the fallback.
		if _host.call("is_frozen"):
			_held += delta
			if _held >= ShotArgs.freeze_hold:
				_done = true
				_take()
			return
		if _elapsed < ShotArgs.shot_time + 30.0:
			return
	if _elapsed >= ShotArgs.shot_time:
		_done = true
		_take()


func _take() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(ShotArgs.shot_path)
	print("shot: saved ", ShotArgs.shot_path, " size=", img.get_size(), " err=", err)
	get_tree().quit()
