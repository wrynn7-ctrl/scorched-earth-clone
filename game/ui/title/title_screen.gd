class_name TitleScreen
extends Control
## Title screen: glowing logo over the neon sky, START (match setup), CONTINUE (when an
## autosave exists) and SETTINGS. START asks for confirmation first if it would replace a save.

const BATTLE_SCENE: String = "res://show/battle/battle_scene.tscn"
const SETUP_SCENE: String = "res://ui/setup/setup_screen.tscn"
const SKINS_SCENE: String = "res://ui/skins/skin_studio.tscn"
const LOVE_SETUP_SCENE: String = "res://ui/love/love_setup_screen.tscn"
const THEME: Theme = preload("res://ui/theme/neon_theme.tres")
## Grid scroll speed on the title (the battle's sky uses the shader default, 0.35).
const TITLE_GRID_SPEED: float = 0.16
const LOGO_SHADER: Shader = preload("res://ui/title/logo_gradient.gdshader")
## Secret (ARCHITECTURE section 37): this many taps on the logo within LOVE_WINDOW_MS reveal the Love Edition button.
const LOVE_TAPS: int = 7
const LOVE_WINDOW_MS: int = 3000
const LOVE_PINK: Color = Color(1.0, 0.42, 0.68)

var _sky: NeonSky = null
var _box: VBoxContainer = null
var _logo_holder: Control = null
var _glow_a: Label = null
var _glow_b: Label = null
var _logo: Label = null
var _subtitle: Label = null
var _start: Button = null
var _online: Button = null
var _primary_row: HBoxContainer = null
var _continue: Button = null
var _settings: Button = null
var _skins: Button = null
var _row: HBoxContainer = null
var _settings_overlay: SettingsOverlay = null
var _unlock_chip: Button = null
var _chip_row: HBoxContainer = null
var _love_button: Button = null
var _love_taps: Array[int] = []
var _love_burst: HeartBurst = null
var _love_fade: Tween = null
## Where the confirm dialog's YES goes (the setup screen of the standard or the love match).
var _pending_scene: String = SETUP_SCENE
var _unlock: UnlockScreen = null
var _confirm: ConfirmOverlay = null
var _pulse: Tween = null
var _pulse_b: Tween = null
var _drift_t: float = 0.0


func _init() -> void:
	ShotArgs.parse()
	SettingsStore.ensure_loaded()
	theme = THEME
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _ready() -> void:
	get_tree().set_quit_on_go_back(true)
	apply_scale()
	LayoutWatch.attach(self, apply_scale)
	refresh_continue()
	Entitlement.start()  # connects to the store (price, what is owned) in the background
	Entitlement.hub().changed.connect(_refresh_unlock_chip)
	_refresh_unlock_chip()
	_refresh_love_button()
	apply_scale()  # again: the pills row may have changed the stack's height
	_start_pulse()
	_start_drift()
	_connect_online_routes()
	ShotHook.attach(self)
	if ShotArgs.open_unlock:
		open_unlock("")
	if ShotArgs.open_settings or ShotArgs.open_diag:
		open_settings()
	if ShotArgs.open_diag:
		for i: int in range(SettingsOverlay.DIAG_TAPS):
			_settings_overlay.tap_version()


func _exit_tree() -> void:
	_disconnect_online_routes()


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
	# The logo is the one tappable thing that is not a button: seven quick taps are a secret (see tap_logo).
	# Only the logo's own rectangle takes input; nothing else on the title changes.
	_logo_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_logo_holder.gui_input.connect(_on_logo_input)
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
	_subtitle.text = tr("TITLE_SUBTITLE_M3")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", NeonPalette.TEXT)
	_subtitle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# The sun sits right behind the subtitle: a dark translucent plate keeps it readable.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(NeonPalette.BG_DEEP, 0.72)
	plate.set_corner_radius_all(10)
	plate.content_margin_left = 14.0
	plate.content_margin_right = 14.0
	plate.content_margin_top = 4.0
	plate.content_margin_bottom = 4.0
	plate.anti_aliasing = true
	_subtitle.add_theme_stylebox_override("normal", plate)
	_box.add_child(_subtitle)

	# START (a match on this device) and ONLINE (friends, ARCHITECTURE section 48) side by side.
	_primary_row = HBoxContainer.new()
	_primary_row.name = "PrimaryRow"
	_primary_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_primary_row)
	_start = Button.new()
	_start.name = "Start"
	_start.text = tr("TITLE_START")
	_start.theme_type_variation = &"FireButton"
	_start.focus_mode = Control.FOCUS_NONE
	_start.pressed.connect(start_game)
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_primary_row.add_child(_start)
	_online = Button.new()
	_online.name = "Online"
	_online.text = tr("TITLE_ONLINE")
	_online.focus_mode = Control.FOCUS_NONE
	_online.pressed.connect(open_online)
	_online.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_primary_row.add_child(_online)

	_row = HBoxContainer.new()
	_row.name = "SecondaryRow"
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_row)
	_continue = Button.new()
	_continue.name = "Continue"
	_continue.text = tr("TITLE_CONTINUE")
	_continue.focus_mode = Control.FOCUS_NONE
	_continue.pressed.connect(continue_game)
	_row.add_child(_continue)
	_settings = Button.new()
	_settings.name = "Settings"
	_settings.text = tr("TITLE_SETTINGS")
	_settings.focus_mode = Control.FOCUS_NONE
	_settings.pressed.connect(open_settings)
	_row.add_child(_settings)
	_skins = Button.new()
	_skins.name = "Skins"
	_skins.text = tr("TITLE_SKINS")
	_skins.focus_mode = Control.FOCUS_NONE
	_skins.pressed.connect(open_skins)
	_row.add_child(_skins)

	# One row of small pills under the buttons: "UNLOCK FULL GAME" (only while the full game is not owned)
	# and, once discovered, the Love Edition. The row takes no height when both are hidden.
	_chip_row = HBoxContainer.new()
	_chip_row.name = "ChipRow"
	_chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(_chip_row)
	_unlock_chip = Button.new()
	_unlock_chip.name = "UnlockChip"
	_unlock_chip.text = tr("TITLE_UNLOCK")
	_unlock_chip.focus_mode = Control.FOCUS_NONE
	_unlock_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unlock_chip.pressed.connect(open_unlock.bind(""))
	_chip_row.add_child(_unlock_chip)
	_love_button = Button.new()
	_love_button.name = "LoveButton"
	_love_button.text = tr("LOVE_BUTTON")
	_love_button.icon = HeartShape.icon_texture(LOVE_PINK)
	_love_button.expand_icon = true
	_love_button.focus_mode = Control.FOCUS_NONE
	_love_button.visible = false
	_love_button.pressed.connect(start_love)
	_chip_row.add_child(_love_button)

	_settings_overlay = SettingsOverlay.new()
	add_child(_settings_overlay)
	_unlock = UnlockScreen.new()
	_unlock.closed.connect(_on_unlock_closed)
	add_child(_unlock)
	_confirm = ConfirmOverlay.new()
	_confirm.confirmed.connect(_on_confirmed)
	add_child(_confirm)


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


## Candidate [separation dp, logo font dp] pairs, roomiest first: the title stack takes the first that fits the
## screen's height (a phone at 150% text with a third row of pills would not otherwise).
const STACK_STEPS: Array = [[14.0, 46.0], [8.0, 46.0], [6.0, 38.0], [4.0, 30.0], [3.0, 24.0]]


func apply_scale() -> void:
	_apply_buttons()
	for step: Array in STACK_STEPS:
		_apply_stack(step[0] as float, step[1] as float)
		if _box.get_combined_minimum_size().y <= get_viewport_rect().size.y - UiScale.dp(2.0 * UiScale.EDGE_MARGIN_DP):
			break


func _apply_stack(sep_dp: float, logo_dp: float) -> void:
	var fs: int = UiScale.font(logo_dp)
	var font: Font = _logo.get_theme_font("font")
	var text_size: Vector2 = font.get_string_size(_logo.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs)
	_logo_holder.custom_minimum_size = text_size + Vector2(UiScale.dp(40.0), UiScale.dp(24.0))
	for l: Label in [_glow_a, _glow_b, _logo]:
		l.add_theme_font_size_override("font_size", fs)
	_glow_a.add_theme_constant_override("outline_size", roundi(UiScale.dp(16.0)))
	_glow_b.add_theme_constant_override("outline_size", roundi(UiScale.dp(6.0)))
	(_logo.material as ShaderMaterial).set_shader_parameter("height", text_size.y)
	(_logo.material as ShaderMaterial).set_shader_parameter("width", text_size.x)
	_box.add_theme_constant_override("separation", roundi(UiScale.dp(sep_dp)))


func _apply_buttons() -> void:
	_subtitle.add_theme_font_size_override("font_size", UiScale.font(15.0))
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(12.0)))
	_primary_row.add_theme_constant_override("separation", roundi(UiScale.dp(12.0)))
	_start.custom_minimum_size = Vector2(UiScale.dp(220.0), UiScale.dp(68.0))
	_start.add_theme_font_size_override("font_size", UiScale.font(26.0))
	_online.custom_minimum_size = Vector2(UiScale.dp(190.0), UiScale.dp(68.0))
	_online.add_theme_font_size_override("font_size", UiScale.font(22.0))
	for b: Button in [_continue, _settings, _skins]:
		b.custom_minimum_size = Vector2(UiScale.dp(150.0), UiScale.touch())
		b.add_theme_font_size_override("font_size", UiScale.font(15.0))
	_chip_row.add_theme_constant_override("separation", roundi(UiScale.dp(12.0)))
	_love_button.custom_minimum_size = Vector2(UiScale.dp(190.0), UiScale.touch())
	_love_button.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_love_button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.92))
	_love_button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(20.0)))
	_love_button.add_theme_constant_override("h_separation", roundi(UiScale.dp(8.0)))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_love_button.add_theme_stylebox_override(state, _chip_style(state == "pressed" or state == "hover", LOVE_PINK))
	_unlock_chip.custom_minimum_size = Vector2(UiScale.dp(210.0), UiScale.touch())
	_unlock_chip.add_theme_font_size_override("font_size", UiScale.font(14.0))
	_unlock_chip.add_theme_color_override("font_color", NeonPalette.HOT)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_unlock_chip.add_theme_stylebox_override(state, _chip_style(state == "pressed" or state == "hover"))


## A gentle logo glow: the wide magenta halo and the tight cyan one breathe out of step, and a
## faint highlight sweeps over the letters. Two looping tweens and one shader uniform: cheap.
## With reduce motion everything stays still.
func _start_pulse() -> void:
	var still: bool = ShowSettings.reduce_motion
	(_logo.material as ShaderMaterial).set_shader_parameter("shimmer", 0.0 if still else 1.0)
	if still:
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_glow_a, "modulate:a", 0.55, 1.6).set_trans(Tween.TRANS_SINE)
	_pulse.tween_property(_glow_a, "modulate:a", 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	_glow_b.modulate.a = 0.6
	_pulse_b = create_tween().set_loops()
	_pulse_b.tween_property(_glow_b, "modulate:a", 1.0, 2.3).set_trans(Tween.TRANS_SINE)
	_pulse_b.tween_property(_glow_b, "modulate:a", 0.6, 2.3).set_trans(Tween.TRANS_SINE)


## The horizon grid scrolls slowly toward the viewer and sways a little sideways.
func _start_drift() -> void:
	var still: bool = ShowSettings.reduce_motion
	_sky.set_scroll_speed(0.0 if still else TITLE_GRID_SPEED)
	set_process(not still)


func _process(delta: float) -> void:
	_drift_t += delta
	_sky.set_parallax(Vector2(sin(_drift_t * 0.07) * 320.0, 0.0))


## Shows CONTINUE only when a valid autosave exists.
func refresh_continue() -> void:
	_continue.visible = SaveStore.has_valid_save(BattleConfig.autosave_path)


func has_save() -> bool:
	return _continue.visible


func get_start_button() -> Button:
	return _start


func get_continue_button() -> Button:
	return _continue


func get_settings_button() -> Button:
	return _settings


func get_settings_overlay() -> SettingsOverlay:
	return _settings_overlay


func get_confirm_overlay() -> ConfirmOverlay:
	return _confirm


func get_logo_text() -> String:
	return _logo.text


## A pill with a magenta neon outline (the one place on the title that is not a standard button).
func _chip_style(bright: bool, edge: Color = NeonPalette.MAGENTA) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NeonPalette.BG_DEEP, 0.78) if not bright else Color(edge, 0.28)
	sb.border_color = edge
	sb.set_border_width_all(maxi(2, roundi(UiScale.dp(1.5))))
	sb.set_corner_radius_all(roundi(UiScale.touch() * 0.5))
	sb.content_margin_left = UiScale.dp(16.0)
	sb.content_margin_right = UiScale.dp(16.0)
	sb.anti_aliasing = true
	return sb


func get_unlock_chip() -> Button:
	return _unlock_chip


func get_unlock_screen() -> UnlockScreen:
	return _unlock


## The chip shows only while the full game is not owned.
func _refresh_unlock_chip() -> void:
	_unlock_chip.visible = not Entitlement.is_full()
	_refresh_chip_row()


func _refresh_chip_row() -> void:
	_chip_row.visible = _unlock_chip.visible or _love_button.visible
	if is_node_ready():
		apply_scale()


# --- the secret ---------------------------------------------------------------------------

## The Love Edition button shows once the secret was found (stored in SettingsStore, so it stays).
func _refresh_love_button() -> void:
	_love_button.visible = SettingsStore.love_found or ShotArgs.love_found
	_refresh_chip_row()


func _on_logo_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tap_logo()


## One tap on the logo at `now_ms` (the real clock when omitted). LOVE_TAPS taps within LOVE_WINDOW_MS
## find the secret. Returns true when this tap revealed it. Taps after it was found do nothing, and
## there is no hint anywhere that the logo is tappable.
func tap_logo(now_ms: int = -1) -> bool:
	if SettingsStore.love_found:
		return false
	var now: int = now_ms if now_ms >= 0 else Time.get_ticks_msec()
	_love_taps.append(now)
	while not _love_taps.is_empty() and now - _love_taps[0] > LOVE_WINDOW_MS:
		_love_taps.pop_front()
	if _love_taps.size() < LOVE_TAPS:
		return false
	_love_taps.clear()
	_reveal_love()
	return true


## The discovery: stored for good, a small heart sparkle, a soft chime, and the button fades in.
func _reveal_love() -> void:
	SettingsStore.love_found = true
	SettingsStore.save()
	_love_button.visible = true
	_refresh_chip_row()
	if _love_fade != null:
		_love_fade.kill()
	if ShowSettings.reduce_motion:
		_love_button.modulate.a = 1.0
	else:
		_love_button.modulate.a = 0.0
		_love_fade = create_tween()
		_love_fade.tween_property(_love_button, "modulate:a", 1.0, 0.6)
	_sparkle_at_logo()
	AudioDirector.play_sfx("love_found")


func _sparkle_at_logo() -> void:
	if _love_burst == null:
		_love_burst = HeartBurst.new()
		_love_burst.name = "LoveBurst"
		add_child(_love_burst)
	_love_burst.scale = Vector2.ONE * clampf(UiScale.factor() * 0.7, 1.0, 3.0)
	_love_burst.play(_logo_holder.get_global_rect().get_center(), 60.0)


func get_love_button() -> Button:
	return _love_button


func get_logo_holder() -> Control:
	return _logo_holder


func logo_taps_pending() -> int:
	return _love_taps.size()


func is_love_revealed() -> bool:
	return _love_button.visible


func get_love_burst() -> HeartBurst:
	return _love_burst


## The Love Edition button: its own small setup, after the same "this replaces your save" question.
func start_love() -> void:
	_pending_scene = LOVE_SETUP_SCENE
	if has_save():
		_confirm.ask(tr("TITLE_DISCARD_SAVE"))
	else:
		_on_confirmed()


func open_unlock(kind: String) -> void:
	_unlock.open_for(kind)


## After a "this match needs the full game" unlock, CONTINUE goes straight into the match.
func _on_unlock_closed() -> void:
	if _unlock.get_kind() == "save" and Entitlement.is_full():
		continue_game()


func get_skins_button() -> Button:
	return _skins


func get_online_button() -> Button:
	return _online


## ONLINE: the Online home (sign-in, friends, matches). It asks nothing before it opens; a save is not touched.
func open_online() -> void:
	OnlineHub.go_online(get_tree())


## A craterline://join link or a notification tap that started the game, or arrives while the title shows, opens the
## Online home, which then follows it (OnlineHub keeps what was asked).
func _connect_online_routes() -> void:
	OnlineHub.start_services()
	if OnlineHub.links != null and not OnlineHub.links.join_requested.is_connected(_on_join_link):
		OnlineHub.links.join_requested.connect(_on_join_link)
	if OnlineHub.push != null and not OnlineHub.push.notification_opened.is_connected(_on_push_tap):
		OnlineHub.push.notification_opened.connect(_on_push_tap)
	OnlineHub.collect_pending()
	if OnlineHub.has_route():
		open_online.call_deferred()


func _disconnect_online_routes() -> void:
	if OnlineHub.links != null and OnlineHub.links.join_requested.is_connected(_on_join_link):
		OnlineHub.links.join_requested.disconnect(_on_join_link)
	if OnlineHub.push != null and OnlineHub.push.notification_opened.is_connected(_on_push_tap):
		OnlineHub.push.notification_opened.disconnect(_on_push_tap)


func _on_join_link(code: String) -> void:
	OnlineHub.pending_join_code = code
	open_online()


func _on_push_tap(payload: Dictionary) -> void:
	var id: String = PushService.match_id_of(payload)
	if id != "":
		OnlineHub.pending_match_id = id
		open_online()


## SKINS: the Skin Studio (private, on-device tank looks).
func open_skins() -> void:
	Transition.go(get_tree(), SKINS_SCENE)


func open_settings() -> void:
	_settings_overlay.open()


## START: straight to the setup screen, or ask first if that would discard a saved match.
func start_game() -> void:
	_pending_scene = SETUP_SCENE
	if has_save():
		_confirm.ask(tr("TITLE_DISCARD_SAVE"))
	else:
		_on_confirmed()


func _on_confirmed() -> void:
	Transition.go(get_tree(), _pending_scene)


## CONTINUE: the battle restores the autosave (mid-turn or mid-shop).
func continue_game() -> void:
	if MatchSession.needs_full(BattleConfig.autosave_path):
		# Made with the full game, not owned on this device now: explain and offer the unlock.
		# The save is kept, so unlocking (or a restore) brings the match back.
		open_unlock("save")
		return
	BattleConfig.resume = true
	BattleConfig.settings = null
	Transition.go(get_tree(), BATTLE_SCENE)
