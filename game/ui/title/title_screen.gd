class_name TitleScreen
extends Control
## Title screen: glowing logo over the neon sky, ROUNDS selector (1/3/5) and START.
## START hands the chosen round count to BattleConfig and loads the battle scene
## (2 players, pass-and-play on one device).

const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
const LOGO_SHADER: Shader = preload("res://ui/title/logo_gradient.gdshader")

var _sky: NeonSky = null
var _box: VBoxContainer = null
var _logo_holder: Control = null
var _glow_a: Label = null
var _glow_b: Label = null
var _logo: Label = null
var _subtitle: Label = null
var _rounds_caption: Label = null
var _rounds_row: HBoxContainer = null
var _round_buttons: Array[Button] = []
var _start: Button = null
var _selected_rounds: int = 3
var _pulse: Tween = null


func _init() -> void:
	ShotArgs.parse()
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(true)
	apply_scale()
	get_viewport().size_changed.connect(apply_scale)
	select_rounds(BattleConfig.rounds)
	_start_pulse()
	ShotHook.attach(self)


func _build() -> void:
	_sky = (load("res://show/sky.tscn") as PackedScene).instantiate()
	add_child(_sky)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = VBoxContainer.new()
	_box.name = "Box"
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_box)

	_logo_holder = Control.new()
	_logo_holder.name = "LogoHolder"
	_logo_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_logo_holder)
	_glow_a = _logo_label("GlowWide", Color(NeonPalette.MAGENTA, 0.22))
	_glow_b = _logo_label("GlowTight", Color(NeonPalette.CYAN, 0.38))
	_logo = _logo_label("Logo", Color(0, 0, 0, 0))
	var mat := ShaderMaterial.new()
	mat.shader = LOGO_SHADER
	_logo.material = mat
	_logo.add_theme_color_override("font_color", Color.WHITE)
	_logo.add_theme_constant_override("outline_size", 0)

	_subtitle = Label.new()
	_subtitle.name = "Subtitle"
	_subtitle.text = tr("TITLE_SUBTITLE")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", NeonPalette.TEXT_DIM)
	_box.add_child(_subtitle)

	_rounds_caption = Label.new()
	_rounds_caption.name = "RoundsCaption"
	_rounds_caption.text = tr("TITLE_ROUNDS")
	_rounds_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rounds_caption.add_theme_color_override("font_color", NeonPalette.CYAN)
	_box.add_child(_rounds_caption)
	_rounds_row = HBoxContainer.new()
	_rounds_row.name = "RoundsRow"
	_rounds_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_rounds_row)
	var group := ButtonGroup.new()
	for n: int in BattleConfig.ROUND_CHOICES:
		var b := Button.new()
		b.name = "Rounds%d" % n
		b.text = str(n)
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(select_rounds.bind(n))
		_rounds_row.add_child(b)
		_round_buttons.append(b)

	_start = Button.new()
	_start.name = "Start"
	_start.text = tr("TITLE_START")
	_start.theme_type_variation = &"FireButton"
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(start_game)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_box.add_child(_start)


func _logo_label(label_name: String, outline: Color) -> Label:
	var l := Label.new()
	l.name = label_name
	l.text = tr("TITLE_LOGO")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if outline.a > 0.0:
		l.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		l.add_theme_color_override("font_outline_color", outline)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_logo_holder.add_child(l)
	return l


func apply_scale() -> void:
	var fs: int = UiScale.font(46.0)
	var font: Font = _logo.get_theme_font("font")
	var text_size: Vector2 = font.get_string_size(_logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	_logo_holder.custom_minimum_size = text_size + Vector2(UiScale.dp(40.0), UiScale.dp(24.0))
	for l: Label in [_glow_a, _glow_b, _logo]:
		l.add_theme_font_size_override("font_size", fs)
	_glow_a.add_theme_constant_override("outline_size", roundi(UiScale.dp(16.0)))
	_glow_b.add_theme_constant_override("outline_size", roundi(UiScale.dp(6.0)))
	(_logo.material as ShaderMaterial).set_shader_parameter("height", text_size.y)
	_subtitle.add_theme_font_size_override("font_size", UiScale.font(15.0))
	_rounds_caption.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(14.0)))
	_rounds_row.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	for b: Button in _round_buttons:
		b.custom_minimum_size = Vector2.ONE * UiScale.touch() * 1.15
		b.add_theme_font_size_override("font_size", UiScale.font(20.0))
	_start.custom_minimum_size = Vector2(UiScale.dp(220.0), UiScale.dp(68.0))
	_start.add_theme_font_size_override("font_size", UiScale.font(26.0))


func _start_pulse() -> void:
	if ShowSettings.reduce_motion:
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_glow_a, "modulate:a", 0.55, 1.6).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_glow_a, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)


func select_rounds(n: int) -> void:
	_selected_rounds = n
	for b: Button in _round_buttons:
		b.set_pressed_no_signal(int(b.text) == n)


func get_selected_rounds() -> int:
	return _selected_rounds


func get_start_button() -> Button:
	return _start


func get_rounds_buttons() -> Array[Button]:
	return _round_buttons


func get_logo_text() -> String:
	return _logo.text


func start_game() -> void:
	BattleConfig.rounds = _selected_rounds
	BattleConfig.seed_value = ShotArgs.seed_value
	get_tree().change_scene_to_file(BATTLE_SCENE)
