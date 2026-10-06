class_name CodeField
extends LineEdit
## A text field for friend codes (8) and match codes (6). While the player types, anything that is not in the
## unambiguous code alphabet is dropped and letters become capitals (so the zero/O and one/I confusion cannot
## happen), and the length is capped. `code_changed(code)` fires after each change, `submitted_code(code)` on Done.

signal code_changed(code: String)
signal submitted_code(code: String)

var max_chars: int = DeepLinks.MATCH_CODE_LENGTH
var _fitting: bool = false


func _init(length: int = DeepLinks.MATCH_CODE_LENGTH) -> void:
	name = "CodeField"
	max_chars = length
	max_length = length
	select_all_on_focus = false
	context_menu_enabled = false
	virtual_keyboard_enabled = DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD)
	virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_mode = Control.FOCUS_CLICK
	caret_blink = true
	OnlineKit.style_line_edit(self)
	text_changed.connect(_on_text_changed)
	text_submitted.connect(_on_submitted)


## The text as typed so far (always already filtered).
func code() -> String:
	return text


## Puts a code in the field (filtered the same way).
func set_code(raw: String) -> void:
	var clean: String = OnlineText.filter_code(raw, max_chars)
	text = clean
	caret_column = clean.length()
	code_changed.emit(clean)


func apply_scale() -> void:
	custom_minimum_size.y = UiScale.touch()
	add_theme_font_size_override("font_size", UiScale.font(20.0))


func _on_text_changed(new_text: String) -> void:
	var clean: String = OnlineText.filter_code(new_text, max_chars)
	if clean != new_text:
		var caret: int = caret_column
		text = clean
		caret_column = mini(caret, clean.length())
	code_changed.emit(clean)


func _on_submitted(_value: String) -> void:
	if has_focus():
		release_focus()
	submitted_code.emit(text)
