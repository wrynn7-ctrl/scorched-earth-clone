class_name MatchEndOverlay
extends OverlayPanel
## Final screen: match result, per-player round wins, NEW MATCH / TITLE.

signal new_match_pressed
signal title_pressed

var _title: Label = null
var _sub: Label = null


func _init() -> void:
	name = "MatchEndOverlay"
	_title = add_title("")
	_sub = add_label("", 14.0)
	set_tally(PackedInt32Array([0, 0]))
	add_button(tr("OVERLAY_NEW_MATCH")).pressed.connect(func() -> void: new_match_pressed.emit())
	add_button(tr("OVERLAY_TITLE")).pressed.connect(func() -> void: title_pressed.emit())
	_buttons[0].name = "NewMatch"
	_buttons[1].name = "Title"


## Winner = most round wins; equal top scores are a draw.
static func match_winner(wins: PackedInt32Array) -> int:
	var best: int = -1
	var best_wins: int = -1
	var tied: bool = false
	for i: int in range(wins.size()):
		if wins[i] > best_wins:
			best_wins = wins[i]
			best = i
			tied = false
		elif wins[i] == best_wins:
			tied = true
	return -1 if tied else best


func show_result(wins: PackedInt32Array) -> void:
	var w: int = match_winner(wins)
	if w >= 0:
		_title.text = tr("OVERLAY_MATCH_WINNER") % (w + 1)
		_title.add_theme_color_override("font_color", NeonPalette.tank_color(w))
	else:
		_title.text = tr("OVERLAY_DRAW")
		_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	_sub.text = tr("OVERLAY_FINAL_SCORE")
	set_tally(wins, w)
	open()


func get_title_text() -> String:
	return _title.text
