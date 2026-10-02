class_name BattleHud
extends Control
## The in-battle HUD: aim drag surface, angle readout + fine buttons, power slider,
## FIRE, wind indicator, turn banner, money, weapon picker, item tray and move controls.
## Takes/emits plain data only; the battle controller wires it to the simulation.
##
## Layout (containers, no pixel positions):
##   left column : wind + money (top) .... move buttons + fuel, angle panel (bottom)
##   centre      : turn banner (top) .... tray (bottom): [items row] / [weapon | items toggle]
##   right       : FIRE (bottom) next to the full-height power panel
## All sizes derive from UiScale (dp), so they follow the physical screen size.

signal angle_changed(tenths: int)
signal power_changed(p: int)
signal fire_pressed
signal pause_pressed
signal speed_pressed
## The player picked a weapon in the picker.
signal weapon_selected(item_id: String)
## The weapon button was tapped: the controller answers with open_weapon_picker().
signal weapon_picker_requested
signal item_pressed(item_id: String)
signal move_pressed(dir: int)

const THEME: Theme = preload("res://ui/theme/neon_theme.tres")

var _aim: AimInput = null
var _margin: MarginContainer = null
var _row: HBoxContainer = null
var _left: VBoxContainer = null
var _center: VBoxContainer = null
var _right: HBoxContainer = null
var _fire_col: VBoxContainer = null
var _wind: WindIndicator = null
var _angle_panel: AnglePanel = null
var _banner: TurnBanner = null
var _fire: FireButton = null
var _power: PowerPanel = null
var _top_row: HBoxContainer = null
var _speed_btn: Button = null
var _pause_btn: Button = null
var _money: MoneyLabel = null
var _tray: VBoxContainer = null
var _tray_row: HBoxContainer = null
var _moves: MoveControls = null
var _weapon_chip: HudChip = null
var _items_toggle: Button = null
var _items: ItemTray = null
var _popup: WeaponPopup = null
var _items_open: bool = false
var _item_total: int = 0
var _fade: HudFade = null
## Opacity factor of the angle and power panels while the controls are locked (1 = unlocked).
var _lock_alpha: float = 1.0


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	apply_scale()
	LayoutWatch.attach(self, apply_scale)


func _build() -> void:
	_aim = AimInput.new()
	_aim.name = "AimInput"
	_aim.angle_changed.connect(_on_aim_angle)
	add_child(_aim)

	_margin = MarginContainer.new()
	_margin.name = "Safe"
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_row)

	_left = _ignoring_vbox("Left")
	_row.add_child(_left)
	_wind = WindIndicator.new()
	_wind.name = "Wind"
	_left.add_child(_wind)
	_money = MoneyLabel.new()
	_left.add_child(_money)
	_left.add_child(_ignoring_spacer())
	_moves = MoveControls.new()
	_moves.move_pressed.connect(func(dir: int) -> void: move_pressed.emit(dir))
	_left.add_child(_moves)
	_angle_panel = AnglePanel.new()
	_angle_panel.name = "AnglePanel"
	_angle_panel.angle_changed.connect(_on_panel_angle)
	_left.add_child(_angle_panel)

	_center = _ignoring_vbox("Center")
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_center)
	# Top row: banner, then the speed and pause buttons just to its right (top-centre-right).
	_top_row = HBoxContainer.new()
	_top_row.name = "TopRow"
	_top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_child(_top_row)
	_banner = TurnBanner.new()
	_banner.name = "Banner"
	_top_row.add_child(_banner)
	_speed_btn = Button.new()
	_speed_btn.name = "Speed"
	_speed_btn.focus_mode = Control.FOCUS_NONE
	_speed_btn.text = tr("HUD_SPEED_FMT") % 1
	_speed_btn.pressed.connect(func() -> void: speed_pressed.emit())
	_top_row.add_child(_speed_btn)
	_pause_btn = Button.new()
	_pause_btn.name = "Pause"
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.text = tr("HUD_PAUSE_ICON")
	_pause_btn.pressed.connect(func() -> void: pause_pressed.emit())
	_top_row.add_child(_pause_btn)
	_center.add_child(_ignoring_spacer())
	_build_tray()

	_right = HBoxContainer.new()
	_right.name = "Right"
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_right)
	_fire_col = _ignoring_vbox("FireColumn")
	_right.add_child(_fire_col)
	_fire_col.add_child(_ignoring_spacer())
	_fire = FireButton.new()
	_fire.name = "Fire"
	_fire.fire_pressed.connect(func() -> void: fire_pressed.emit())
	_fire_col.add_child(_fire)
	_power = PowerPanel.new()
	_power.name = "PowerPanel"
	_power.power_changed.connect(func(p: int) -> void: power_changed.emit(p))
	_right.add_child(_power)

	_popup = WeaponPopup.new()
	_popup.chosen.connect(func(id: String) -> void: weapon_selected.emit(id))
	add_child(_popup)

	_fade = HudFade.new()
	_fade.name = "Fade"
	_fade.alpha_changed.connect(_apply_alpha)
	add_child(_fade)
	for p: Control in [_wind, _money, _moves, _angle_panel, _power, _fire]:
		_fade.add_panel(p)


func _build_tray() -> void:
	_tray = _ignoring_vbox("Tray")
	_tray.alignment = BoxContainer.ALIGNMENT_END
	_center.add_child(_tray)
	_items = ItemTray.new()
	_items.item_pressed.connect(func(id: String) -> void: item_pressed.emit(id))
	_items.visible = false
	_tray.add_child(_items)
	_tray_row = HBoxContainer.new()
	_tray_row.name = "TrayRow"
	_tray_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_child(_tray_row)
	_weapon_chip = HudChip.new()
	_weapon_chip.name = "WeaponButton"
	_weapon_chip.configure(150.0, 12.0, 12.0)
	_weapon_chip.pressed.connect(func() -> void: weapon_picker_requested.emit())
	_tray_row.add_child(_weapon_chip)
	_items_toggle = Button.new()
	_items_toggle.name = "ItemsToggle"
	_items_toggle.focus_mode = Control.FOCUS_NONE
	_items_toggle.pressed.connect(toggle_items)
	_tray_row.add_child(_items_toggle)
	_refresh_items_toggle()


static func _ignoring_vbox(node_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func _ignoring_spacer() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


## Re-applies dp-based sizes. Called on ready and whenever the viewport size changes.
func apply_scale() -> void:
	UiScale.apply_edge_margins(_margin)
	# The edge margin is 12 dp; gaps between the columns are a little tighter so the crowded
	# ~700 dp phones at the largest text size still fit.
	var gap: float = UiScale.dp(8.0)
	_row.add_theme_constant_override("separation", roundi(gap))
	_right.add_theme_constant_override("separation", roundi(gap))
	_aim.min_radius = UiScale.dp(10.0)
	_top_row.add_theme_constant_override("separation", roundi(UiScale.dp(4.0)))
	var bsz := Vector2.ONE * UiScale.touch()
	_speed_btn.custom_minimum_size = bsz
	_pause_btn.custom_minimum_size = bsz
	_speed_btn.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_pause_btn.add_theme_font_size_override("font_size", UiScale.hud_font(15.0))
	_tray.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	_tray_row.add_theme_constant_override("separation", roundi(UiScale.dp(6.0)))
	for n: Node in [_wind, _angle_panel, _banner, _fire, _power, _money, _moves, _weapon_chip, _items, _popup]:
		n.call("apply_scale")
	_items_toggle.custom_minimum_size = Vector2(UiScale.dp(70.0), maxf(UiScale.touch(), _weapon_chip.custom_minimum_size.y))
	_items_toggle.add_theme_font_size_override("font_size", UiScale.hud_font(12.0))


# --- Public API (plain data) ---

func set_angle_tenths(a: int) -> void:
	_aim.set_angle_tenths(a)
	_angle_panel.set_angle_tenths(a)


func get_angle_tenths() -> int:
	return _angle_panel.get_angle_tenths()


func set_power(p: int) -> void:
	_power.set_power(p)


func get_power() -> int:
	return _power.get_power()


## wind in [-100, 100], positive blows right.
func set_wind(w: int) -> void:
	_wind.set_wind(w)


func show_turn(player_index: int, player_name: String = "") -> void:
	_banner.show_turn(player_index, player_name)
	_aim.set_color(PlayerLooks.color(player_index))


func set_fire_enabled(enabled: bool) -> void:
	_fire.set_enabled(enabled)


## Active tank position in viewport (canvas) coordinates; the aim drag is measured from it.
func set_aim_pivot(p: Vector2) -> void:
	_aim.set_pivot(p)


## Shows the playback speed on the speed toggle ("1x" / "2x").
func set_speed(speed: float) -> void:
	_speed_btn.text = tr("HUD_SPEED_FMT") % roundi(speed)


func get_speed_button() -> Button:
	return _speed_btn


func get_pause_button() -> Button:
	return _pause_btn


## Locks aiming during timeline playback: dims the panels and stops the drag surface.
func set_controls_locked(locked: bool) -> void:
	_aim.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	_lock_alpha = 0.45 if locked else 1.0
	_apply_alpha(_angle_panel)
	_apply_alpha(_power)
	_angle_panel.process_mode = Node.PROCESS_MODE_DISABLED if locked else Node.PROCESS_MODE_INHERIT
	_power.process_mode = Node.PROCESS_MODE_DISABLED if locked else Node.PROCESS_MODE_INHERIT
	_weapon_chip.disabled = locked
	_items_toggle.disabled = locked
	for b: HudChip in _items.get_buttons():
		b.disabled = locked
	if locked:
		_aim.cancel_drag()
		_popup.close()


## Fade (the action is behind a panel) times the lock dimming. Buttons use self_modulate:
## the FIRE button pulses through its own modulate.
func _apply_alpha(panel: Control) -> void:
	var a: float = _fade.get_alpha(panel)
	if panel == _angle_panel or panel == _power:
		a *= _lock_alpha
	if panel is Button:
		panel.self_modulate = Color(1, 1, 1, a)
	else:
		panel.modulate = Color(1, 1, 1, a)


## Screen rectangles (viewport coordinates) of whatever is happening behind the HUD. The
## panels over them fade to ~30% (see HudFade).
func set_occluders(rects: Array[Rect2], segments: PackedVector2Array = PackedVector2Array()) -> void:
	_fade.set_occluders(rects, segments)


func get_fade() -> HudFade:
	return _fade


## True if the viewport rectangle `r` lies under one of the fading panels.
func is_under_panel(r: Rect2) -> bool:
	return _fade.is_under_panel(r)


## A press on a faded panel shows it in full at once. Watching in _input (not _gui_input)
## because the buttons inside a panel consume the event first; this never consumes it.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		_fade.touch_at((event as InputEventMouse).position if event is InputEventMouse \
				else (event as InputEventScreenTouch).position)


func is_controls_locked() -> bool:
	return _aim.mouse_filter == Control.MOUSE_FILTER_IGNORE


# --- Weapon, items, move, money ---

func set_money(n: int) -> void:
	_money.set_amount(n)


## The weapon shown on the weapon button; count < 0 means unlimited.
func set_weapon(item_id: String, count: int) -> void:
	_weapon_chip.set_entry(item_id, tr("ITEM_" + item_id.to_upper()), HudChip.count_text(count))


func get_weapon_button() -> HudChip:
	return _weapon_chip


## entries: [{id, count}] of owned weapons (spark_dart with count -1 first).
func open_weapon_picker(entries: Array[Dictionary], selected: String) -> void:
	_popup.open(entries, selected)


func close_weapon_picker() -> void:
	_popup.close()


func get_weapon_popup() -> WeaponPopup:
	return _popup


## Usable items the player owns: [{id, count}]. The ITEMS toggle hides when there are none.
func set_items(entries: Array[Dictionary]) -> void:
	_items.set_items(entries)
	_item_total = _items.item_count()
	if _item_total == 0:
		_items_open = false
	_items.visible = _items_open and _item_total > 0
	_items_toggle.visible = _item_total > 0
	_refresh_items_toggle()


func toggle_items() -> void:
	_items_open = not _items_open
	_items.visible = _items_open and _item_total > 0
	_refresh_items_toggle()


func is_items_open() -> bool:
	return _items_open


func get_item_tray() -> ItemTray:
	return _items


func get_items_toggle() -> Button:
	return _items_toggle


func _refresh_items_toggle() -> void:
	_items_toggle.text = tr("HUD_ITEMS_OPEN") if _items_open else tr("HUD_ITEMS")


## Fuel readout and move buttons; hidden when fuel_total is 0.
func set_fuel(fuel_total: int) -> void:
	_moves.set_fuel(fuel_total)


func get_move_controls() -> MoveControls:
	return _moves


func get_money_label() -> MoneyLabel:
	return _money


func get_tray() -> Control:
	return _tray


func get_fire_button() -> FireButton:
	return _fire


func get_aim_input() -> AimInput:
	return _aim


func get_power_panel() -> PowerPanel:
	return _power


func get_angle_panel() -> AnglePanel:
	return _angle_panel


func get_wind_indicator() -> WindIndicator:
	return _wind


func get_turn_banner() -> TurnBanner:
	return _banner


func _on_aim_angle(a: int) -> void:
	_angle_panel.set_angle_tenths(a)
	angle_changed.emit(a)


func _on_panel_angle(a: int) -> void:
	_aim.set_angle_tenths(a)
	angle_changed.emit(a)
