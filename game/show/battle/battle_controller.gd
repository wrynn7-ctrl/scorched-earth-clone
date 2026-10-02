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
const FX_POOL: int = 3
const FLAME_POOL: int = 2
const BEAM_POOL: int = 2
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
var _wells: Dictionary = {}
var _preview: TrajectoryPreview = null
var _toast: Toast = null
var _shop: ShopFlow = null
var _pause_overlay: PauseOverlay = null
var _settings_overlay: SettingsOverlay = null
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
var _needs_snap: bool = false

# --- autosave ---
var _save_dirty: bool = false
var _save_cooldown: float = 0.0
var _saves_done: int = 0

# --- debug hooks (ShotArgs) ---
var _elapsed: float = 0.0
var _auto_timer: float = 0.0
var _auto_fire_pending: bool = false
var _hooks_done: bool = false


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
	_hud.speed_pressed.connect(toggle_speed)
	_hud.weapon_picker_requested.connect(open_weapon_picker)
	_hud.weapon_selected.connect(func(id: String) -> void: select_weapon(id))
	_hud.item_pressed.connect(func(id: String) -> void: use_item(id))
	_hud.move_pressed.connect(func(dir: int) -> void: move_current(dir))
	_hud.set_speed(_speed)
	get_viewport().size_changed.connect(_frame_camera)
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
			if _settings_overlay != null and _settings_overlay.visible:
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
	for i: int in range(POPUP_POOL):
		var p := DamagePopup.new()
		p.name = "Popup%d" % i
		_world.add_child(p)
		_popups.append(p)
	_toast = Toast.new()
	_toast.name = "Toast"
	_hud.get_parent().add_child(_toast)
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
	_needs_snap = false


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
		_show_toast(tr("ERR_" + err.to_upper()))
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
	_ev_i = 0
	_playhead = 0.0
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
		last = maxi(last, _present[i])
		var type: String = events[i]["type"]
		if type == "explosion" or type == "round_end" or type == "beam" or type == "flames" or type == "tunnel":
			impact = true
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
	_ev_i = 0
	_clear_shells()
	_cancel_tank_tweens()


func _cancel_tank_tweens() -> void:
	for entry: Variant in _tank_tweens.values():
		var tw: Tween = (entry as Dictionary)["tween"]
		if tw.is_valid():
			tw.kill()
	_tank_tweens.clear()


## Presentation tick of every event (see class comment). Monotone, so events always play in
## order even when a later one has an earlier base tick.
func _compute_present(events: Array[Dictionary]) -> PackedInt32Array:
	var out := PackedInt32Array()
	var prev: int = 0
	for e: Dictionary in events:
		var t: int = e["tick"]
		var p: int = t
		match e["type"]:
			"terrain_settle", "tank_fall", "tank_destroyed", "chute":
				p = t + SETTLE_DELAY
			"damage":
				p = t + (SETTLE_DELAY if e["cause"] == "fall" else 0)
			"wind", "turn", "round_end", "well_off":
				p = t + (POST_DELAY if t > 0 else 0)
			"money":
				p = prev  # shown together with the damage / kill / round pay it belongs to
		prev = maxi(prev, p)
		out.append(prev)
	return out


func _process(delta: float) -> void:
	_elapsed += delta
	if state == null:
		return
	if state.phase == SimConstants.PHASE_AIM:
		var t: TankView = _tank_views[state.current_tank]
		_hud.set_aim_pivot(get_viewport().get_canvas_transform() * (t.position + Vector2(0, -TankView.TANK_H * 0.5) * TankView.VISUAL_SCALE))
		_sky.set_parallax(_camera.get_screen_center_position())
	if _playing:
		_playhead += delta * TPS * _speed
		_advance_playback()
	_tick_autosave(delta)
	_run_auto_hooks(delta)


func _advance_playback() -> void:
	while _ev_i < _events.size() and float(_present[_ev_i]) <= _playhead:
		_dispatch(_events[_ev_i])
		_ev_i += 1
	for entry: Variant in _shells.values():
		var sh: Dictionary = entry
		(sh["trail"] as ShellTrail).set_progress(clampf(_playhead - float(sh["start"]) - 1.0, 0.0, float((sh["points"] as int) - 1)))
	if _playhead >= _end_tick and _ev_i >= _events.size():
		_finish_playback()


func _finish_playback() -> void:
	_playing = false
	_clear_shells()
	if _needs_snap:
		_snap_display_to_state()  # M3-C2: a terrain function was missing; resync quietly
	else:
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
	match e["type"]:
		"round_start":
			_rebuild_display()
		"projectile":
			_start_shell(e)
		"projectile_end":
			_end_shell(e["id"] as int)
		"explosion":
			_on_explosion(e)
		"terrain_carve":
			display_terrain.carve_circle(e["x"], e["y"], e["radius"])
			_terrain_view.update_cells(display_terrain.cells)
		"terrain_settle":
			display_terrain.settle(e["x0"], e["x1"])
			_terrain_view.update_cells(display_terrain.cells)
		"tunnel":
			_on_tunnel(e)
		"terrain_add":
			_on_terrain_add(e)
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
			_ensure_selection(id)
			_hud.show_turn(id)
			_hud.set_angle_tenths(_aim_angle[id])
			_hud.set_power(_aim_power[id])
			_refresh_loadout(id)
		"round_end":
			_round_ended = true
			_round_winner = e["winner"]
		# "fire" and "ready" have no presentation of their own; the shell appears with "projectile".


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


## Starts one projectile (id 0 is the main shell; splitter children start at their own tick).
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
	_shells[e["id"] as int] = {"trail": trail, "start": e["tick"] as int, "points": pts.size()}


func _end_shell(id: int) -> void:
	if _shells.has(id):
		((_shells[id] as Dictionary)["trail"] as ShellTrail).clear()
		_shells.erase(id)


func _clear_shells() -> void:
	for t: ShellTrail in _trail_pool:
		t.clear()
	_shells.clear()


# --- explosions, terrain -----------------------------------------------------------------

func _on_explosion(e: Dictionary) -> void:
	if _instant:
		return
	var radius: float = float(e["radius"])
	_next_fx().play(Vector2(float(e["x"]), float(e["y"])), radius)
	_camera.shake(clampf(radius * SHAKE_PER_RADIUS, 0.15, 0.9))
	_haptic(clampi(roundi(radius * 2.0), 15, 90))


func _on_tunnel(e: Dictionary) -> void:
	# M3-C2: Terrain.carve_tunnel may not exist yet; without it the display is snapped to the state after playback.
	if display_terrain.has_method("carve_tunnel"):
		display_terrain.call("carve_tunnel", e["x0"], e["y0"], e["x1"], e["y1"], e["radius"])
		_terrain_view.update_cells(display_terrain.cells)
	else:
		_needs_snap = true


func _on_terrain_add(e: Dictionary) -> void:
	# M3-C2: Terrain.add_circle_skipping may not exist yet (see _on_tunnel).
	if display_terrain.has_method("add_circle_skipping"):
		display_terrain.call("add_circle_skipping", e["x"], e["y"], e["radius"], e["material"],
				e.get("skip", PackedInt32Array()))
		_terrain_view.update_cells(display_terrain.cells)
	else:
		_needs_snap = true


func _on_terrain_pour(e: Dictionary) -> void:
	# M3-C2: Terrain.pour may not exist yet (see _on_tunnel).
	if display_terrain.has_method("pour"):
		display_terrain.call("pour", e["cells"], e["material"])
		_terrain_view.update_cells(display_terrain.cells)
	else:
		_needs_snap = true


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
	_tank_views[id].set_health(e["health"], SimConstants.MAX_HEALTH)
	if not _instant:
		var v: TankView = _tank_views[id]
		_pop("-%d" % int(e["amount"]), PlayerLooks.color(id), v.position + Vector2(0, -52.0 * TankView.VISUAL_SCALE))


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
	if _instant:
		v.position = final
		return
	var dur: float = clampf(float(absi(to_x - from_x)) / 320.0, 0.06, 0.2)
	var tw: Tween = create_tween()
	tw.set_speed_scale(_speed)
	tw.tween_method(_set_slide_pos.bind(v, from_x, to_x, ys), 0.0, 1.0, dur)
	_tank_tweens[id] = {"tween": tw, "end": final}


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
	if ShotArgs.use_item != "":
		use_item(ShotArgs.use_item)
	if ShotArgs.open_picker:
		open_weapon_picker()
	if ShotArgs.open_settings:
		open_pause()
		_open_settings_from_pause()


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
