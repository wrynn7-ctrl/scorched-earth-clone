class_name BattleController
extends Node2D
## Wires the deterministic simulation to the show layer for a pass-and-play match
## (2-8 players). The simulation is the single source of truth: this controller submits
## actions through a MatchSession, then *plays back* the returned Timeline
## (docs/ARCHITECTURE.md sections 10, 17-25) against its own display copy of the terrain and the
## TankViews, and finally verifies that the display matches the authoritative state.
##
## Flow: shop (hand-over screen, shop screen, READY, next player) -> round (aim, fire, move,
## items) -> round summary -> shop ... -> final standings. Every applied action is logged and
## autosaved (see MatchSession / SaveStore) so CONTINUE can restore the match mid-turn or
## mid-shop.
##
## Timing: events carry `tick` (ticks since the action started, 60/s). Playback advances a
## playhead by delta * 60 * speed and dispatches every event whose *presentation tick* has been
## reached. Impact consequences are staggered a little (carve now, settle/fall shortly after,
## turn banner last) so the player can follow cause and effect; this only moves the visuals in
## time, never changes outcomes. `instant` mode (tests) applies a whole timeline at once.
##
## Floats and non-determinism are fine here: the seed is just an input to the simulation.

signal timeline_finished
signal round_finished(winner: int)
signal match_finished
signal toast_shown(text: String)
## Every player pressed READY; the round is about to start.
signal shop_finished

const TITLE_SCENE: String = "res://ui/title/title_screen.tscn"
const TPS: float = float(SimConstants.TICKS_PER_SECOND)
## Presentation offsets in ticks (see class comment).
const SETTLE_DELAY: int = 14
const POST_DELAY: int = 46
const END_HOLD_TICKS: int = 42
const SHORT_HOLD_TICKS: int = 18
const MOVE_HOLD_TICKS: int = 5
const POPUP_POOL: int = 14
const FX_POOL: int = 8
const FLAME_POOL: int = 2
const BEAM_POOL: int = 2
const PULL_POOL: int = 2
## Sludge pours over this many ticks (the following events wait for it).
const POUR_TICKS: int = 54
## Event types shown at their own tick, independent of the list order: shells, their ends and the
## blast flashes. Splitter children all start at the apex and land at different ticks, so
## their ticks are not monotone along the list, while the terrain events of the same
## timeline must stay in list order.
const VISUAL_TYPES: PackedStringArray = ["projectile", "projectile_end", "explosion"]
## Events that deserve the long hold before the next turn.
const IMPACT_TYPES: PackedStringArray = ["explosion", "round_end", "beam", "flames", "tunnel", "terrain_add",
		"terrain_pour", "tank_drag", "well_on"]
## Hit-box of a tank for the HUD fade (world units around the ground point), emblem included.
const TANK_FADE_RECT: Rect2 = Rect2(-22.0, -84.0, 44.0, 86.0)
## Where the "you" arrow's tip sits above the ground point (world units).
const YOU_TIP_Y: float = -86.0
const SHAKE_PER_RADIUS: float = 1.0 / 80.0
const MOVE_STEP: int = 10
## Minimum gap between idle autosaves (a burst of shop taps saves once).
const SAVE_DEBOUNCE: float = 0.4

# --- scene nodes ---
@onready var _sky: NeonSky = $Sky
@onready var _world: Node2D = $World
@onready var _terrain_view: TerrainView = $World/Terrain
@onready var _trail: ShellTrail = $World/ShellTrail
@onready var _camera: CameraShake = $Camera
@onready var _hud: BattleHud = $HudLayer/Hud
@onready var _overlay_layer: CanvasLayer = $OverlayLayer

# --- model (authoritative state + display copies) ---
var session: MatchSession = null
var state: MatchState = null
var display_terrain: Terrain = null
var round_wins: PackedInt32Array = PackedInt32Array()
var mismatch_count: int = 0

# --- configuration (set via configure() before the node enters the tree) ---
var _rounds: int = 3
var _seed: int = 0
var _players: int = 2
var _instant: bool = false
var _configured: bool = false
var _autosave_path: String = ""

# --- views ---
var _tank_views: Array[TankView] = []
var _fx: Array[Explosion] = []
var _fx_next: int = 0
var _popups: Array[DamagePopup] = []
var _popup_next: int = 0
var _popup_slot: int = 0
var _flames: Array[FlameField] = []
var _flame_next: int = 0
var _beams: Array[BeamFx] = []
var _beam_next: int = 0
var _pulls: Array[PullRings] = []
var _pull_next: int = 0
var _markers: BattleMarkers = null
var _wells: Dictionary = {}
var _preview: TrajectoryPreview = null
var _toast: Toast = null
var _shop: ShopFlow = null
var _pause_overlay: PauseOverlay = null
var _settings_overlay: SettingsOverlay = null
## The hidden diagnostics screen opened by a long press on the pause button (the one in the
## settings overlay is opened by tapping the version number).
var _diag: DiagnosticsOverlay = null
var _round_overlay: RoundEndOverlay = null
var _match_overlay: MatchEndOverlay = null
## tank id -> {tween: Tween, end: Vector2}: the one slide/fall animation a tank view may have.
var _tank_tweens: Dictionary = {}

# --- aim, weapon and money (per tank, local to the show layer) ---
var _aim_angle: PackedInt32Array = PackedInt32Array()
var _aim_power: PackedInt32Array = PackedInt32Array()
var _selected: PackedStringArray = PackedStringArray()
var _round_money: PackedInt32Array = PackedInt32Array()
var _summary_pending: bool = false

# --- playback ---
var _events: Array[Dictionary] = []
var _present: PackedInt32Array = PackedInt32Array()
var _ev_i: int = 0
## Visual events (VISUAL_TYPES) sorted by tick, and the index of the next one to show.
var _vis: Array[Dictionary] = []
var _vis_i: int = 0
var _playhead: float = 0.0
var _end_tick: float = 0.0
var _playing: bool = false
var _busy: bool = false
var _speed: float = 1.0
## id -> {trail: ShellTrail, start: int, points: int}: shells currently in flight.
var _shells: Dictionary = {}
var _trail_pool: Array[ShellTrail] = []
var _round_winner: int = -1
var _round_ended: bool = false
var _timelines_played: int = 0
## Tank whose turn the HUD shows (the "you" marker follows it) and the tank that fired.
var _turn_tank: int = -1
var _shooter: int = -1
## The sludge pour in progress: {cols, material, start, done} or empty.
var _pour: Dictionary = {}
## tank id -> where a walk/drag put the tank on the ground (see _on_tank_slide).
var _slide_ground: Dictionary = {}

# --- autosave ---
var _save_dirty: bool = false
var _save_cooldown: float = 0.0
var _saves_done: int = 0

# --- debug hooks (ShotArgs) ---
var _elapsed: float = 0.0
var _auto_timer: float = 0.0
var _auto_fire_pending: bool = false
var _hooks_done: bool = false
var _frozen: bool = false
var _fire_timeline: bool = false
var _fire_count: int = 0


func _init() -> void:
	# Before children's _ready so the HUD sees the emulated DPI.
	ShotArgs.parse()
	SettingsStore.ensure_loaded()


## Test/automation entry: call before add_child(). seed 0 = random. instant = no animation.
## Autosaving is off unless set_autosave_path() is called as well.
func configure(rounds: int, seed_value: int, instant: bool = false, players: int = 2) -> void:
	_rounds = rounds
	_seed = seed_value
	_instant = instant
	_players = players
	_configured = true


## Enables autosaving to `path` (call before add_child()).
func set_autosave_path(path: String) -> void:
	_autosave_path = path


func _ready() -> void:
	var resume: bool = false
	if not _configured:
		_rounds = ShotArgs.rounds if ShotArgs.rounds > 0 else BattleConfig.rounds
		_seed = ShotArgs.seed_value if ShotArgs.seed_value != 0 else BattleConfig.seed_value
		_players = ShotArgs.players if ShotArgs.players > 0 else 2
		_instant = BattleConfig.instant
		_autosave_path = BattleConfig.autosave_path
		resume = BattleConfig.resume
		BattleConfig.resume = false
	# We handle the Android back button ourselves (opens the pause menu).
	get_tree().set_quit_on_go_back(false)
	_speed = ShowSettings.playback_speed if ShotArgs.speed <= 0.0 else ShotArgs.speed
	_build_support_nodes()
	_hud.angle_changed.connect(_on_hud_angle)
	_hud.power_changed.connect(_on_hud_power)
	_hud.fire_pressed.connect(func() -> void: fire_current())
	_hud.pause_pressed.connect(open_pause)
	_hud.diagnostics_requested.connect(open_diagnostics)
	_hud.speed_pressed.connect(toggle_speed)
	_hud.weapon_picker_requested.connect(open_weapon_picker)
	_hud.weapon_selected.connect(func(id: String) -> void: select_weapon(id))
	_hud.item_pressed.connect(func(id: String) -> void: use_item(id))
	_hud.move_pressed.connect(func(dir: int) -> void: move_current(dir))
	_hud.set_speed(_speed)
	LayoutWatch.attach(self, _frame_camera)
	_frame_camera()
	_start_match(resume)
	_auto_fire_pending = ShotArgs.auto_fire
	_auto_timer = 0.4
	ShotHook.attach(self)


func _exit_tree() -> void:
	# Never leave the whole tree paused behind us.
	if is_inside_tree() and get_tree().paused:
		get_tree().paused = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if _diag != null and _diag.visible:
				_diag.close()
			elif _settings_overlay != null and _settings_overlay.visible:
				_settings_overlay.close()
			elif is_paused():
				close_pause()
			else:
				open_pause()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			# The OS may kill the app any time after these: save what we have.
			if state != null:
				autosave_now()


# ======================================================================================
# Setup
# ======================================================================================

func _build_support_nodes() -> void:
	_trail_pool.append(_trail)
	_preview = TrajectoryPreview.new()
	_preview.name = "TrajectoryPreview"
	_preview.visible = false
	_world.add_child(_preview)
	_world.move_child(_preview, _trail.get_index())
	var fx_scene: PackedScene = load("res://show/fx/explosion.tscn")
	for i: int in range(FX_POOL):
		var e: Explosion = fx_scene.instantiate()
		e.name = "Explosion%d" % i
		_world.add_child(e)
		_fx.append(e)
	for i: int in range(FLAME_POOL):
		var f := FlameField.new()
		f.name = "Flames%d" % i
		_world.add_child(f)
		_flames.append(f)
	for i: int in range(BEAM_POOL):
		var b := BeamFx.new()
		b.name = "Beam%d" % i
		_world.add_child(b)
		_beams.append(b)
	for i: int in range(PULL_POOL):
		var pr := PullRings.new()
		pr.name = "Pull%d" % i
		_world.add_child(pr)
		_pulls.append(pr)
	for i: int in range(POPUP_POOL):
		var p := DamagePopup.new()
		p.name = "Popup%d" % i
		_world.add_child(p)
		_popups.append(p)
	_toast = Toast.new()
	_toast.name = "Toast"
	_hud.get_parent().add_child(_toast)
	# Above the HUD (10), below the overlays (20): the "you" arrow and off-screen shell chevrons.
	var marker_layer := CanvasLayer.new()
	marker_layer.name = "MarkerLayer"
	marker_layer.layer = 11
	add_child(marker_layer)
	_markers = BattleMarkers.new()
	marker_layer.add_child(_markers)
	_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_shop = ShopFlow.new()
	_shop.all_ready.connect(_on_shop_all_ready)
	_overlay_layer.add_child(_shop)
	_round_overlay = RoundEndOverlay.new()
	_round_overlay.next_pressed.connect(next_round)
	_overlay_layer.add_child(_round_overlay)
	_match_overlay = MatchEndOverlay.new()
	_match_overlay.new_match_pressed.connect(restart_match)
	_match_overlay.title_pressed.connect(quit_to_title)
	_overlay_layer.add_child(_match_overlay)
	_pause_overlay = PauseOverlay.new()
	_pause_overlay.resume_pressed.connect(close_pause)
	_pause_overlay.restart_pressed.connect(restart_match)
	_pause_overlay.quit_pressed.connect(quit_to_title)
	_pause_overlay.settings_pressed.connect(_open_settings_from_pause)
	_overlay_layer.add_child(_pause_overlay)
	_settings_overlay = SettingsOverlay.new()
	_settings_overlay.closed.connect(_on_settings_closed)
	_overlay_layer.add_child(_settings_overlay)
	_diag = DiagnosticsOverlay.new()
	_diag.closed.connect(_on_diag_closed)
	_overlay_layer.add_child(_diag)


func _frame_camera() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var f: Dictionary = BattleFraming.frame(vis)
	_camera.zoom = Vector2.ONE * float(f["zoom"])
	_camera.position = f["center"] as Vector2


## Starts a fresh match (settings from setup / defaults) or restores the autosave.
func _start_match(resume: bool = false) -> void:
	var restored: MatchSession = null
	if resume:
		restored = MatchSession.restore(_autosave_path)
		if restored != null:
			PlayerLooks.from_dict(restored.meta.get("looks", {}) as Dictionary)
	if restored != null:
		_adopt_session(restored, true)
	else:
		var fresh: MatchSession = MatchSession.create(_new_settings())
		_adopt_session(fresh, false)


## Makes `new_session` the running match: per-tank data, tank views, display, first screen.
func _adopt_session(new_session: MatchSession, restored: bool) -> void:
	_cancel_playback()
	session = new_session
	state = session.state
	if not restored:
		_apply_debug_inventory()
	_init_per_tank_data(restored)
	_close_overlays()
	_shop.close()
	for v: TankView in _tank_views:
		v.queue_free()
	_tank_views.clear()
	for i: int in range(state.tanks.size()):
		var v: TankView = (load("res://show/tank_view.tscn") as PackedScene).instantiate()
		v.name = "Tank%d" % i
		_world.add_child(v)
		_tank_views.append(v)
	mismatch_count = 0
	_round_winner = -1
	_rebuild_display()
	_apply_initial_aim_override()
	_sync_round_wins()
	_enter_phase()


func _new_settings() -> MatchSettings:
	var base: MatchSettings = BattleConfig.settings if (BattleConfig.settings != null and not _configured) else null
	var settings: MatchSettings = base.duplicate_settings() if base != null else MatchSettings.new()
	if base == null:
		settings.num_tanks = _players
		settings.rounds = _rounds
		settings.wind_max = 100
		if ShotArgs.money >= 0:
			settings.start_money = ShotArgs.money
	settings.seed = _seed if _seed != 0 else (settings.seed if settings.seed != 0 else int(randi()))
	return settings


## Debug hook (--give=id:n): a screenshot/test aid that fills inventories without a shop visit.
func _apply_debug_inventory() -> void:
	if _configured:
		return
	for g: String in ShotArgs.gives:
		var parts: PackedStringArray = g.split(":")
		if parts.size() != 2 or not Catalog.has(parts[0]):
			continue
		for t: TankState in state.tanks:
			t.set_stock(parts[0], parts[1].to_int())


func _init_per_tank_data(restored: bool) -> void:
	var n: int = state.tanks.size()
	_aim_angle.resize(n)
	_aim_power.resize(n)
	_selected = PackedStringArray()
	for _i: int in range(n):
		_selected.append(Catalog.SPARK_DART)
	_round_money.resize(n)
	_round_money.fill(0)
	_summary_pending = false
	_round_ended = false
	if restored:
		var saved: Variant = session.meta.get("round_money", [])
		if typeof(saved) == TYPE_ARRAY and (saved as Array).size() == n:
			for i: int in range(n):
				_round_money[i] = int((saved as Array)[i])
		_summary_pending = session.meta.get("summary_pending", false) as bool and state.phase == SimConstants.PHASE_SHOP
	elif ShotArgs.select_weapon != "" and not _configured:
		_selected[0] = ShotArgs.select_weapon


## Rebuilds everything that mirrors the state: terrain copy, tank views, per-tank aim.
func _rebuild_display() -> void:
	_cancel_tank_tweens()
	var has_terrain: bool = state.terrain != null
	_world.visible = has_terrain and state.phase != SimConstants.PHASE_SHOP
	if has_terrain:
		display_terrain = state.terrain.duplicate_terrain()
		if _terrain_view.world_width == 0:
			_terrain_view.setup(display_terrain.cells, display_terrain.width, display_terrain.height)
		else:
			_terrain_view.update_cells(display_terrain.cells)
	else:
		display_terrain = null
	_terrain_view.visible = has_terrain
	for t: TankState in state.tanks:
		var v: TankView = _tank_views[t.id]
		v.visible = has_terrain
		v.set_look(PlayerLooks.color_index(t.id), PlayerLooks.emblem_index(t.id))
		v.position = Vector2(float(t.x), float(t.y))
		v.set_dead(not t.alive)
		v.set_health(t.health, SimConstants.MAX_HEALTH)
		v.set_angle_tenths(t.angle)
		v.set_shield(t.shield_hp if t.has_shield() else 0, _shield_max(t.shield_type))
		v.set_repulsor(t.repulsor_charge > 0 and t.alive)
		_aim_angle[t.id] = t.angle
		_aim_power[t.id] = t.power
	_rebuild_wells()
	_clear_shells()
	_pour = {}


func _shield_max(shield_type: int) -> int:
	var id: String = Catalog.id_at(shield_type)
	if id == "" or not ItemDefs.has(id):
		return 1
	return ItemDefs.get_def(id)["hp"] as int


func _rebuild_wells() -> void:
	for w: Variant in _wells.values():
		(w as WellView).queue_free()
	_wells.clear()
	for well: Dictionary in state.wells:
		_place_well(well["owner"] as int, well["x"] as int, well["y"] as int, well["expires_turn"] as int)


func _apply_initial_aim_override() -> void:
	if ShotArgs.aim_angle >= 0 and state.phase == SimConstants.PHASE_AIM:
		_aim_angle[state.current_tank] = ShotArgs.aim_angle
		_aim_power[state.current_tank] = ShotArgs.aim_power
		_tank_views[state.current_tank].set_angle_tenths(ShotArgs.aim_angle)


## Shows whatever the phase calls for: shop, round summary, aim HUD or the final standings.
func _enter_phase() -> void:
	match state.phase:
		SimConstants.PHASE_SHOP:
			_set_busy(true)
			if Simulation.all_ready(state):
				# Saved between the last READY and the round start: finish the hand-off.
				_begin_round()
			elif _summary_pending:
				_show_round_summary()
			else:
				_open_shop()
		SimConstants.PHASE_MATCH_OVER:
			_show_match_over()
		_:
			_hud.visible = true
			_set_busy(false)
			_begin_turn_ui()
			_run_start_hooks()


## HUD + preview for whoever's turn it is now.
func _begin_turn_ui() -> void:
	var id: int = state.current_tank
	_turn_tank = id
	_ensure_selection(id)
	_hud.show_turn(id)
	_hud.set_angle_tenths(_aim_angle[id])
	_hud.set_power(_aim_power[id])
	_refresh_loadout(id)
	_request_preview()


## Money, weapon button, item tray and fuel readout for tank `id`.
func _refresh_loadout(id: int) -> void:
	var t: TankState = state.tanks[id]
	_hud.set_money(t.money)
	var w: String = _selected[id]
	_hud.set_weapon(w, _weapon_count(t, w))
	var items: Array[Dictionary] = []
	for item_id: String in Catalog.IDS:
		if ItemDefs.has(item_id) and _is_usable_item(item_id):
			items.append({"id": item_id, "count": t.stock_of(item_id)})
	_hud.set_items(items)
	_hud.set_fuel(_fuel_total(t))


static func _is_usable_item(item_id: String) -> bool:
	var behavior: String = ItemDefs.get_def(item_id)["behavior"]
	return behavior == "shield" or behavior == "repulsor" or behavior == "repair"


static func _weapon_count(t: TankState, weapon_id: String) -> int:
	if WeaponDefs.get_def(weapon_id).get("unlimited", false):
		return -1
	return t.stock_of(weapon_id)


## Fuel in the tank plus what the owned fuel cells would add (0 = hide the move buttons).
static func _fuel_total(t: TankState) -> int:
	var cell: int = ItemDefs.get_def("fuel_cell")["amount"] as int
	return t.fuel + t.stock_of("fuel_cell") * cell


# ======================================================================================
# Public API (also used by tests and the auto-play hooks)
# ======================================================================================

func get_state() -> MatchState:
	return state


func get_session() -> MatchSession:
	return session


func get_tank_view(i: int) -> TankView:
	return _tank_views[i]


func get_hud() -> BattleHud:
	return _hud


func get_preview() -> TrajectoryPreview:
	return _preview


func get_pause_overlay() -> PauseOverlay:
	return _pause_overlay


func get_settings_overlay() -> SettingsOverlay:
	return _settings_overlay


func get_diagnostics() -> DiagnosticsOverlay:
	return _diag


func get_round_overlay() -> RoundEndOverlay:
	return _round_overlay


func get_match_overlay() -> MatchEndOverlay:
	return _match_overlay


func get_shop() -> ShopFlow:
	return _shop


func get_toast() -> Toast:
	return _toast


func get_terrain_view() -> TerrainView:
	return _terrain_view


func get_well_view(owner_id: int) -> WellView:
	return _wells.get(owner_id) as WellView


func get_aim(tank_id: int) -> Vector2i:
	return Vector2i(_aim_angle[tank_id], _aim_power[tank_id])


func get_speed() -> float:
	return _speed


func is_busy() -> bool:
	return _busy


func is_paused() -> bool:
	return _pause_overlay != null and _pause_overlay.visible


func timelines_played() -> int:
	return _timelines_played


func round_earnings(tank_id: int) -> int:
	return _round_money[tank_id]


func autosaves_done() -> int:
	return _saves_done


func get_autosave_path() -> String:
	return _autosave_path


## Sets the aim of the tank whose turn it is (ignored while input is locked).
func set_aim(angle: int, power: int) -> void:
	if _busy:
		return
	var id: int = state.current_tank
	_aim_angle[id] = clampi(angle, 0, SimConstants.MAX_ANGLE)
	_aim_power[id] = clampi(power, 0, SimConstants.MAX_POWER)
	_tank_views[id].set_angle_tenths(_aim_angle[id])
	_hud.set_angle_tenths(_aim_angle[id])
	_hud.set_power(_aim_power[id])
	_request_preview()


## The weapon the current tank will fire.
func get_selected_weapon() -> String:
	_ensure_selection(state.current_tank)
	return _selected[state.current_tank]


## Picks a weapon for the current tank. Returns "" or an error key ("out_of_stock",
## "unknown_weapon", "busy").
func select_weapon(item_id: String) -> String:
	if _busy:
		return "busy"
	if not WeaponDefs.has(item_id):
		return "unknown_weapon"
	var id: int = state.current_tank
	if _weapon_count(state.tanks[id], item_id) == 0:
		_show_toast(tr("ERR_OUT_OF_STOCK"))
		return "out_of_stock"
	_selected[id] = item_id
	_refresh_loadout(id)
	return ""


## Falls back to the Spark Dart when the chosen weapon ran out.
func _ensure_selection(id: int) -> void:
	var w: String = _selected[id]
	if not WeaponDefs.has(w) or _weapon_count(state.tanks[id], w) == 0:
		_selected[id] = Catalog.SPARK_DART


## Opens the weapon picker with the weapons the current tank owns.
func open_weapon_picker() -> void:
	if _busy or state.phase != SimConstants.PHASE_AIM:
		return
	var t: TankState = state.tanks[state.current_tank]
	var entries: Array[Dictionary] = []
	for id: String in Catalog.IDS:
		if not WeaponDefs.has(id):
			continue
		var n: int = _weapon_count(t, id)
		if n != 0:
			entries.append({"id": id, "count": n})
	_hud.open_weapon_picker(entries, get_selected_weapon())


## Submits an action through the session. Returns "" on success or the validation error key
## ("busy" if input is locked). Errors show a toast and change nothing.
func submit_action(action: Dictionary) -> String:
	if _busy:
		return "busy"
	var res: Dictionary = session.submit(action)
	var err: String = res["err"]
	if err != "":
		_show_toast(ErrorText.message(err))
		return err
	_save_dirty = true
	_play(res["events"] as Array[Dictionary])
	return ""


## Fires the current tank with its remembered aim and selected weapon. Returns "" on
## success, or the validation error key. "busy" if input is locked.
func fire_current() -> String:
	if _busy:
		return "busy"
	var id: int = state.current_tank
	_ensure_selection(id)
	var action: Dictionary = {
		"kind": "fire", "tank": id, "angle": _aim_angle[id], "power": _aim_power[id], "weapon": _selected[id],
	}
	var err: String = submit_action(action)
	if err == "":
		_ensure_selection(id)  # the shot may have used the last unit
	return err


## Drives the current tank 10 cells left (-1) or right (+1). Silent while busy (a held
## button repeats faster than the animation sometimes finishes).
func move_current(dir: int) -> String:
	if _busy:
		return "busy"
	return submit_action({"kind": "move", "tank": state.current_tank, "dx": MOVE_STEP * signi(dir)})


func use_item(item_id: String) -> String:
	if _busy:
		return "busy"
	return submit_action({"kind": "use_item", "tank": state.current_tank, "item": item_id})


func pass_turn() -> String:
	if _busy:
		return "busy"
	return submit_action({"kind": "pass", "tank": state.current_tank})


## NEXT on the round summary: on to the shop.
func next_round() -> void:
	if state.phase != SimConstants.PHASE_SHOP:
		return
	_round_overlay.close()
	_summary_pending = false
	_world.visible = false
	_open_shop()


## Test/automation shortcut: every player presses READY and the round starts. Returns false
## if not in the shop.
func quick_start() -> bool:
	if state.phase != SimConstants.PHASE_SHOP:
		return false
	for t: TankState in state.tanks:
		if not t.ready:
			session.submit({"kind": "ready", "tank": t.id})
	_shop.close()
	_round_overlay.close()
	_summary_pending = false
	_begin_round()
	return true


## New match with the same settings. A fixed seed (tests, --seed) replays it; otherwise a new
## random seed is drawn. The autosave is replaced by the new match's.
func restart_match() -> void:
	close_pause()
	var keep: MatchSettings = state.settings.duplicate_settings()
	keep.seed = _seed if _seed != 0 else int(randi())
	if _autosave_path != "":
		SaveStore.delete(_autosave_path)
	_adopt_session(MatchSession.create(keep), false)
	_save_dirty = true


func quit_to_title() -> void:
	close_pause()
	if state != null and state.phase != SimConstants.PHASE_MATCH_OVER:
		autosave_now()
	get_tree().change_scene_to_file(TITLE_SCENE)


func open_pause() -> void:
	if is_paused():
		return
	_pause_overlay.open_for(_displayed_round_number(), state.settings.rounds)
	_preview.hide_preview()
	get_tree().paused = true


func close_pause() -> void:
	if _pause_overlay != null:
		_pause_overlay.close()
	if _settings_overlay != null:
		_settings_overlay.close_silently()
	if is_inside_tree():
		get_tree().paused = false
	_request_preview()


## Long press on the pause button: the layout diagnostics over the (paused) battle.
func open_diagnostics() -> void:
	if _diag.visible:
		return
	_preview.hide_preview()
	get_tree().paused = true
	_diag.open()


func _on_diag_closed() -> void:
	# Back to whatever was behind it: the pause menu keeps the tree paused, the battle does not.
	if is_paused() or _settings_overlay.visible:
		return
	get_tree().paused = false
	_request_preview()


func _displayed_round_number() -> int:
	var n: int = state.round_index + (2 if state.phase == SimConstants.PHASE_SHOP else 1)
	return clampi(n, 1, state.settings.rounds)


func _open_settings_from_pause() -> void:
	_pause_overlay.visible = false
	_settings_overlay.open()


func _on_settings_closed() -> void:
	if get_tree().paused:
		_pause_overlay.visible = true
	# Text size may have changed: every apply_scale() hangs off the viewport signal.
	_hud.apply_scale()


func toggle_speed() -> void:
	set_speed(2.0 if _speed < 1.5 else 1.0)


func set_speed(s: float) -> void:
	_speed = s
	ShowSettings.playback_speed = s
	_hud.set_speed(s)


## Compares the display copy with the authoritative state; snaps the display on mismatch.
func check_consistency() -> bool:
	var ok: bool = true
	if state.terrain != null and (display_terrain == null or display_terrain.cells != state.terrain.cells):
		ok = false
		_report_terrain_diff()
	for t: TankState in state.tanks:
		var v: TankView = _tank_views[t.id]
		var want := Vector2(float(t.x), float(t.y))
		var want_shield: int = t.shield_hp if t.has_shield() else 0
		if v.position != want or v.get_health() != t.health or v.is_dead() == t.alive \
				or v.get_shield_hp() != want_shield or v.is_repulsor_on() != (t.repulsor_charge > 0 and t.alive):
			ok = false
			push_error("BattleController: tank %d view (pos %s, hp %d, dead %s, shield %d, repulsor %s) differs from state (pos %s, hp %d, alive %s, shield %d, repulsor %d)"
					% [t.id, v.position, v.get_health(), v.is_dead(), v.get_shield_hp(), v.is_repulsor_on(),
					want, t.health, t.alive, want_shield, t.repulsor_charge])
	if _wells.size() != state.wells.size():
		ok = false
		push_error("BattleController: %d well views but the state has %d wells" % [_wells.size(), state.wells.size()])
	if not ok:
		mismatch_count += 1
		_snap_display_to_state()
	return ok


func _report_terrain_diff() -> void:
	if display_terrain == null:
		push_error("BattleController: no display terrain although the state has one")
		return
	var diff: int = 0
	var first: int = -1
	for i: int in range(state.terrain.cells.size()):
		if display_terrain.cells[i] != state.terrain.cells[i]:
			diff += 1
			if first < 0:
				first = i
	push_error("BattleController: display terrain differs from state in %d cells (first index %d = x %d, y %d)"
			% [diff, first, first / state.terrain.height, first % state.terrain.height])


func _snap_display_to_state() -> void:
	_rebuild_display()
	_hud.set_wind(state.wind)


# ======================================================================================
# Shop flow
# ======================================================================================

func _open_shop() -> void:
	_set_busy(true)
	_hud.visible = false
	_world.visible = false
	_preview.hide_preview()
	var skip: bool = ShotArgs.shop_player > 0 and not _configured
	var start: int = ShotArgs.shop_player - 1 if skip else -1
	_shop.open(state, _shop_submit, start, skip, ShotArgs.shop_tab, ShotArgs.shop_select)


## The shop screens submit buy/sell/ready here. Returns "" or the error key.
func _shop_submit(action: Dictionary) -> String:
	var res: Dictionary = session.submit(action)
	var err: String = res["err"]
	if err == "":
		_save_dirty = true
		if _instant:
			autosave_now()
			_save_dirty = false
	return err


func _on_shop_all_ready() -> void:
	_begin_round()


## Everyone is ready: ask the simulation to start the round and play round_start / wind / turn.
func _begin_round() -> void:
	var events: Array[Dictionary] = session.start_round()
	if events.is_empty():
		push_error("BattleController: start_round refused (not everyone is ready?)")
		return
	_shop.close()
	_round_overlay.close()
	_hud.visible = true
	_world.visible = true
	_round_money.fill(0)
	_save_dirty = true
	shop_finished.emit()
	_play(events)


# ======================================================================================
# Playback
# ======================================================================================

func _play(events: Array[Dictionary]) -> void:
	_events = events
	_present = _compute_present(events)
	_vis = _visual_events(events)
	_ev_i = 0
	_vis_i = 0
	_pour = {}
	_slide_ground.clear()
	_playhead = 0.0
	_frozen = false
	_fire_timeline = false
	_timelines_played += 1
	_round_winner = -1
	_round_ended = false
	_popup_slot = 0
	var quiet: bool = _is_move_only(events)
	_set_busy(true, quiet)
	_preview.hide_preview()
	var last: int = 0
	var impact: bool = false
	for i: int in range(events.size()):
		last = maxi(last, _present[i] if _present[i] >= 0 else (events[i]["tick"] as int))
		var type: String = events[i]["type"]
		if IMPACT_TYPES.has(type):
			impact = true
		elif type == "fire":
			_fire_count += 1
			_fire_timeline = _fire_count == ShotArgs.freeze_shot
	var hold: int = END_HOLD_TICKS if impact else (MOVE_HOLD_TICKS if quiet else SHORT_HOLD_TICKS)
	_end_tick = float(last + hold)
	if _instant:
		while _ev_i < _events.size():
			_dispatch(_events[_ev_i])
			_ev_i += 1
		_finish_playback()
	else:
		_playing = true


static func _is_move_only(events: Array[Dictionary]) -> bool:
	if events.is_empty():
		return false
	for e: Dictionary in events:
		if e["type"] != "tank_move":
			return false
	return true


func _cancel_playback() -> void:
	_playing = false
	_events = []
	_vis = []
	_ev_i = 0
	_vis_i = 0
	_pour = {}
	_clear_shells()
	_cancel_tank_tweens()


func _cancel_tank_tweens() -> void:
	for entry: Variant in _tank_tweens.values():
		var tw: Tween = (entry as Dictionary)["tween"]
		if tw.is_valid():
			tw.kill()
	_tank_tweens.clear()


## Presentation tick of every list-order event (see class comment). Monotone, so events always
## play in order even when a later one has an earlier base tick. Visual events (shells, blast
## flashes) get -1: they are shown at their own tick by _vis (see VISUAL_TYPES).
func _compute_present(events: Array[Dictionary]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var prev: int = 0
	var shot: bool = false
	for e: Dictionary in events:
		shot = shot or e["type"] == "fire"
	for i: int in range(events.size()):
		var e: Dictionary = events[i]
		var t: int = e["tick"]
		var type: String = e["type"]
		if VISUAL_TYPES.has(type):
			out.append(-1)
			continue
		var p: int = t
		# A shot that ends at tick 0 (the Photon Lance) still hands over the turn after a beat.
		var post: int = POST_DELAY if (t > 0 or shot) else 0
		match type:
			"terrain_settle", "tank_fall", "tank_destroyed", "chute":
				p = t + SETTLE_DELAY
			"damage":
				p = t + (SETTLE_DELAY if e["cause"] == "fall" else 0)
			"wind", "turn", "round_end":
				p = t + post
			"well_off":
				# A well replaced by its owner goes off together with the new one; an expiry
				# goes off with the turn change.
				var replaced: bool = i + 1 < events.size() and events[i + 1]["type"] == "well_on" \
						and events[i + 1]["owner"] == e["owner"]
				p = t if replaced else t + post
			"money":
				p = prev  # shown together with the damage / kill / round pay it belongs to
		prev = maxi(prev, p)
		out.append(prev)
		if type == "terrain_pour":
			prev += POUR_TICKS  # whatever follows waits for the sludge to flow
	return out


## The visual events of a timeline in tick order (stable: equal ticks keep list order).
static func _visual_events(events: Array[Dictionary]) -> Array[Dictionary]:
	var keyed: Array[Vector2i] = []
	for i: int in range(events.size()):
		if VISUAL_TYPES.has(events[i]["type"] as String):
			keyed.append(Vector2i(events[i]["tick"] as int, i))
	keyed.sort()  # Vector2i compares x then y: tick, then list index
	var out: Array[Dictionary] = []
	for k: Vector2i in keyed:
		out.append(events[k.y])
	return out


func _process(delta: float) -> void:
	_elapsed += delta
	if state == null:
		return
	if state.phase == SimConstants.PHASE_AIM:
		var t: TankView = _tank_views[state.current_tank]
		_hud.set_aim_pivot(get_viewport().get_canvas_transform() * (t.position + Vector2(0, -TankView.TANK_H * 0.5) * TankView.VISUAL_SCALE))
		_sky.set_parallax(_camera.get_screen_center_position())
	if _playing and not _frozen:
		_playhead += delta * TPS * _speed
		if ShotArgs.freeze_tick >= 0 and _fire_timeline and _playhead >= float(ShotArgs.freeze_tick):
			_playhead = float(ShotArgs.freeze_tick)
			_frozen = true  # screenshot hook: hold this moment of the shot
		_advance_playback()
	_update_overlays()
	_tick_autosave(delta)
	_run_auto_hooks(delta)


func _advance_playback() -> void:
	while _vis_i < _vis.size() and float(_vis[_vis_i]["tick"] as int) <= _playhead:
		_dispatch(_vis[_vis_i])
		_vis_i += 1
	while _ev_i < _events.size():
		if _present[_ev_i] < 0:
			_ev_i += 1  # a visual event: shown by _vis
			continue
		if float(_present[_ev_i]) > _playhead:
			break
		_dispatch(_events[_ev_i])
		_ev_i += 1
	_advance_pour()
	for entry: Variant in _shells.values():
		var sh: Dictionary = entry
		# path[i] is the position at tick start + i + 1 (ARCHITECTURE section 26).
		(sh["trail"] as ShellTrail).set_progress(clampf(_playhead - float(sh["start"]) - 1.0, 0.0, float((sh["points"] as int) - 1)))
	if _frozen:
		return
	if _playhead >= _end_tick and _ev_i >= _events.size() and _vis_i >= _vis.size():
		_finish_playback()


## True once the screenshot hook (--freeze-tick) has stopped the playhead.
func is_frozen() -> bool:
	return _frozen


func _finish_playback() -> void:
	_playing = false
	_flush_pour()
	_clear_shells()
	check_consistency()
	_sync_round_wins()
	timeline_finished.emit()
	if _instant and _save_dirty:
		autosave_now()
	match state.phase:
		SimConstants.PHASE_SHOP:
			if _round_ended:
				_summary_pending = true
				_show_round_summary()
				round_finished.emit(_round_winner)
				_save_dirty = true
				if _instant:
					autosave_now()
			else:
				_set_busy(true)
		SimConstants.PHASE_MATCH_OVER:
			_show_match_over()
			round_finished.emit(_round_winner)
			match_finished.emit()
		_:
			_set_busy(false)
			_begin_turn_ui()
			_run_start_hooks()


func _dispatch(e: Dictionary) -> void:
	var type: String = e["type"]
	if not _pour.is_empty() and not VISUAL_TYPES.has(type):
		_flush_pour()  # the next terrain event builds on the finished pour
	match type:
		"round_start":
			_rebuild_display()
		"fire":
			_shooter = e["tank"]
		"projectile":
			_start_shell(e)
		"projectile_end":
			_end_shell(e)
		"explosion":
			_on_explosion(e)
		"terrain_carve":
			display_terrain.carve_circle(e["x"], e["y"], e["radius"])
			_terrain_view.update_cells(display_terrain.cells)
		"terrain_settle":
			display_terrain.settle(e["x0"], e["x1"])
			_terrain_view.update_cells(display_terrain.cells)
		"tunnel":
			display_terrain.carve_tunnel(e["x0"], e["y0"], e["x1"], e["y1"], e["radius"])
			_terrain_view.update_cells(display_terrain.cells)
		"terrain_add":
			display_terrain.add_circle_skipping(e["x"], e["y"], e["radius"], e["material"],
					e.get("skip", PackedInt32Array()) as PackedInt32Array)
			_terrain_view.update_cells(display_terrain.cells)
		"terrain_pour":
			_on_terrain_pour(e)
		"damage":
			_on_damage(e)
		"money":
			_on_money(e)
		"tank_fall":
			_on_tank_fall(e)
		"tank_move", "tank_drag":
			_on_tank_slide(e)
		"tank_destroyed":
			_on_tank_destroyed(e)
		"shield_on":
			_tank_views[e["tank"]].set_shield(e["hp"], e["hp"])
		"shield_hit":
			_on_shield_hit(e)
		"shield_down":
			_tank_views[e["tank"]].shield_break()
		"repulsor_on":
			_tank_views[e["tank"]].set_repulsor(true)
		"repulsor_down":
			_tank_views[e["tank"]].set_repulsor(false)
		"chute":
			_on_chute(e)
		"repair":
			_on_repair(e)
		"flames":
			_on_flames(e)
		"beam":
			_on_beam(e)
		"well_on":
			_place_well(e["owner"], e["x"], e["y"], e["expires_turn"])
		"well_off":
			_remove_well(e["owner"])
		"wind":
			_hud.set_wind(e["wind"])
		"turn":
			var id: int = e["tank"]
			_turn_tank = id
			_ensure_selection(id)
			_hud.show_turn(id)
			_hud.set_angle_tenths(_aim_angle[id])
			_hud.set_power(_aim_power[id])
			_refresh_loadout(id)
		"round_end":
			_round_ended = true
			_round_winner = e["winner"]
		# "ready" has no presentation of its own.


# --- shells ----------------------------------------------------------------------------

func _acquire_trail() -> ShellTrail:
	for t: ShellTrail in _trail_pool:
		var busy: bool = false
		for entry: Variant in _shells.values():
			if (entry as Dictionary)["trail"] == t:
				busy = true
		if not busy:
			return t
	var extra := ShellTrail.new()
	extra.name = "ShellTrail%d" % _trail_pool.size()
	_world.add_child(extra)
	_trail_pool.append(extra)
	return extra


## Starts one projectile (id 0 is the main shell; splitter children start at the apex tick).
## The trail is driven by the playhead: path[i] is the position at tick start + i + 1.
func _start_shell(e: Dictionary) -> void:
	if _instant:
		return
	var path: PackedInt32Array = e["path"]
	var n: int = path.size() / 2
	var pts := PackedVector2Array()
	pts.resize(maxi(n, 2))
	var inv: float = 1.0 / float(FixedMath.ONE)
	for i: int in range(n):
		pts[i] = Vector2(float(path[i * 2]) * inv, float(path[i * 2 + 1]) * inv)
	if n < 2:
		pts[1] = pts[0]
	var trail: ShellTrail = _acquire_trail()
	trail.play(pts)  # self-driven start sets the path; we then drive it by the playhead
	trail.set_process(false)
	trail.set_progress(0.0)
	_shells[e["id"] as int] = {"trail": trail, "start": e["tick"] as int, "points": pts.size(),
			"weapon": e.get("weapon", "") as String}


func _end_shell(e: Dictionary) -> void:
	var id: int = e["id"]
	if not _shells.has(id):
		return
	var sh: Dictionary = _shells[id]
	(sh["trail"] as ShellTrail).clear()
	_shells.erase(id)
	var reason: String = e["reason"]
	if WeaponResolver.is_impact(reason) and _behavior_of(sh["weapon"] as String) == "anchor":
		var def: Dictionary = WeaponDefs.get_def(sh["weapon"] as String)
		var p: PullRings = _pulls[_pull_next]
		_pull_next = (_pull_next + 1) % _pulls.size()
		p.play(Vector2(float(e["x"]), float(e["y"])), float(def.get("pull_r", 180)), _shooter_color())
		_haptic(30)


static func _behavior_of(weapon_id: String) -> String:
	return WeaponDefs.get_def(weapon_id).get("behavior", "") as String


func _shooter_color() -> Color:
	return PlayerLooks.color(_shooter) if _shooter >= 0 else NeonPalette.CYAN


func _clear_shells() -> void:
	for t: ShellTrail in _trail_pool:
		t.clear()
	_shells.clear()


# --- explosions, terrain -----------------------------------------------------------------

func _on_explosion(e: Dictionary) -> void:
	if _instant:
		return
	var radius: float = float(e["radius"])
	var style: int = Explosion.STYLE_STATIC if _behavior_of(e.get("weapon", "") as String) == "static" else Explosion.STYLE_BLAST
	_next_fx().play(Vector2(float(e["x"]), float(e["y"])), radius, style)
	_camera.shake(clampf(radius * SHAKE_PER_RADIUS, 0.15, 0.9))
	_haptic(clampi(roundi(radius * 2.0), 15, 90))


## Sludge: the columns are poured over POUR_TICKS (it visibly flows), in placement order, so
## the finished terrain is exactly the core's. Instant mode pours at once.
func _on_terrain_pour(e: Dictionary) -> void:
	var cols: PackedInt32Array = e["cells"]
	if _instant or cols.size() < 2:
		display_terrain.pour(cols, e["material"])
		_terrain_view.update_cells(display_terrain.cells)
		return
	_pour = {"cols": cols, "material": e["material"], "start": _playhead, "done": 0}
	_haptic(25)


func _advance_pour() -> void:
	if _pour.is_empty():
		return
	var cols: PackedInt32Array = _pour["cols"]
	var k: float = clampf((_playhead - (_pour["start"] as float)) / float(POUR_TICKS), 0.0, 1.0)
	_pour_to(ceili(float(cols.size()) * k))


func _flush_pour() -> void:
	if not _pour.is_empty():
		_pour_to((_pour["cols"] as PackedInt32Array).size())


func _pour_to(count: int) -> void:
	var cols: PackedInt32Array = _pour["cols"]
	var done: int = _pour["done"]
	if count > done:
		display_terrain.pour(cols.slice(done, count), _pour["material"] as int)
		_terrain_view.update_cells(display_terrain.cells)
		_pour["done"] = count
	if count >= cols.size():
		_pour = {}


func _on_flames(e: Dictionary) -> void:
	if _instant:
		return
	var f: FlameField = _flames[_flame_next]
	_flame_next = (_flame_next + 1) % _flames.size()
	f.play(e["points"] as PackedInt32Array)
	_haptic(40)


func _on_beam(e: Dictionary) -> void:
	if _instant:
		return
	var b: BeamFx = _beams[_beam_next]
	_beam_next = (_beam_next + 1) % _beams.size()
	b.play(Vector2(float(e["x0"]), float(e["y0"])), Vector2(float(e["x1"]), float(e["y1"])))
	_camera.shake(0.25)
	_haptic(30)


# --- wells ------------------------------------------------------------------------------

func _place_well(owner_id: int, x: int, y: int, expires_turn: int) -> void:
	_remove_well(owner_id)  # a new well by the same owner replaces the old one
	var w := WellView.new()
	w.name = "Well%d" % owner_id
	_world.add_child(w)
	var radius: float = float(WeaponDefs.get_def("singularity_seed").get("well_r", 300))
	w.place(Vector2(float(x), float(y)), radius, owner_id, expires_turn)
	_wells[owner_id] = w


func _remove_well(owner_id: int) -> void:
	if _wells.has(owner_id):
		(_wells[owner_id] as WellView).queue_free()
		_wells.erase(owner_id)


# --- tanks ------------------------------------------------------------------------------

func _on_damage(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	v.set_health(e["health"], SimConstants.MAX_HEALTH)
	if _instant:
		return
	var amount: int = e["amount"]
	var cause: String = e["cause"]
	var at: Vector2 = v.position + Vector2(0, -52.0 * TankView.VISUAL_SCALE)
	# Burning and the beam get their own colour, a word next to the number (never colour alone)
	# and a glow on the hull; blasts and falls keep the tank's colour.
	match cause:
		"burn":
			_pop(tr("DMG_BURN_FMT") % amount, NeonPalette.SUNSET, at)
			v.hit_flash(NeonPalette.SUNSET, true)
			_haptic(25)
		"beam":
			_pop(tr("DMG_BEAM_FMT") % amount, NeonPalette.CYAN, at)
			v.hit_flash(Color(0.8, 1.0, 1.0), false)
			_haptic(40)
		_:
			_pop("-%d" % amount, PlayerLooks.color(id), at)


func _on_money(e: Dictionary) -> void:
	var id: int = e["tank"]
	var delta: int = e["delta"]
	var reason: String = e["reason"]
	if reason == "buy" or reason == "sell":
		return
	_round_money[id] += delta
	if _instant:
		return
	var v: TankView = _tank_views[id]
	var col: Color = NeonPalette.WARN if delta >= 0 else NeonPalette.BAD
	_pop(HudFormat.money_delta(delta), col, v.position + Vector2(0, -78.0 * TankView.VISUAL_SCALE))


func _pop(text: String, color: Color, at: Vector2) -> void:
	# Several popups on one tank in the same moment fan out vertically so they stay readable.
	var lift: float = float(_popup_slot % 3) * 30.0
	_popup_slot += 1
	_popups[_popup_next].pop(text, color, at + Vector2(0, -lift))
	_popup_next = (_popup_next + 1) % _popups.size()


func _on_shield_hit(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	v.shield_hit(e["hp"])
	if not _instant:
		_pop("-%d" % int(e["absorbed"]), NeonPalette.CYAN, v.position + Vector2(0, -52.0 * TankView.VISUAL_SCALE))
		_haptic(20)


func _on_repair(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	v.set_health(e["health"], SimConstants.MAX_HEALTH)
	if _instant:
		return
	v.repair_burst()
	_pop("+%d" % int(e["amount"]), NeonPalette.GOOD, v.position + Vector2(0, -52.0 * TankView.VISUAL_SCALE))


func _on_chute(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	if _instant:
		return
	v.show_chute()
	# The canopy slows the fall: restart the running fall tween more gently.
	if _tank_tweens.has(id):
		var entry: Dictionary = _tank_tweens[id]
		var tw: Tween = entry["tween"]
		if tw.is_valid():
			tw.kill()
		var to: Vector2 = entry["end"]
		var slow: Tween = create_tween()
		slow.set_speed_scale(_speed)
		slow.tween_property(v, "position", to, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tank_tweens[id] = {"tween": slow, "end": to}


func _on_tank_fall(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	_finish_tank_tween(id)
	var to := Vector2(v.position.x, float(e["to_y"]))
	if _slide_ground.has(id) and not _more_falls_follow(id):
		# The last fall after a walk or drag: the tank rests on the ground it was moved onto.
		to = _slide_ground[id] as Vector2
		_slide_ground.erase(id)
	if _instant:
		v.position = to
		return
	var tw: Tween = create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_property(v, "position", to, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tank_tweens[id] = {"tween": tw, "end": to}


## tank_move / tank_drag: the tank slides along the surface to its new column.
func _on_tank_slide(e: Dictionary) -> void:
	var id: int = e["tank"]
	var v: TankView = _tank_views[id]
	var from_x: int = e["from_x"]
	var to_x: int = e["to_x"]
	_finish_tank_tween(id)
	if from_x == to_x:
		return
	var max_step: float = 6.0 if e["type"] == "tank_drag" else float(SimConstants.MAX_CLIMB)
	var ys: PackedFloat32Array = _slide_heights(v.position.y, from_x, to_x, max_step)
	var final := Vector2(float(to_x), ys[ys.size() - 1])
	# Where the tank really ends up: the ground under its new column (the core sets y to the
	# resting height at every step). The falls that follow a long drop may end higher.
	_slide_ground[id] = Vector2(float(to_x), float(TankState.rest_y(display_terrain, to_x)))
	if _instant:
		v.position = final
		return
	var dur: float = clampf(float(absi(to_x - from_x)) / 320.0, 0.06, 0.2)
	var tw: Tween = create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_method(_set_slide_pos.bind(v, from_x, to_x, ys), 0.0, 1.0, dur)
	_tank_tweens[id] = {"tween": tw, "end": final}


## True if another tank_fall of tank `id` comes later in the running timeline.
func _more_falls_follow(id: int) -> bool:
	for i: int in range(_ev_i + 1, _events.size()):
		if _events[i]["type"] == "tank_fall" and _events[i]["tank"] == id:
			return true
	return false


## Ground height under the tank at every column from `from_x` to `to_x` (inclusive), never
## changing by more than `max_step` per column: bigger drops are shown by the tank_fall that
## follows.
func _slide_heights(start_y: float, from_x: int, to_x: int, max_step: float) -> PackedFloat32Array:
	var ys := PackedFloat32Array()
	ys.append(start_y)
	var dir: int = signi(to_x - from_x)
	var y: float = start_y
	var x: int = from_x
	while x != to_x:
		x += dir
		var ground: float = float(TankState.rest_y(display_terrain, x))
		y = clampf(ground, y - max_step, y + max_step)
		ys.append(y)
	return ys


func _set_slide_pos(k: float, v: TankView, from_x: int, to_x: int, ys: PackedFloat32Array) -> void:
	var steps: int = ys.size() - 1
	var f: float = k * float(steps)
	var i: int = clampi(int(f), 0, steps)
	var j: int = mini(i + 1, steps)
	v.position = Vector2(lerpf(float(from_x), float(to_x), k), lerpf(ys[i], ys[j], f - float(i)))


## Completes a running slide/fall at once (a later event continues from its end point).
func _finish_tank_tween(id: int) -> void:
	if not _tank_tweens.has(id):
		return
	var entry: Dictionary = _tank_tweens[id]
	var tw: Tween = entry["tween"]
	if tw.is_valid():
		tw.kill()
	_tank_views[id].position = entry["end"] as Vector2
	_tank_tweens.erase(id)


func _on_tank_destroyed(e: Dictionary) -> void:
	var v: TankView = _tank_views[e["tank"]]
	v.set_dead(true)
	if _instant:
		return
	_next_fx().play(v.position + Vector2(0, -TankView.TANK_H * TankView.VISUAL_SCALE * 0.5), 58.0)
	_camera.shake(0.7)
	_haptic(160)


func _next_fx() -> Explosion:
	var e: Explosion = _fx[_fx_next]
	_fx_next = (_fx_next + 1) % _fx.size()
	return e


func _haptic(ms: int) -> void:
	if ShowSettings.haptics and not _instant:
		Input.vibrate_handheld(ms)


# ======================================================================================
# HUD occlusion, "you" marker, off-screen shell marker
# ======================================================================================

## Every frame: tells the HUD which screen rectangles have action behind them (it fades the
## panels over them), draws the "you" arrow when the active tank sits under a panel and shows
## a chevron for each shell above the top of the screen.
func _update_overlays() -> void:
	var live: bool = _hud.visible and _world.visible and state.terrain != null
	if not live:
		_hud.set_occluders([] as Array[Rect2])
		_markers.set_you(false)
		_markers.set_shells([] as Array[Dictionary])
		return
	var xf: Transform2D = get_viewport().get_canvas_transform()
	var rects: Array[Rect2] = []
	var segments := PackedVector2Array()
	for t: TankState in state.tanks:
		if t.alive:
			rects.append(xf * _tank_rect(_tank_views[t.id]))
	var chevrons: Array[Dictionary] = []
	for entry: Variant in _shells.values():
		var head: Vector2 = ((entry as Dictionary)["trail"] as ShellTrail).head_position()
		rects.append(xf * Rect2(head - Vector2.ONE * 24.0, Vector2.ONE * 48.0))
		var sp: Vector2 = xf * head
		if sp.y < 0.0:
			chevrons.append({"x": sp.x, "height": maxi(1, roundi(-sp.y / maxf(xf.get_scale().y, 0.001))),
					"color": _shooter_color()})
	for fx: Explosion in _fx:
		_add_rect(rects, xf, fx.get_world_rect())
	for f: FlameField in _flames:
		_add_rect(rects, xf, f.get_world_rect())
	for p: PullRings in _pulls:
		_add_rect(rects, xf, p.get_world_rect())
	for b: BeamFx in _beams:
		if b.is_active():
			var ends: PackedVector2Array = b.get_endpoints()
			segments.append(xf * ends[0])
			segments.append(xf * ends[1])
	_hud.set_occluders(rects, segments)
	_markers.set_shells(chevrons)
	_update_you_marker(xf)


static func _add_rect(rects: Array[Rect2], xf: Transform2D, r: Rect2) -> void:
	if r.size != Vector2.ZERO:
		rects.append(xf * r)


## The tank's footprint for the fade: ground point, hull, emblem and health bar.
static func _tank_rect(v: TankView) -> Rect2:
	return Rect2(v.position + TANK_FADE_RECT.position, TANK_FADE_RECT.size)


func _update_you_marker(xf: Transform2D) -> void:
	if state.phase != SimConstants.PHASE_AIM or _turn_tank < 0 or _turn_tank >= _tank_views.size() \
			or not state.tanks[_turn_tank].alive:
		_markers.set_you(false)
		return
	var v: TankView = _tank_views[_turn_tank]
	if _hud.is_under_panel(xf * _tank_rect(v)):
		_markers.set_you(true, xf * (v.position + Vector2(0.0, YOU_TIP_Y)), PlayerLooks.color(_turn_tank))
	else:
		_markers.set_you(false)


func get_markers() -> BattleMarkers:
	return _markers


# ======================================================================================
# Round summary, match over
# ======================================================================================

func _sync_round_wins() -> void:
	round_wins.resize(state.tanks.size())
	for t: TankState in state.tanks:
		round_wins[t.id] = t.round_wins


func _summary_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for t: TankState in state.tanks:
		rows.append({"id": t.id, "earned": _round_money[t.id], "kills": t.kills, "wins": t.round_wins,
				"money": t.money, "damage": t.damage_dealt})
	return rows


func _show_round_summary() -> void:
	_set_busy(true)
	_hud.visible = true
	_world.visible = state.terrain != null
	_round_overlay.show_summary(_round_winner_for_summary(), _summary_rows(), state.round_index + 1, state.settings.rounds)


## After a restore the winner is not remembered; it is the tank with the most round wins that
## is alive (a draw shows no winner).
func _round_winner_for_summary() -> int:
	if _round_winner >= 0 or _round_ended:
		return _round_winner
	var alive: int = -1
	for t: TankState in state.tanks:
		if t.alive:
			if alive >= 0:
				return -1
			alive = t.id
	return alive


func _show_match_over() -> void:
	_set_busy(true)
	_hud.visible = true
	_world.visible = state.terrain != null
	_summary_pending = false
	_save_dirty = false
	if _autosave_path != "":
		SaveStore.delete(_autosave_path)  # nothing to continue
	var rows: Array[Dictionary] = _summary_rows()
	_match_overlay.show_standings(Simulation.standings(state), rows)


# ======================================================================================
# Autosave
# ======================================================================================

func _make_meta() -> Dictionary:
	var money: Array = []
	for v: int in _round_money:
		money.append(v)
	return {"looks": PlayerLooks.to_dict(state.tanks.size()), "round_money": money,
			"summary_pending": _summary_pending}


## Writes the autosave now. Returns true when a file was written. Does nothing without an
## autosave path, and deletes the file once the match is over.
func autosave_now() -> bool:
	_save_dirty = false
	_save_cooldown = SAVE_DEBOUNCE
	if _autosave_path == "" or state == null:
		return false
	if state.phase == SimConstants.PHASE_MATCH_OVER:
		SaveStore.delete(_autosave_path)
		return false
	session.meta = _make_meta()
	var ok: bool = session.save(_autosave_path)
	if ok:
		_saves_done += 1
	return ok


## Saves after a change once the playback is idle (and at most every SAVE_DEBOUNCE seconds),
## so a burst of shop taps or a long animation never stutters on disk writes.
func _tick_autosave(delta: float) -> void:
	_save_cooldown = maxf(0.0, _save_cooldown - delta)
	if _save_dirty and not _playing and _save_cooldown <= 0.0:
		autosave_now()


# ======================================================================================
# UI glue
# ======================================================================================

## `quiet` = a short, harmless timeline (walking): block input but do not dim the controls,
## so holding a move button does not flicker the HUD.
func _set_busy(b: bool, quiet: bool = false) -> void:
	_busy = b
	_hud.set_fire_enabled(not b)
	if not quiet:
		_hud.set_controls_locked(b)


func _close_overlays() -> void:
	_round_overlay.close()
	_match_overlay.close()


func _show_toast(text: String) -> void:
	_toast.show_message(text)
	toast_shown.emit(text)


func _request_preview() -> void:
	if state == null or _preview == null:
		return
	var id: int = state.current_tank
	if _busy or state.phase != SimConstants.PHASE_AIM or ShowSettings.trajectory_preview == ShowSettings.PREVIEW_OFF:
		_preview.hide_preview()
		return
	_preview.request(state, id, _aim_angle[id], _aim_power[id])


func _on_hud_angle(a: int) -> void:
	if _busy:
		return
	var id: int = state.current_tank
	_aim_angle[id] = a
	_tank_views[id].set_angle_tenths(a)
	_request_preview()


func _on_hud_power(p: int) -> void:
	if _busy:
		return
	_aim_power[state.current_tank] = p
	_request_preview()


# ======================================================================================
# Debug / screenshot hooks (ShotArgs)
# ======================================================================================

## One-shot hooks that need the round to be running (item use, picker).
func _run_start_hooks() -> void:
	if _hooks_done or _configured:
		return
	_hooks_done = true
	_apply_screenshot_setup()
	if ShotArgs.use_item != "":
		use_item(ShotArgs.use_item)
	if ShotArgs.open_picker:
		open_weapon_picker()
	if ShotArgs.open_settings:
		open_pause()
		_open_settings_from_pause()
	if ShotArgs.open_diag:
		open_diagnostics()


## --place / --aim: arranges the first turn for a screenshot (tank positions and aim).
func _apply_screenshot_setup() -> void:
	var moved: bool = false
	for spec: String in ShotArgs.places:
		var parts: PackedStringArray = spec.split(":")
		if parts.size() != 2:
			continue
		var i: int = parts[0].to_int()
		var x: int = parts[1].to_int()
		if i < 0 or i >= state.tanks.size() or x < 12 or x > state.terrain.width - 12:
			continue
		state.tanks[i].x = x
		state.tanks[i].y = TankState.rest_y(state.terrain, x)
		moved = true
	if moved:
		_rebuild_display()
	_apply_initial_aim_override()
	_begin_turn_ui()


func _run_auto_hooks(delta: float) -> void:
	if _configured:
		return
	if state.phase == SimConstants.PHASE_SHOP and not _playing:
		_auto_shop(delta)
		return
	if _busy or is_paused():
		return
	if state.phase != SimConstants.PHASE_AIM:
		return
	_auto_timer -= delta
	if _auto_timer > 0.0:
		return
	if ShotArgs.auto_play:
		var id: int = state.current_tank
		var shot: Vector2i = AutoShot.find_shot(state, id)
		set_aim(shot.x, shot.y)
		fire_current()
		_auto_timer = 0.5
	elif ShotArgs.open_pause and _elapsed > 0.5 and not is_paused():
		ShotArgs.open_pause = false
		open_pause()
	elif _auto_fire_pending:
		_auto_fire_pending = false
		fire_current()


## --auto-play / --skip-shop: press NEXT on the summary and READY for everyone.
func _auto_shop(delta: float) -> void:
	if not (ShotArgs.auto_play or ShotArgs.skip_shop):
		return
	_auto_timer -= delta
	if _auto_timer > 0.0:
		return
	_auto_timer = 0.6
	if _round_overlay.visible:
		if ShotArgs.auto_play and ShotArgs.auto_next:
			next_round()
		return
	if _match_overlay.visible:
		return
	quick_start()
