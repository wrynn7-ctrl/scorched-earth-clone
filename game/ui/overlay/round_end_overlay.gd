class_name RoundEndOverlay
extends OverlayPanel
## "PLAYER N WINS THE ROUND" (or "DRAW") with the running round-win tally and NEXT ROUND.

signal next_round_pressed

var _title: Label = null
var _sub: Label = null


func _init() -> void:
	name = "RoundEndOverlay"
	_title = add_title("")
	_sub = add_label("", 14.0)
	set_tally(PackedInt32Array([0, 0]))
	add_button(tr("OVERLAY_NEXT_ROUND")).pressed.connect(func() -> void: next_round_pressed.emit())
	_buttons[0].name = "NextRound"


## winner: tank id or -1 for a draw. round_number is 1-based.
func show_result(winner: int, wins: PackedInt32Array, round_number: int, rounds: int) -> void:
	if winner >= 0:
		_title.text = tr("OVERLAY_ROUND_WINNER") % (winner + 1)
		_title.add_theme_color_override("font_color", NeonPalette.tank_color(winner))
	else:
		_title.text = tr("OVERLAY_DRAW")
		_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	_sub.text = tr("OVERLAY_ROUND_OF") % [round_number, rounds]
	set_tally(wins, winner)
	open()


func get_title_text() -> String:
	return _title.text


func get_next_button() -> Button:
	return _buttons[0]
