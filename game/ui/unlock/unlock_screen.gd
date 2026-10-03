class_name UnlockScreen
extends OverlayPanel
## "UNLOCK THE FULL GAME": a modal overlay that can be put on any screen (title, setup, shop,
## settings). It lists what the full game adds, shows one big BUY button with the store's price,
## RESTORE PURCHASE and CLOSE, and walks through the states of Entitlement's flow:
## loading -> ready -> (waiting) -> success / pending / cancelled / error.
##
## No dark patterns: no countdowns, no "limited time", no fake discounts, and it never opens by
## itself; only a tap on something locked (or the title chip / settings button) shows it.
##
## Layout: a scrolling area (title, a one-line reason like "Hard CPUs need the full game", weapon
## glyphs, the feature list), then the pinned status line, BUY and a RESTORE | CLOSE row. Only the
## scrolling area scrolls, so BUY / RESTORE / CLOSE are always on screen, even at 150% text on a
## short phone.

signal closed
## Emitted when the full game became owned while this screen was open.
signal unlocked

## The weapons whose glyphs sit above the feature list.
const SHOWCASE_ITEMS: PackedStringArray = [
	"singularity_seed", "riptide_anchor", "supernova", "photon_lance", "prism_cascade",
]
## [string key, accent colour] per feature row, in display order.
const FEATURES: Array = [
	["UNLOCK_F_TANKS", NeonPalette.CYAN],
	["UNLOCK_F_CPU", NeonPalette.MAGENTA],
	["UNLOCK_F_WEAPONS", NeonPalette.WARN],
	["UNLOCK_F_THEMES", NeonPalette.VIOLET],
	["UNLOCK_F_SKINS", NeonPalette.GOOD],
	["UNLOCK_F_ROUNDS", NeonPalette.SUNSET],
	["UNLOCK_F_RULES", NeonPalette.CYAN],
	["UNLOCK_F_ONLINE", NeonPalette.TEXT_DIM],
]
## What opened the screen -> the one-line reason shown under the title.
const CONTEXT_KEYS: Dictionary = {
	"players": "UNLOCK_CTX_PLAYERS",
	"human": "UNLOCK_CTX_HUMANS",
	"rounds": "UNLOCK_CTX_ROUNDS",
	"money": "UNLOCK_CTX_MONEY",
	"wind": "UNLOCK_CTX_WIND",
	"theme": "UNLOCK_CTX_THEME",
	"cpu": "UNLOCK_CTX_CPU",
	"item": "UNLOCK_CTX_ITEM",
	"skin": "UNLOCK_CTX_SKIN",
	"save": "UNLOCK_CTX_SAVE",
}
## How long "Contacting the store…" may show before we stop promising a price (seconds).
static var loading_timeout_sec: float = 5.0
## Frames the fit may take to settle.
const FIT_FRAMES: int = 6

var _title: Label = null
var _context: Label = null
var _scroll: TouchScroll = null
var _content: VBoxContainer = null
var _showcase: HBoxContainer = null
var _icons: Array[ItemIcon] = []
var _sub: Label = null
var _grid: GridContainer = null
var _feature_labels: Array[Label] = []
var _bullets: Array[Control] = []
var _status: Label = null
var _buy: Button = null
var _restore: Button = null
var _close: Button = null
var _burst: Burst = null
var _kind: String = ""
var _loading: bool = false
var _celebrated: bool = false
var _was_full: bool = false
var _hub: Entitlement.Hub = null
var _fit_generation: int = 0
## True while a match is running behind this screen: a purchase then applies from the next match.
var _in_match: bool = false


func _init() -> void:
	super._init()
	name = "UnlockScreen"
	_dim.color = Color(NeonPalette.BG_DEEP, 0.9)  # a purchase screen should be calm: hide what is behind
	# Title, reason and the showcase all live in the scrolling area: on a short phone with big text
	# only the status line and the buttons are pinned, so they can never be pushed off screen.
	_build_scroll()
	_target = _content
	_title = add_title(tr("UNLOCK_TITLE"), NeonPalette.CYAN, 24.0)
	_title.name = "Title"
	_context = add_label("", 14.0, NeonPalette.WARN)
	_context.name = "Context"
	_context.visible = false
	_build_showcase()
	_target = _box
	_status = add_label("", 14.0, NeonPalette.TEXT)
	_status.name = "Status"
	_status.visible = false
	_buy = add_button(tr("UNLOCK_BUY"), 280.0)
	_buy.name = "Buy"
	_buy.theme_type_variation = &"FireButton"
	_btn_dp[_buy] = [280.0, 22.0]
	_buy.set_meta("ui_sound", "none")  # the purchase sound plays on success, not on the tap
	_buy.pressed.connect(buy)
	begin_row()
	_restore = add_button(tr("UNLOCK_RESTORE"), 190.0)
	_restore.name = "Restore"
	_restore.pressed.connect(restore)
	_close = add_button(tr("UNLOCK_CLOSE"), 130.0)
	_close.name = "Close"
	_close.set_meta("ui_sound", "back")
	_close.pressed.connect(close)
	end_container()
	_burst = Burst.new()
	add_child(_burst)


func _build_scroll() -> void:
	_scroll = TouchScroll.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)


## Weapon glyphs, a one-line promise, the feature list.
func _build_showcase() -> void:
	_showcase = HBoxContainer.new()
	_showcase.name = "Showcase"
	_showcase.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(_showcase)
	for id: String in SHOWCASE_ITEMS:
		var icon := ItemIcon.new()
		icon.set_item(id)
		_showcase.add_child(icon)
		_icons.append(icon)
	_sub = Label.new()
	_sub.name = "Sub"
	_sub.text = tr("UNLOCK_SUB")
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_color_override("font_color", NeonPalette.TEXT)
	_font_dp[_sub] = 15.0
	_labels.append(_sub)
	_content.add_child(_sub)
	_grid = GridContainer.new()
	_grid.name = "Features"
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_grid)
	for spec: Array in FEATURES:
		var row := HBoxContainer.new()
		row.name = "Feature"
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(row)
		var bullet := Control.new()
		bullet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var accent: Color = spec[1]
		bullet.draw.connect(_draw_bullet.bind(bullet, accent))
		row.add_child(bullet)
		_bullets.append(bullet)
		var l := Label.new()
		l.text = tr(spec[0] as String)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", NeonPalette.TEXT)
		_font_dp[l] = 13.0
		_labels.append(l)
		row.add_child(l)
		_feature_labels.append(l)


## A glowing diamond: the shape is the bullet, the colour only decoration.
func _draw_bullet(bullet: Control, accent: Color) -> void:
	var c: Vector2 = bullet.size * 0.5
	var r: float = minf(bullet.size.x, bullet.size.y) * 0.34
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
	bullet.draw_colored_polygon(pts, Color(accent, 0.28))
	bullet.draw_polyline(pts, Color(accent, 0.3), r * 0.5, true)
	bullet.draw_polyline(pts, accent, maxf(1.2, r * 0.2), true)


# ======================================================================================
# Open / close
# ======================================================================================

## Opens the screen. `kind` is what the player tapped ("rounds", "cpu", "item", ... or "" for the
## title chip / settings): it picks the one-line reason. `start_restore` also asks the store for
## the earlier purchase right away (Settings > Restore purchase).
func open_for(kind: String, start_restore: bool = false) -> void:
	_kind = kind
	_celebrated = false
	_was_full = Entitlement.is_full()
	_context.text = tr(CONTEXT_KEYS[kind] as String) if CONTEXT_KEYS.has(kind) else ""
	_connect_hub()
	Entitlement.start()  # also refreshes price and ownership
	Entitlement.clear_status()
	_loading = Entitlement.price_text() == "" and not _was_full
	_start_loading_timer()
	_refresh_state()
	open()
	if start_restore and not _was_full:
		restore()


func open() -> void:
	super.open()
	apply_scale()


func close() -> void:
	if not visible:
		return
	_disconnect_hub()
	_burst.stop()
	super.close()
	closed.emit()


## The host says a match is running (shop, pause menu), so the screen can tell the player that the
## new features start with the next match.
func set_in_match(on: bool) -> void:
	_in_match = on


func get_kind() -> String:
	return _kind


## True while the screen shows the owned / success layout.
func shows_owned() -> bool:
	return _was_full or Entitlement.is_full()


func buy() -> void:
	if Entitlement.is_full() or _buy.disabled:
		return
	_loading = false
	Entitlement.purchase_full()


func restore() -> void:
	if Entitlement.is_full() or _restore.disabled:
		return
	_loading = false
	Entitlement.restore()


# ======================================================================================
# Entitlement signals
# ======================================================================================

func _connect_hub() -> void:
	var hub: Entitlement.Hub = Entitlement.hub()
	if hub == _hub:
		return
	_disconnect_hub()
	_hub = hub
	_hub.changed.connect(_on_changed)
	_hub.status_changed.connect(_on_status)
	_hub.price_changed.connect(_on_price)


func _disconnect_hub() -> void:
	if _hub == null:
		return
	_hub.changed.disconnect(_on_changed)
	_hub.status_changed.disconnect(_on_status)
	_hub.price_changed.disconnect(_on_price)
	_hub = null


func _exit_tree() -> void:
	_disconnect_hub()


func _on_changed() -> void:
	if Entitlement.is_full() and not _was_full:
		_was_full = true
		unlocked.emit()
	_refresh_state()


func _on_status(status: int) -> void:
	if status == Entitlement.Status.SUCCESS and visible and not _celebrated:
		_celebrate()
	_refresh_state()


func _on_price(_text: String) -> void:
	_loading = false
	_refresh_state()


func _start_loading_timer() -> void:
	if not _loading or not is_inside_tree() or loading_timeout_sec <= 0.0:
		return
	get_tree().create_timer(loading_timeout_sec).timeout.connect(end_loading)


## Stops showing "Contacting the store…" (the price did not arrive; BUY will report the real reason).
func end_loading() -> void:
	if _loading:
		_loading = false
		_refresh_state()


## The celebration: sound, a short haptic pulse and a neon starburst (still with reduce motion).
func _celebrate() -> void:
	_celebrated = true
	AudioDirector.play_ui("purchase")
	if ShowSettings.haptics:
		Input.vibrate_handheld(70)
	if is_inside_tree():
		_burst.start(_panel.get_global_rect().get_center() - global_position)


# ======================================================================================
# State -> widgets
# ======================================================================================

func _refresh_state() -> void:
	var full: bool = Entitlement.is_full()
	var st: int = Entitlement.status()
	var busy: bool = st == Entitlement.Status.PURCHASING or st == Entitlement.Status.RESTORING
	var pending: bool = st == Entitlement.Status.PENDING
	_title.text = tr("UNLOCK_TITLE_DONE") if full else tr("UNLOCK_TITLE")
	_title.add_theme_color_override("font_color", NeonPalette.GOOD if full else NeonPalette.CYAN)
	_context.visible = not full and _context.text != ""
	_buy.visible = not full
	_restore.visible = not full
	_buy.disabled = busy or pending
	_restore.disabled = busy
	var price: String = Entitlement.price_text()
	if pending:
		_buy.text = tr("UNLOCK_BUY_PENDING")
	else:
		_buy.text = tr("UNLOCK_BUY_FMT") % price if price != "" else tr("UNLOCK_BUY")
	_close.text = tr("UNLOCK_CONTINUE") if (full and _kind == "save") else tr("UNLOCK_CLOSE")
	var text: String = ""
	var color: Color = NeonPalette.TEXT
	if full:
		text = tr("UNLOCK_THANKS") if _celebrated else tr("UNLOCK_ALREADY")
		if _in_match:
			text = tr("UNLOCK_NEXT_MATCH")
		color = NeonPalette.GOOD
	elif busy:
		text = tr("UNLOCK_WAITING")
		color = NeonPalette.CYAN
	elif pending:
		text = Entitlement.status_message()
		color = NeonPalette.CYAN
	elif st == Entitlement.Status.ERROR:
		text = Entitlement.status_message()
		color = NeonPalette.WARN
	elif st == Entitlement.Status.CANCELLED:
		text = Entitlement.status_message()
		color = NeonPalette.TEXT_DIM
	elif _loading:
		text = tr("UNLOCK_LOADING")
		color = NeonPalette.TEXT_DIM
	_status.text = text
	_status.add_theme_color_override("font_color", color)
	_status.visible = text != ""
	if is_inside_tree():
		_fit_scrolls()
		_refit_next_frame()


# ======================================================================================
# Scale / fit
# ======================================================================================

func apply_scale() -> void:
	super.apply_scale()
	if _scroll == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	var wide: float = minf(UiScale.dp(580.0), vp.x * 0.94)
	_panel.custom_minimum_size.x = wide
	# Two feature columns when each gets a readable width, one long column when it does not.
	var pad: float = UiScale.dp(32.0 + TouchScroll.BAR_DP + TouchScroll.GAP_DP)
	var inner: float = maxf(UiScale.dp(120.0), wide - pad)
	var col_min: float = UiScale.dp(200.0) * maxf(1.0, UiScale.text_scale)
	_grid.columns = 2 if inner / 2.0 >= col_min else 1
	var col_w: float = inner / float(_grid.columns)
	var bullet_w: float = UiScale.dp(20.0)
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(12.0)))
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(4.0)))
	for i: int in range(_feature_labels.size()):
		_bullets[i].custom_minimum_size = Vector2(bullet_w, UiScale.dp(24.0))
		_bullets[i].queue_redraw()
		_feature_labels[i].custom_minimum_size.x = maxf(UiScale.dp(60.0), col_w - bullet_w - UiScale.dp(14.0))
	_sub.custom_minimum_size.x = inner
	_content.add_theme_constant_override("separation", roundi(UiScale.dp(8.0)))
	_showcase.add_theme_constant_override("separation", roundi(UiScale.dp(10.0)))
	for icon: ItemIcon in _icons:
		icon.custom_minimum_size = Vector2.ONE * UiScale.dp(34.0)
	_buy.custom_minimum_size.y = UiScale.dp(56.0)
	_status.custom_minimum_size.x = inner
	_fit_scrolls()


## Sizes the showcase to its content, but never so tall that the panel leaves the screen: the
## showcase scrolls, the buttons never move off screen. It adds up the other rows itself (instead of
## asking the panel, whose cached size lags a frame behind).
func _fit_scrolls() -> void:
	if _scroll == null:
		return
	var content: float = _content.get_combined_minimum_size().y
	var sep: float = float(_box.get_theme_constant("separation"))
	var other: float = 0.0
	for c: Node in _box.get_children():
		if c is Control and c != _scroll and (c as Control).visible:
			other += (c as Control).get_combined_minimum_size().y + sep
	var frame: float = _panel.get_theme_stylebox("panel").get_minimum_size().y + 2.0 * float(_margin.get_theme_constant("margin_top")) + sep
	var avail: float = get_viewport_rect().size.y * 0.97 - frame - other
	_scroll.custom_minimum_size.y = clampf(avail, minf(UiScale.dp(72.0), content), content)


## Wrapped labels only report their real height after a frame or two: measure again then, until
## nothing moves any more.
func _refit_next_frame() -> void:
	if not is_inside_tree():
		return
	_fit_generation += 1
	var mine: int = _fit_generation
	var last: float = -1.0
	for i: int in range(FIT_FRAMES):
		await get_tree().process_frame
		if mine != _fit_generation or not visible or not is_inside_tree():
			return
		_fit_scrolls()
		if is_equal_approx(last, _scroll.custom_minimum_size.y):
			return
		last = _scroll.custom_minimum_size.y


func _gui_input(event: InputEvent) -> void:
	# The dim area swallows taps (a purchase screen should not close by accident).
	if visible and event is InputEventMouseButton:
		accept_event()


# --- accessors (tests, tools) ---

func get_title_text() -> String:
	return _title.text


func get_context_text() -> String:
	return _context.text if _context.visible else ""


func get_status_text() -> String:
	return _status.text if _status.visible else ""


func get_buy_button() -> Button:
	return _buy


func get_restore_button() -> Button:
	return _restore


func get_close_button() -> Button:
	return _close


func get_scroll() -> TouchScroll:
	return _scroll


func get_panel() -> PanelContainer:
	return _panel


func get_feature_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for l: Label in _feature_labels:
		out.append(l.text)
	return out


func get_burst() -> Control:
	return _burst


func is_celebrating() -> bool:
	return _burst.active


## A short neon starburst over the panel. Drawn in one pass; animated for ~1.4 s, or a single
## still frame (no motion) when "reduce motion" is on.
class Burst extends Control:
	const RAYS: int = 28
	const SECONDS: float = 1.4
	const COLORS: Array[Color] = [NeonPalette.CYAN, NeonPalette.MAGENTA, NeonPalette.WARN, NeonPalette.GOOD, NeonPalette.VIOLET]

	var active: bool = false
	var _t: float = 0.0
	var _center: Vector2 = Vector2.ZERO

	func _init() -> void:
		name = "Burst"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		visible = false
		set_process(false)

	func start(center: Vector2) -> void:
		if ShowSettings.reduce_motion:
			return  # the title and message change anyway; no moving sparks
		_center = center
		_t = 0.0
		active = true
		visible = true
		set_process(true)

	func stop() -> void:
		active = false
		visible = false
		set_process(false)

	func _process(delta: float) -> void:
		_t += delta / SECONDS
		if _t >= 1.0:
			stop()
			return
		queue_redraw()

	func _draw() -> void:
		if not active:
			return
		var ease_out: float = 1.0 - pow(1.0 - _t, 3.0)
		var fade: float = 1.0 - _t
		var reach: float = UiScale.dp(260.0) * ease_out
		var inner: float = reach * 0.55
		for i: int in range(RAYS):
			var a: float = TAU * float(i) / float(RAYS) + 0.2
			var dir := Vector2(cos(a), sin(a))
			var col: Color = COLORS[i % COLORS.size()]
			var len_scale: float = 0.75 + 0.25 * float(i % 3) / 2.0
			draw_line(_center + dir * inner, _center + dir * reach * len_scale, Color(col, fade), UiScale.dp(3.0), true)
		draw_arc(_center, reach * 0.5, 0.0, TAU, 48, Color(NeonPalette.HOT, fade * 0.6), UiScale.dp(2.0), true)
