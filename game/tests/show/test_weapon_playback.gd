extends GutTest
## Every weapon in the catalog is fired in a seeded battle and played back; the presentation
## must follow the event stream exactly: the consistency check never has to snap (resync) the
## display. Instant mode covers all 21 weapons from several aims; a handful also run in real
## time (shells, trails and staggered effects).

const BATTLE: String = "res://show/battle/battle_scene.tscn"
const SEED: int = 4242
## Event types each weapon must put in its timeline (a sanity check on the scenario itself).
const SIGNATURE: Dictionary = {
	"prism_splitter": "projectile_end",
	"prism_cascade": "projectile_end",
	"bore_shell": "tunnel",
	"deep_bore": "tunnel",
	"mound_mortar": "terrain_add",
	"landslide": "terrain_add",
	"sludge_shell": "terrain_pour",
	"ember_rain": "flames",
	"inferno_gel": "flames",
	"photon_lance": "beam",
	"singularity_seed": "well_on",
}
const REAL_TIME: Array[String] = [
	"prism_splitter", "glide_orb", "bore_shell", "mound_mortar", "sludge_shell", "ember_rain", "seeker",
	"photon_lance", "static_burst", "singularity_seed", "riptide_anchor", "supernova",
]


func after_each() -> void:
	ShowSettings.reset()
	UiScale.reset_overrides()
	BattleConfig.reset()
	PlayerLooks.reset()


static func weapon_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in Catalog.IDS:
		if WeaponDefs.has(id):
			out.append(id)
	return out


## A running round with `players` tanks, `weapon` in tank 0's hands.
func _round(weapon: String, instant: bool, players: int = 2) -> BattleController:
	var c: BattleController = (load(BATTLE) as PackedScene).instantiate()
	c.configure(3, SEED, instant, players)
	add_child_autofree(c)
	assert_true(c.quick_start())
	c.get_state().tanks[0].set_stock(weapon, 9)
	if not instant:
		c.set_speed(6.0)
	return c


## The aims tried for every weapon: a shot at the nearest enemy, a short lob and a steep one.
func _aims(c: BattleController) -> Array[Vector2i]:
	var hit: Vector2i = AutoShot.find_shot(c.get_state(), 0)
	var right: bool = c.get_state().tanks[1].x >= c.get_state().tanks[0].x
	var flip: int = 0 if right else SimConstants.MAX_ANGLE
	var sign: int = 1 if right else -1
	return [
		hit,
		Vector2i(clampi(hit.x, 0, SimConstants.MAX_ANGLE), clampi(hit.y * 6 / 10, 40, SimConstants.MAX_POWER)),
		Vector2i(flip + sign * 750, 520),
		Vector2i(flip + sign * 250, 640),
	]


func _event_types(c: BattleController) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in c.get("_events") as Array[Dictionary]:
		out.append(e["type"] as String)
	return out


func _check_path_convention(c: BattleController, weapon: String) -> void:
	var events: Array[Dictionary] = c.get("_events") as Array[Dictionary]
	var ends: Dictionary = {}
	for e: Dictionary in events:
		if e["type"] == "projectile_end":
			ends[e["id"]] = e
	for e: Dictionary in events:
		if e["type"] != "projectile":
			continue
		var path: PackedInt32Array = e["path"]
		var end: Dictionary = ends[e["id"]]
		assert_eq(end["tick"], (e["tick"] as int) + path.size() / 2,
				"%s shell %d: path[i] is at tick start + i + 1, so the end is start + len" % [weapon, e["id"]])
		var last := Vector2i(path[path.size() - 2] / FixedMath.ONE, path[path.size() - 1] / FixedMath.ONE)
		if end["reason"] != "split" and end["reason"] != "apex":
			assert_lte(absi(last.x - (end["x"] as int)) + absi(last.y - (end["y"] as int)), 2,
					"%s shell %d ends where its path ends" % [weapon, e["id"]])


func test_all_21_weapons_are_covered() -> void:
	assert_eq(weapon_ids().size(), 21)


func test_no_weapon_needs_a_resync_in_instant_mode() -> void:
	for weapon: String in weapon_ids():
		var probe: BattleController = _round(weapon, true)
		var aims: Array[Vector2i] = _aims(probe)
		probe.queue_free()
		await wait_process_frames(1)
		for aim: Vector2i in aims:
			var c: BattleController = _round(weapon, true)
			assert_eq(c.select_weapon(weapon), "", "%s can be selected" % weapon)
			c.set_aim(aim.x, aim.y)
			var err: String = c.fire_current()
			assert_eq(err, "", "%s fires" % weapon)
			assert_eq(c.mismatch_count, 0, "%s from aim %s needed no resync" % [weapon, aim])
			_check_path_convention(c, weapon)
			c.queue_free()
			await wait_process_frames(1)


func test_weapon_signature_events_do_occur() -> void:
	var seen: Dictionary = {}
	for weapon: String in SIGNATURE.keys():
		for aim: Vector2i in _aims(_round(weapon, true)):
			var c: BattleController = _round(weapon, true)
			c.select_weapon(weapon)
			c.set_aim(aim.x, aim.y)
			c.fire_current()
			if _event_types(c).has(SIGNATURE[weapon] as String):
				seen[weapon] = true
			c.queue_free()
			await wait_process_frames(1)
		assert_true(seen.has(weapon), "%s produced a %s event from at least one aim" % [weapon, SIGNATURE[weapon]])


func test_real_time_playback_needs_no_resync() -> void:
	for weapon: String in REAL_TIME:
		var aims: Array[Vector2i] = _aims(_round(weapon, false))
		var c: BattleController = _round(weapon, false)
		await wait_until(func() -> bool: return not c.is_busy(), 15.0, 0.1)
		c.select_weapon(weapon)
		c.set_aim(aims[0].x, aims[0].y)
		assert_eq(c.fire_current(), "", "%s fires" % weapon)
		# A kill ends the round (the summary keeps the controller busy), so wait on the playback itself.
		await wait_until(func() -> bool: return not (c.get("_playing") as bool), 40.0, 0.1)
		assert_false(c.get("_playing"), "%s playback finished" % weapon)
		assert_eq(c.mismatch_count, 0, "%s: real-time playback needed no resync" % weapon)
		_check_path_convention(c, weapon)
		c.queue_free()
		await wait_process_frames(1)


func test_a_second_well_by_the_same_owner_replaces_the_first_in_real_time() -> void:
	var c: BattleController = _round("singularity_seed", false, 3)
	await wait_until(func() -> bool: return not c.is_busy(), 15.0, 0.1)
	for shot: int in range(2):
		assert_eq(c.get_state().current_tank, 0)
		c.select_weapon("singularity_seed")
		var aim: Vector2i = AutoShot.find_shot(c.get_state(), 0)
		c.set_aim(aim.x, aim.y + shot * 40)
		assert_eq(c.fire_current(), "")
		await wait_until(func() -> bool: return not (c.get("_playing") as bool), 40.0, 0.1)
		assert_eq(c.get_state().wells.size(), 1, "one well per owner")
		assert_not_null(c.get_well_view(0))
		# The other tanks pass; tank 0 is up again.
		var guard: int = 0
		while c.get_state().current_tank != 0 and guard < 4:
			assert_eq(c.pass_turn(), "")
			await wait_until(func() -> bool: return not (c.get("_playing") as bool), 20.0, 0.1)
			guard += 1
	assert_eq(c.mismatch_count, 0, "the replaced well went off together with the new one, not after it")
	assert_eq(c.get_state().wells.size(), 1)
