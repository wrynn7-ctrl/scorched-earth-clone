class_name RoundEndOverlay
extends OverlayPanel
## Round summary: "PLAYER N WINS THE ROUND" (or "DRAW"), then per player the credits earned
## this round, total kills and round wins, and NEXT (on to the shop).

signal next_pressed

var _title: Label = null
var _sub: Label = null
var _table: StatTable = null


func _init() -> void:
	super._init()
	name = "RoundEndOverlay"
	_title = add_title("")
	_sub = add_label("", 14.0)
	_table = add_stat_table()
	add_button(tr("OVERLAY_NEXT"), 240.0).pressed.connect(func() -> void: next_pressed.emit())
	_buttons[0].name = "Next"


## winner: tank id or -1 for a draw. rows: [{id, earned, kills, wins}] in player order.
## round_number is 1-based.
func show_summary(winner: int, rows: Array[Dictionary], round_number: int, rounds: int) -> void:
	if winner >= 0:
		_title.text = tr("OVERLAY_ROUND_WINNER") % (winner + 1)
		_title.add_theme_color_override("font_color", PlayerLooks.color(winner))
	else:
		_title.text = tr("OVERLAY_DRAW")
		_title.add_theme_color_override("font_color", NeonPalette.TEXT)
	_sub.text = tr("OVERLAY_ROUND_OF") % [round_number, rounds]
	var table_rows: Array[Dictionary] = []
	for r: Dictionary in rows:
		var id: int = r["id"]
		table_rows.append({
			"id": id,
			"label": tr("HUD_PLAYER_N") % (id + 1),
			"cells": PackedStringArray([HudFormat.money_delta(r["earned"] as int), str(r["kills"]), str(r["wins"])]),
		})
	_table.set_data(PackedStringArray([tr("SUM_EARNED"), tr("SUM_KILLS"), tr("SUM_WINS")]), table_rows, winner)
	open()
	if is_inside_tree():
		apply_scale()
		_refit_next_frame()


func get_title_text() -> String:
	return _title.text


func get_table() -> StatTable:
	return _table


func get_next_button() -> Button:
	return _buttons[0]
