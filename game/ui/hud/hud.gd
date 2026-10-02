class_name BattleHud
extends Control
## The in-battle HUD: aim drag surface, angle readout + fine buttons, power slider,
## FIRE, wind indicator and turn banner. Takes/emits plain data only; a later task wires it
## to the simulation.
##
## Layout (containers, no pixel positions):
##   left column : wind (top) .... angle panel (bottom)
##   centre      : turn banner (top)
##   right       : FIRE (bottom) next to the full-height power panel
## All sizes derive from UiScale (dp), so they follow the physical screen size.

signal angle_changed(tenths: int)
signal power_changed(p: int)
signal fire_pressed

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


func _init() -> void:
	theme = THEME
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	apply_scale()
	get_viewport().size_changed.connect(apply_scale)


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
	_left.add_child(_ignoring_spacer())
	_angle_panel = AnglePanel.new()
	_angle_panel.name = "AnglePanel"
	_angle_panel.angle_changed.connect(_on_panel_angle)
	_left.add_child(_angle_panel)

	_center = _ignoring_vbox("Center")
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.add_child(_center)
	_banner = TurnBanner.new()
	_banner.name = "Banner"
	_banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_center.add_child(_banner)
	_center.add_child(_ignoring_spacer())

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
	var pad: float = UiScale.dp(10.0)
	var ins: Vector4 = UiScale.safe_insets()
	_margin.add_theme_constant_override("margin_left", roundi(pad + ins.x))
	_margin.add_theme_constant_override("margin_top", roundi(pad + ins.y))
	_margin.add_theme_constant_override("margin_right", roundi(pad + ins.z))
	_margin.add_theme_constant_override("margin_bottom", roundi(pad + ins.w))
	_row.add_theme_constant_override("separation", roundi(pad))
	_right.add_theme_constant_override("separation", roundi(pad))
	_aim.min_radius = UiScale.dp(10.0)
	for n: Node in [_wind, _angle_panel, _banner, _fire, _power]:
		n.call("apply_scale")


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
	_aim.set_color(NeonPalette.tank_color(player_index))


func set_fire_enabled(enabled: bool) -> void:
	_fire.set_enabled(enabled)


## Active tank position in viewport (canvas) coordinates; the aim drag is measured from it.
func set_aim_pivot(p: Vector2) -> void:
	_aim.set_pivot(p)


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
