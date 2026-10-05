class_name RoundEndOverlay
extends OverlayPanel
## Round summary: "PLAYER N WINS THE ROUND" (or "DRAW"), then per player the credits earned
## this round, total kills and round wins, a "CPU purchases" line per computer player (what it
## just bought for the next round), and NEXT (on to the shop).

signal next_pressed

var _title: Label = null
var _sub: Label = null
var _table: StatTable = null
var _cpu_scroll: TouchScroll = null
var _cpu_box: VBoxContainer = null
var _cpu_labels: Array[Label] = []

## The CPU lines scroll beyond this height so eight CPUs never push NEXT off a phone screen.
const CPU_MAX_DP: float = 80.0
## A wider panel while CPU purchases are listed, so each line fits on one row.
const CPU_PANEL_DP: float = 600.0


func _init() -> void:
	super._init()
	name = "RoundEndOverlay"
	_title = add_title("")
	_sub = add_label("", 14.0)
	_table = add_stat_table()
	_cpu_scroll = TouchScroll.new()
	_cpu_scroll.name = "CpuScroll"
	_cpu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_cpu_scroll.visible = false
	_cpu_box = VBoxContainer.new()
	_cpu_box.name = "CpuLines"
	_cpu_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cpu_scroll.add_child(_cpu_box)
	_box.add_child(_cpu_scroll)
	add_button(tr("OVERLAY_NEXT"), 240.0).pressed.connect(func() -> void: next_pressed.emit())
	_buttons[0].name = "Next"


## winner: tank id or -1 for a draw. rows: [{id, earned, kills, wins}] in player order.
## round_number is 1-based.
## cpu_buys: [{tank, level, items: [{id, units}]}] from CpuShop.run (may be empty).
func show_summary(winner: int, rows: Array[Dictionary], round_number: int, rounds: int,
		cpu_buys: Array[Dictionary] = []) -> void:
	if winner >= 0:
		_title.text = tr("OVERLAY_ROUND_WINNER") % PlayerNames.label(winner)
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
			"label": PlayerNames.label(id),
			"cells": PackedStringArray([HudFormat.money_delta(r["earned"] as int), str(r["kills"]), str(r["wins"])]),
		})
	_table.set_data(PackedStringArray([tr("SUM_EARNED"), tr("SUM_KILLS"), tr("SUM_WINS")]), table_rows, winner)
	_set_cpu_lines(cpu_buys)
	open()
	if is_inside_tree():
		apply_scale()
		_refit_next_frame()


func _set_cpu_lines(cpu_buys: Array[Dictionary]) -> void:
	for l: Label in _cpu_labels:
		_labels.erase(l)
		_font_dp.erase(l)
		_cpu_box.remove_child(l)
		l.free()
	_cpu_labels.clear()
	for entry: Dictionary in cpu_buys:
		var id: int = entry["tank"]
		var l := Label.new()
		l.name = "Cpu%d" % id
		l.text = tr("SUM_CPU_BUYS_FMT") % [PlayerNames.label(id), CpuNames.level_word(entry["level"] as int),
				CpuShop.describe(entry["items"] as Array[Dictionary])]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", PlayerLooks.color(id))
		_font_dp[l] = 12.0
		_labels.append(l)
		_cpu_box.add_child(l)
		_cpu_labels.append(l)
	_cpu_scroll.visible = not _cpu_labels.is_empty()
	_cpu_scroll.custom_minimum_size.y = 0.0
	if is_inside_tree():
		apply_scale()


func apply_scale() -> void:
	super.apply_scale()
	if _cpu_scroll != null and _cpu_scroll.visible:
		var wide: float = minf(UiScale.dp(CPU_PANEL_DP), get_viewport_rect().size.x * 0.92)
		_panel.custom_minimum_size.x = maxf(_panel.custom_minimum_size.x, wide)


## The CPU lines get their own short scroll area, then the table takes what is left.
func _fit_scrolls() -> void:
	if _cpu_scroll != null and _cpu_scroll.visible:
		_cpu_scroll.custom_minimum_size.y = clampf(_cpu_box.get_combined_minimum_size().y, 0.0, UiScale.dp(CPU_MAX_DP))
	super._fit_scrolls()


func get_cpu_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for l: Label in _cpu_labels:
		out.append(l.text)
	return out


func get_cpu_scroll() -> TouchScroll:
	return _cpu_scroll


func get_title_text() -> String:
	return _title.text


func get_table() -> StatTable:
	return _table


func get_next_button() -> Button:
	return _buttons[0]
