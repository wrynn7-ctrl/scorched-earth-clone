class_name MatchNotice
extends OverlayPanel
## A full-screen message in the middle of an online match that stops play: "this match is disputed" (the players' copies
## of the game disagree), "the host ended the match", "please update the game". It dims the whole picture, explains in
## plain words and offers one to three buttons. `chosen(id)` says which one was pressed.

signal chosen(id: String)

var _title: Label = null
var _text: Label = null
var _row: HBoxContainer = null
var _ids: PackedStringArray = PackedStringArray()


func _init() -> void:
	super._init()
	name = "MatchNotice"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.95)  # a stop sign: hide the battle behind it
	_title = add_title("", NeonPalette.WARN, 24.0)
	_title.name = "Title"
	_text = add_label("", 15.0, NeonPalette.TEXT)
	_text.name = "Text"
	_row = begin_row()
	_row.name = "Buttons"
	end_container()


## Shows the notice. `buttons` = [{id, label}], the first is the main one.
func show_notice(title: String, text: String, buttons: Array, color: Color = NeonPalette.WARN) -> void:
	_title.text = title
	_title.add_theme_color_override("font_color", color)
	_text.text = text
	for b: Button in _buttons.duplicate():
		if b.get_parent() == _row:
			_buttons.erase(b)
			_btn_dp.erase(b)
			_row.remove_child(b)
			b.queue_free()
	_ids = PackedStringArray()
	_target = _row
	for spec: Variant in buttons:
		var d: Dictionary = spec as Dictionary
		var b: Button = add_button(d.get("label", "") as String, 170.0)
		b.name = "Button_" + (d.get("id", "") as String)
		var id: String = d.get("id", "")
		_ids.append(id)
		b.pressed.connect(func() -> void: chosen.emit(id))
	_target = _box
	open()
	if is_inside_tree():
		apply_scale()


func get_title_text() -> String:
	return _title.text


func get_text() -> String:
	return _text.text


func button_ids() -> PackedStringArray:
	return _ids


func get_notice_button(id: String) -> Button:
	return _row.get_node_or_null("Button_" + id) as Button
