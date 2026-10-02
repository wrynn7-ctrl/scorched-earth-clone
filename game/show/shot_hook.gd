class_name ShotHook
extends Node
## Saves a screenshot of the viewport after ShotArgs.shot_time seconds and quits.
## Only added when --shot=<png> was given (see attach()).

var _elapsed: float = 0.0
var _done: bool = false


func _init() -> void:
	# Keep ticking while the tree is paused (pause-menu screenshots).
	process_mode = Node.PROCESS_MODE_ALWAYS


## Adds a hook to `host` if the command line asked for a screenshot.
static func attach(host: Node) -> void:
	ShotArgs.parse()
	if ShotArgs.shot_path != "":
		var h := ShotHook.new()
		h.name = "ShotHook"
		host.add_child(h)


func _process(delta: float) -> void:
	_elapsed += delta
	if not _done and _elapsed >= ShotArgs.shot_time:
		_done = true
		_take()


func _take() -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(ShotArgs.shot_path)
	print("shot: saved ", ShotArgs.shot_path, " size=", img.get_size(), " err=", err)
	get_tree().quit()
