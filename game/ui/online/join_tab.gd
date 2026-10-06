class_name JoinTab
extends OnlineTab
## Join (ARCHITECTURE section 48): a field for the 6-character match code (capitals, ambiguous characters 0/O/1/I
## filtered out as the player types), JOIN, and "+ another player on this phone" for a shared-phone seat: each extra
## player gets a name field and takes one more seat (`joinMatch` seatCount and names).

## At most this many seats from one phone (the backend allows 4).
const MAX_SEATS: int = 4

var _scroll: TouchScroll = null
var _box: VBoxContainer = null
var _field: CodeField = null
var _join: Button = null
var _hint: Label = null
var _message: Label = null
var _add_seat: Button = null
var _seat_box: VBoxContainer = null
var _seat_fields: Array[NameField] = []
var _busy: bool = false


func _init() -> void:
	super._init()
	name = "JoinTab"
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.name = "Form"
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)
	var caption: Label = OnlineKit.label(tr("NET_JOIN_CAPTION"), 14.0, NeonPalette.CYAN, true)
	caption.name = "Caption"
	_box.add_child(caption)
	var row := HBoxContainer.new()
	row.name = "CodeRow"
	_box.add_child(row)
	_field = CodeField.new(DeepLinks.MATCH_CODE_LENGTH)
	_field.placeholder_text = tr("NET_JOIN_PLACEHOLDER")
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.code_changed.connect(func(_c: String) -> void: _refresh())
	_field.submitted_code.connect(func(_c: String) -> void: join())
	row.add_child(_field)
	_join = OnlineKit.button(tr("NET_JOIN"), 120.0, 16.0)
	_join.name = "Join"
	_join.theme_type_variation = &"FireButton"
	_join.pressed.connect(join)
	row.add_child(_join)
	_hint = OnlineKit.label(tr("NET_JOIN_HINT"), 12.0, NeonPalette.TEXT_DIM, true, true)
	_hint.name = "Hint"
	_box.add_child(_hint)
	_seat_box = VBoxContainer.new()
	_seat_box.name = "ExtraSeats"
	_box.add_child(_seat_box)
	_add_seat = OnlineKit.button(tr("NET_ADD_PHONE_SEAT"), 240.0, 13.0)
	_add_seat.name = "AddSeat"
	_add_seat.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_seat.pressed.connect(add_phone_seat)
	_box.add_child(_add_seat)
	_message = OnlineKit.label("", 14.0, NeonPalette.WARN, true)
	_message.name = "Message"
	_box.add_child(_message)
	_refresh()


func activate() -> void:
	super.activate()
	_refresh()


func apply_scale() -> void:
	super.apply_scale()
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_seat_box.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_field.apply_scale()
	for nf: NameField in _seat_fields:
		nf.apply_scale()


## Fills the code (a deep link): the player only has to press JOIN.
func set_code(code: String) -> void:
	_field.set_code(code)
	_message.text = ""
	_refresh()


func code() -> String:
	return _field.code()


func seat_count() -> int:
	return 1 + _seat_fields.size()


func _refresh() -> void:
	_join.disabled = _busy or _field.code().length() != DeepLinks.MATCH_CODE_LENGTH
	_add_seat.visible = seat_count() < MAX_SEATS
	_add_seat.disabled = _busy


## "+ another player on this phone": one more seat, with its own name field.
func add_phone_seat() -> void:
	if seat_count() >= MAX_SEATS:
		return
	var row := HBoxContainer.new()
	row.name = "ExtraSeat%d" % (seat_count() + 1)
	_seat_box.add_child(row)
	var nf := NameField.new()
	nf.name = "SeatName"
	nf.placeholder_text = tr("HUD_PLAYER_N") % (seat_count() + 1)
	nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nf)
	_seat_fields.append(nf)
	var rm: Button = OnlineKit.button(tr("NET_REMOVE_SEAT"), 56.0, 16.0)
	rm.name = "RemoveSeat"
	rm.accessibility_name = tr("NET_REMOVE_SEAT_TIP")
	rm.pressed.connect(func() -> void:
		_seat_fields.erase(nf)
		_seat_box.remove_child(row)
		row.queue_free()
		_refresh())
	row.add_child(rm)
	_refresh()
	apply_scale()


## The names to send: the first seat keeps the account's name (""), the others the typed ones.
func seat_names() -> Array:
	var names: Array = [""]
	for nf: NameField in _seat_fields:
		names.append(PlayerNames.sanitize(nf.text))
	return names


func join() -> void:
	if _busy or _field.code().length() != DeepLinks.MATCH_CODE_LENGTH:
		return
	_busy = true
	_message.text = ""
	_refresh()
	var count: int = seat_count()
	var r: NetResult = await net.lobby.join(_field.code(), count, seat_names() if count > 1 else [])
	_busy = false
	_refresh()
	if r.ok:
		var id: String = r.dict().get("matchId", "")
		_field.set_code("")
		open_lobby.emit(id)
		return
	if check_update(r):
		return
	_message.text = OnlineText.error(r)


# --- test accessors ---------------------------------------------------------------------------------------------

func get_field() -> CodeField:
	return _field


func get_join_button() -> Button:
	return _join


func get_add_seat_button() -> Button:
	return _add_seat


func get_seat_fields() -> Array[NameField]:
	return _seat_fields


func get_message() -> String:
	return _message.text


func get_scroll() -> TouchScroll:
	return _scroll
