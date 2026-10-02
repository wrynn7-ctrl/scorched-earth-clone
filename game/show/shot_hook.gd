class_name ShotHook
extends Node
## Saves a screenshot of the viewport after ShotArgs.shot_time seconds and quits.
## Only added when --shot=<png> was given (see attach()).

var _elapsed: float = 0.0
var _done: bool = false
var _host: Node = null
var _held: float = 0.0
var _resized: bool = false
var _seq_i: int = 0


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
	while _seq_i < ShotArgs.resize_seq.size() and _elapsed >= float(ShotArgs.resize_seq[_seq_i]["at"]):
		get_window().size = ShotArgs.resize_seq[_seq_i]["size"] as Vector2i
		_seq_i += 1
	if ShotArgs.resize_to != Vector2i.ZERO and not _resized and _elapsed >= ShotArgs.resize_after:
		_resized = true
		_resize_window()
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


## Debug: changes the window size mid-run (what Android does when it finishes rotating),
## optionally capturing the "before" frame first. The normal screenshot timer keeps running.
func _resize_window() -> void:
	if ShotArgs.shot_before_path != "":
		await RenderingServer.frame_post_draw
		var before: Image = get_viewport().get_texture().get_image()
		before.save_png(ShotArgs.shot_before_path)
		print("shot: saved ", ShotArgs.shot_before_path, " size=", before.get_size())
	get_window().size = ShotArgs.resize_to  # Window.size also sets the native window


func _take() -> void:
	if _host != null and _host.has_method("get_hud"):
		var hud: BattleHud = _host.call("get_hud") as BattleHud
		for l: String in hud.diagnostics_lines():
			if l.begins_with("HUD root:") or l.begins_with("Safe:") or l.begins_with("layout") or l.begins_with("last"):
				print("shot: hud ", l)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: int = img.save_png(ShotArgs.shot_path)
	print("shot: saved ", ShotArgs.shot_path, " size=", img.get_size(), " err=", err)
	get_tree().quit()
