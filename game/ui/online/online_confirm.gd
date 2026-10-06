class_name OnlineConfirm
extends OverlayPanel
## A two-button question for the online screens ("Remove ANNA from your friends?", "Leave this match?"). Unlike the
## ConfirmOverlay of the title it has its own title and button words, runs a Callable on YES and can be asked twice in
## a row ("Delete my online data" needs two confirmations). Tapping outside the panel is CANCEL.

signal answered(yes: bool)

var _title: Label = null
var _message: Label = null
var _yes: Button = null
var _no: Button = null
var _on_yes: Callable = Callable()


func _init() -> void:
	super._init()
	name = "OnlineConfirm"
	_title = add_title(tr("CONFIRM_TITLE"), NeonPalette.WARN, 22.0)
	_title.name = "Title"
	_message = add_label("", 15.0, NeonPalette.TEXT)
	_message.name = "Message"
	begin_row()
	_yes = add_button(tr("CONFIRM_OK"), 150.0)
	_yes.name = "Yes"
	_yes.pressed.connect(_answer.bind(true))
	_no = add_button(tr("CONFIRM_NO"), 130.0)
	_no.name = "No"
	_no.set_meta("ui_sound", "back")
	_no.pressed.connect(_answer.bind(false))
	end_container()


## Asks `text`. `yes_label` is the word on the confirming button (REMOVE, BLOCK, LEAVE...); `on_yes` runs after it.
func ask(text: String, on_yes: Callable, yes_label: String = "") -> void:
	_message.text = text
	_yes.text = yes_label if yes_label != "" else tr("CONFIRM_OK")
	_no.text = tr("CONFIRM_NO")
	_on_yes = on_yes
	open()
	if is_inside_tree():
		apply_scale()


func _answer(yes: bool) -> void:
	var run: Callable = _on_yes
	_on_yes = Callable()
	close()
	answered.emit(yes)
	if yes and run.is_valid():
		run.call()


func get_message_text() -> String:
	return _message.text


func get_yes_button() -> Button:
	return _yes


func get_no_button() -> Button:
	return _no


## A tap on the dimmed area outside the panel means "no".
func _gui_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point((event as InputEventMouseButton).global_position):
			_answer(false)
