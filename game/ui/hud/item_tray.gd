class_name ItemTray
extends HFlowContainer
## Buttons for the usable items the player owns (shields, repulsor, repair kit), each with its
## glyph and count (the name is the tooltip). The row wraps instead of growing wider than the
## screen. Pressing one emits `item_pressed(item_id)`; the controller runs `use_item`.

signal item_pressed(item_id: String)

var _buttons: Array[HudChip] = []


func _init() -> void:
	name = "ItemTray"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = FlowContainer.ALIGNMENT_CENTER


func _ready() -> void:
	apply_scale()


func apply_scale() -> void:
	add_theme_constant_override("h_separation", roundi(UiScale.dp(6.0)))
	add_theme_constant_override("v_separation", roundi(UiScale.dp(6.0)))
	for b: HudChip in _buttons:
		b.apply_scale()


## entries: [{id, count}] of items to show (only counts > 0 are shown).
func set_items(entries: Array[Dictionary]) -> void:
	for b: HudChip in _buttons:
		remove_child(b)
		b.queue_free()
	_buttons.clear()
	for e: Dictionary in entries:
		if (e["count"] as int) <= 0:
			continue
		var id: String = e["id"]
		var chip := HudChip.new()
		chip.name = "Use_" + id
		chip.configure(76.0, 11.0, 13.0)
		chip.set_entry(id, "", HudChip.count_text(e["count"] as int))
		chip.tooltip_text = tr("ITEM_" + id.to_upper())
		chip.pressed.connect(func() -> void: item_pressed.emit(id))
		add_child(chip)
		_buttons.append(chip)
	visible = not _buttons.is_empty()


func get_buttons() -> Array[HudChip]:
	return _buttons


func get_button(id: String) -> HudChip:
	for b: HudChip in _buttons:
		if b.get_item() == id:
			return b
	return null


func item_count() -> int:
	return _buttons.size()
