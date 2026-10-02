class_name ConfirmOverlay
extends OverlayPanel
## A two-button question ("Start a new match? Your saved game will be deleted").

signal confirmed
signal cancelled

var _message: Label = null


func _init() -> void:
	super._init()
	name = "ConfirmOverlay"
	add_title(tr("CONFIRM_TITLE"), NeonPalette.WARN, 22.0)
	_message = add_label("", 15.0, NeonPalette.TEXT)
	begin_row()
	var ok: Button = add_button(tr("CONFIRM_YES"), 180.0)
	ok.name = "Confirm"
	ok.pressed.connect(func() -> void:
		close()
		confirmed.emit())
	var no: Button = add_button(tr("CONFIRM_NO"), 140.0)
	no.name = "Cancel"
	no.pressed.connect(func() -> void:
		close()
		cancelled.emit())
	end_container()


func ask(message: String) -> void:
	_message.text = message
	open()
