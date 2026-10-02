class_name HudChip
extends Button
## A touch chip showing a catalog entry: glyph, name and a second line (count, price...).
## The content is built from child controls that ignore the mouse, so the whole chip is one
## tap target. Used by the weapon picker, the item tray and the shop cards.

var _row: HBoxContainer = null
var _icon: ItemIcon = null
var _col: VBoxContainer = null
var _name: Label = null
var _sub: Label = null
var _width_dp: float = 150.0
var _name_dp: float = 12.0
var _sub_dp: float = 11.0
var _item_id: String = ""


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	_icon = ItemIcon.new()
	_icon.name = "Icon"
	_row.add_child(_icon)
	_col = VBoxContainer.new()
	_col.name = "Col"
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.alignment = BoxContainer.ALIGNMENT_CENTER
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_col)
	_name = _make_label("Name", NeonPalette.TEXT)
	_sub = _make_label("Sub", NeonPalette.TEXT_DIM)


func _ready() -> void:
	apply_scale()


func _make_label(label_name: String, color: Color) -> Label:
	var l := Label.new()
	l.name = label_name
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_color_override("font_color", color)
	_col.add_child(l)
	return l


## width_dp: minimum chip width. Fonts in dp. Call before/after set_entry; safe any time.
func configure(width_dp: float, name_dp: float = 12.0, sub_dp: float = 11.0) -> void:
	_width_dp = width_dp
	_name_dp = name_dp
	_sub_dp = sub_dp
	if is_inside_tree():
		apply_scale()


func apply_scale() -> void:
	var lines: float = (UiScale.hud_line_h(_name_dp) if _name.visible else 0.0) + UiScale.hud_line_h(_sub_dp)
	var h: float = maxf(UiScale.touch(), lines + UiScale.dp(8.0))
	custom_minimum_size = Vector2(UiScale.dp(_width_dp), h)
	_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, roundi(UiScale.dp(5.0)))
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_icon.custom_minimum_size = Vector2.ONE * minf(h - UiScale.dp(8.0), UiScale.dp(40.0))
	_name.add_theme_font_size_override("font_size", UiScale.hud_font(_name_dp))
	_sub.add_theme_font_size_override("font_size", UiScale.hud_font(_sub_dp))
	_col.add_theme_constant_override("separation", 0)


## `name_text`/`sub_text` are already translated by the caller. `dim` mutes the glyph.
func set_entry(item_id: String, name_text: String, sub_text: String, dim: bool = false) -> void:
	_item_id = item_id
	_icon.set_item(item_id)
	_icon.set_dim(dim)
	_name.text = name_text
	_name.visible = name_text != ""
	_sub.text = sub_text
	_sub.visible = sub_text != ""


func get_item() -> String:
	return _item_id


func get_name_text() -> String:
	return _name.text


func get_sub_text() -> String:
	return _sub.text


## Hides the icon (for chips that only need two lines of text).
func set_icon_visible(v: bool) -> void:
	_icon.visible = v


func get_icon() -> ItemIcon:
	return _icon


static func count_text(count: int) -> String:
	return TranslationServer.translate("HUD_UNLIMITED") if count < 0 else (TranslationServer.translate("HUD_COUNT_FMT") % count)
