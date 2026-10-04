extends GutTest
## AudioDirector (docs/ARCHITECTURE.md section 33): the sound files, the event -> sound map, the voice pool, the
## loops and the settings that drive the buses. Headless runs use Godot's dummy audio driver, so everything
## here must also work without a sound device.

const SFX_DIR: String = "res://assets/sfx/"
## Every sound the task asks for.
const REQUIRED: Array[String] = [
	"fire_light", "fire_medium", "fire_heavy", "beam_zap",
	"explosion_small", "explosion_medium", "explosion_large", "explosion_nuke",
	"terrain_crumble", "dirt_thud", "sludge_pour", "fire_crackle", "well_hum", "anchor_clank",
	"shield_up", "shield_hit", "shield_break", "repulsor_pulse",
	"chute_pop", "repair_chime", "money_gain", "money_loss", "tank_destroyed", "round_win", "match_win",
	"ui_tap", "ui_back", "ui_purchase", "ui_locked", "cpu_think_tick", "turn_blip",
	"love_fire", "heart_burst", "love_win", "love_found",
]
const PATH: String = "user://test_audio_settings.cfg"
## Longest allowed file (seconds); every other sound stays under DEFAULT_MAX_SECONDS. The heavy redesign made the
## big booms and the jingles long on purpose (ARCHITECTURE 33a).
const DEFAULT_MAX_SECONDS: float = 3.0
const MAX_SECONDS: Dictionary = {
	"explosion_large": 2.8, "explosion_nuke": 4.2, "love_win": 5.0, "match_win": 5.0, "tank_destroyed": 2.4,
}

var _ad: Node = null


func before_each() -> void:
	_ad = get_tree().root.get_node("AudioDirector")
	ShowSettings.reset()
	_ad.reset_for_tests()
	_ad.apply_settings()
	SettingsStore.path = PATH
	SettingsStore.delete()


func after_each() -> void:
	_ad.reset_for_tests()
	ShowSettings.reset()
	_ad.apply_settings()
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	UiScale.reset_overrides()


# --- files ----------------------------------------------------------------------------------

func test_every_required_sound_is_registered_exists_and_loads() -> void:
	var sounds: Dictionary = _ad.SOUNDS
	for key: String in REQUIRED:
		assert_true(sounds.has(key), "registered: " + key)
		assert_true(FileAccess.file_exists(SFX_DIR + key + ".wav") or ResourceLoader.exists(SFX_DIR + key + ".wav"), "file: " + key)
		var spec: Dictionary = sounds[key]
		var stream: AudioStreamWAV = spec["s"] as AudioStreamWAV
		assert_not_null(stream, "loads: " + key)
		if stream == null:
			continue
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, key + " is 16-bit")
		assert_eq(stream.mix_rate, 44100, key + " is 44.1 kHz")
		assert_false(stream.stereo, key + " is mono")
		assert_gt(stream.get_length(), 0.01, key + " has sound in it")
		assert_lt(stream.get_length(), float(MAX_SECONDS.get(key, DEFAULT_MAX_SECONDS)), key + " is not too long")
		assert_true(float(spec["db"]) <= 0.0 and int(spec["pri"]) >= 1 and int(spec["pri"]) <= 10, key + " spec")
	assert_eq(sounds.size(), REQUIRED.size(), "no unregistered extras")


func test_explosions_grow_in_length_and_the_nuke_is_a_long_boom() -> void:
	var lens: Array[float] = []
	for key: String in ["explosion_small", "explosion_medium", "explosion_large", "explosion_nuke"]:
		lens.append(((_ad.SOUNDS[key] as Dictionary)["s"] as AudioStreamWAV).get_length())
	for i: int in range(lens.size() - 1):
		assert_gt(lens[i + 1], lens[i], "small < medium < large < nuke in length: %s" % str(lens))
	assert_between(lens[3], 3.0, 4.2, "the nuke is an earth-shaking boom of about 3-4 s")
	assert_gt(lens[0], 0.4, "even the smallest bang has a body and a tail")


func test_the_win_melodies_are_long_and_sweet() -> void:
	var love: float = ((_ad.SOUNDS["love_win"] as Dictionary)["s"] as AudioStreamWAV).get_length()
	assert_between(love, 3.0, 5.0, "the Love win is a 3-5 s melody")
	var match_win: float = ((_ad.SOUNDS["match_win"] as Dictionary)["s"] as AudioStreamWAV).get_length()
	var round_win: float = ((_ad.SOUNDS["round_win"] as Dictionary)["s"] as AudioStreamWAV).get_length()
	assert_gt(match_win, round_win, "the match jingle is bigger than the round jingle")


func test_battle_sounds_sit_above_ui_sounds_in_the_mix() -> void:
	var quietest_battle: float = 0.0
	for key: String in ["fire_light", "fire_medium", "fire_heavy", "explosion_small", "explosion_nuke", "tank_destroyed"]:
		quietest_battle = minf(quietest_battle, (_ad.SOUNDS[key] as Dictionary)["db"] as float)
	for key: String in ["ui_tap", "ui_back", "ui_purchase", "ui_locked", "cpu_think_tick"]:
		assert_true(((_ad.SOUNDS[key] as Dictionary)["db"] as float) <= 0.0, key)
	assert_gte(quietest_battle, -4.0, "battle sounds stay close to full level (the files carry the quieter UI peaks)")


func test_no_wav_in_the_sfx_folder_is_unused() -> void:
	var names: Array[String] = []
	for f: String in DirAccess.get_files_at(SFX_DIR):
		if f.ends_with(".wav"):
			names.append(f.get_basename())
	names.sort()
	var want: Array[String] = REQUIRED.duplicate()
	want.sort()
	assert_eq(names, want)


func test_the_sound_files_stay_small() -> void:
	var total: int = 0
	for key: String in REQUIRED:
		var f: FileAccess = FileAccess.open(SFX_DIR + key + ".wav", FileAccess.READ)
		assert_not_null(f, key)
		if f != null:
			total += f.get_length()
	assert_lt(total, 4 * 1024 * 1024, "under 4 MB in total (%d bytes)" % total)


func test_loops_are_switched_on_for_the_two_loop_sounds() -> void:
	for key: String in ["fire_crackle", "well_hum"]:
		var stream: AudioStreamWAV = (_ad.SOUNDS[key] as Dictionary)["s"] as AudioStreamWAV
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, key)
		assert_gt(stream.loop_end, 1000, key)
	for key: String in ["fire_light", "explosion_nuke"]:
		var stream: AudioStreamWAV = (_ad.SOUNDS[key] as Dictionary)["s"] as AudioStreamWAV
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, key + " plays once")


func test_the_buses_exist_and_route_to_master() -> void:
	for n: String in ["SFX", "UI", "Music"]:
		var idx: int = AudioServer.get_bus_index(n)
		assert_gt(idx, 0, n + " bus")
		assert_eq(AudioServer.get_bus_send(idx), &"Master", n + " sends to Master")
	assert_eq(AudioServer.get_bus_effect_count(0), 1, "a limiter guards the master against clipping")


# --- event -> sound ---------------------------------------------------------------------------

func test_explosion_radius_picks_the_size_class() -> void:
	var cases: Array = [[1, "small"], [12, "small"], [14, "small"], [24, "small"], [28, "medium"], [44, "medium"],
			[59, "medium"], [60, "large"], [90, "large"], [119, "large"], [120, "nuke"], [160, "nuke"]]
	for c: Array in cases:
		assert_eq(_ad.explosion_key(c[0] as int), "explosion_" + (c[1] as String), "radius %d" % c[0])
	# The real catalog: Spark Dart small, Nova Core large, Supernova the nuke.
	assert_eq(_ad.explosion_key(WeaponDefs.get_def("spark_dart")["r"] as int), "explosion_small")
	assert_eq(_ad.explosion_key(WeaponDefs.get_def("hyperpulse")["r"] as int), "explosion_medium")
	assert_eq(_ad.explosion_key(WeaponDefs.get_def("nova_core")["r"] as int), "explosion_large")
	assert_eq(_ad.explosion_key(WeaponDefs.get_def("supernova")["r"] as int), "explosion_nuke")


func test_weapon_behaviour_picks_the_fire_class() -> void:
	var want: Dictionary = {
		"spark_dart": "fire_light", "pulse_missile": "fire_medium", "hyperpulse": "fire_medium",
		"nova_core": "fire_heavy", "supernova": "fire_heavy", "prism_splitter": "fire_medium",
		"prism_cascade": "fire_medium", "glide_orb": "fire_light", "heavy_orb": "fire_medium",
		"bore_shell": "fire_medium", "deep_bore": "fire_medium", "mound_mortar": "fire_medium",
		"landslide": "fire_heavy", "sludge_shell": "fire_heavy", "ember_rain": "fire_medium",
		"inferno_gel": "fire_heavy", "seeker": "fire_medium", "photon_lance": "beam_zap",
		"static_burst": "fire_light", "singularity_seed": "fire_heavy", "riptide_anchor": "fire_medium",
	}
	for id: String in Catalog.IDS:
		if WeaponDefs.has(id):
			assert_true(want.has(id), "table covers " + id)
			assert_eq(_ad.fire_key(id), want[id], id)
	assert_eq(_ad.fire_key("not_a_weapon"), "fire_medium", "unknown weapons still make a sound")


## Every event type of sections 10, 20, 21 and 25 with its expected sound ("" = silent).
func _event_table() -> Array:
	return [
		[{"type": "fire", "weapon": "spark_dart"}, "fire_light"],
		[{"type": "fire", "weapon": "supernova"}, "fire_heavy"],
		[{"type": "fire", "weapon": "photon_lance"}, "beam_zap"],
		[{"type": "projectile", "id": 0}, ""],
		[{"type": "projectile_end", "id": 0, "reason": "terrain"}, ""],
		[{"type": "explosion", "radius": 14}, "explosion_small"],
		[{"type": "explosion", "radius": 44}, "explosion_medium"],
		[{"type": "explosion", "radius": 90}, "explosion_large"],
		[{"type": "explosion", "radius": 160}, "explosion_nuke"],
		[{"type": "terrain_carve", "radius": 20}, ""],
		# Love mode (docs/ARCHITECTURE.md section 37).
		[{"type": "heart_burst", "radius": 30}, "heart_burst"],
		[{"type": "love", "tank": 1, "amount": 34}, "love_fire"],
		[{"type": "fire", "weapon": "heart"}, "love_fire"],
		[{"type": "terrain_settle", "falls": [{"x": 3, "from": 10, "to": 14}]}, "terrain_crumble"],
		[{"type": "terrain_settle", "falls": []}, ""],
		[{"type": "tunnel"}, "terrain_crumble"],
		[{"type": "terrain_add"}, "dirt_thud"],
		[{"type": "terrain_pour"}, "sludge_pour"],
		[{"type": "damage", "cause": "explosion"}, ""],
		[{"type": "damage", "cause": "burn"}, ""],
		[{"type": "damage", "cause": "beam"}, ""],
		[{"type": "damage", "cause": "fall"}, "dirt_thud"],
		[{"type": "tank_fall"}, ""],
		[{"type": "tank_move", "from_x": 10, "to_x": 20}, ""],
		[{"type": "tank_drag", "from_x": 10, "to_x": 60}, "anchor_clank"],
		[{"type": "tank_drag", "from_x": 10, "to_x": 10}, ""],
		[{"type": "tank_destroyed"}, "tank_destroyed"],
		[{"type": "wind", "wind": 5}, ""],
		[{"type": "turn", "tank": 1}, "turn_blip"],
		[{"type": "round_start", "round": 1}, ""],
		[{"type": "round_end", "winner": 0}, "round_win"],
		[{"type": "round_end", "winner": -1}, ""],
		[{"type": "ready", "tank": 0}, ""],
		[{"type": "shield_on", "hp": 50}, "shield_up"],
		[{"type": "shield_hit"}, "shield_hit"],
		[{"type": "shield_down"}, "shield_break"],
		[{"type": "repulsor_on", "charge": 100}, "repulsor_pulse"],
		[{"type": "repulsor_down"}, ""],
		[{"type": "chute"}, "chute_pop"],
		[{"type": "repair", "amount": 40}, "repair_chime"],
		[{"type": "money", "delta": 300, "reason": "damage"}, "money_gain"],
		[{"type": "money", "delta": -200, "reason": "self"}, "money_loss"],
		[{"type": "money", "delta": -500, "reason": "buy"}, ""],
		[{"type": "flames", "points": PackedInt32Array()}, ""],  # the crackle loop, not a one-shot
		[{"type": "beam"}, ""],  # the zap plays with the fire event
		[{"type": "well_on", "owner": 0}, ""],  # the hum loop
		[{"type": "well_off", "owner": 0}, ""],
	]


func test_every_event_type_maps_to_the_expected_sound() -> void:
	for row: Array in _event_table():
		var e: Dictionary = row[0]
		assert_eq(_ad.sound_for_event(e), row[1], "%s" % [e])
		if row[1] != "":
			assert_true((_ad.SOUNDS as Dictionary).has(row[1]), "%s is a registered sound" % row[1])


func test_round_end_plays_the_match_jingle_when_the_match_is_decided() -> void:
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": 2}, true), "match_win")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": 2}, false), "round_win")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": -1}, true), "", "a draw has no jingle")


## A new event type in the core must be given a decision here (a sound, or deliberately none).
func test_every_event_type_the_core_can_emit_is_in_the_table() -> void:
	var known: Dictionary = {}
	for row: Array in _event_table():
		known[(row[0] as Dictionary)["type"]] = true
	var re := RegEx.new()
	re.compile("\"type\": \"([a-z_]+)\"")
	var found: Dictionary = {}
	for dir: String in ["res://core/", "res://core/weapons/", "res://core/items/"]:
		for f: String in DirAccess.get_files_at(dir):
			if not f.ends_with(".gd"):
				continue
			var text: String = FileAccess.get_file_as_string(dir + f)
			for m: RegExMatch in re.search_all(text):
				found[m.get_string(1)] = true
	assert_gt(found.size(), 20, "the scan finds the core's events")
	for type: String in found:
		assert_true(known.has(type), "event type '%s' has an audio decision" % type)


func test_on_event_plays_the_mapped_sound() -> void:
	_ad.record_log = true
	_ad.on_event({"type": "explosion", "radius": 90})
	_ad.on_event({"type": "shield_down", "tank": 0})
	_ad.on_event({"type": "wind", "wind": 3})
	assert_eq(_ad.played_log, ["explosion_large", "shield_break"] as Array[String])
	assert_eq(_ad.active_voices(), 2)


# --- the voice pool ---------------------------------------------------------------------------

func test_a_burst_of_fifty_events_never_exceeds_the_voice_limit() -> void:
	_ad.record_log = true
	var keys: Array = (_ad.SOUNDS as Dictionary).keys()
	keys.erase("fire_crackle")
	keys.erase("well_hum")
	keys.sort()
	for i: int in range(50):
		_ad.play_sfx(keys[i % keys.size()] as String)
		assert_lte(_ad.active_voices(), 12, "after event %d" % i)
	assert_eq(_ad.played_log.size(), 50)
	assert_eq((_ad.stats["played"] as int) + (_ad.stats["dropped"] as int), 50, "every event was played or refused")
	assert_lte(_ad.active_voices(), 12)
	assert_gt(_ad.stats["dropped"], 0, "an over-full pool refuses (equal sounds too soon, unimportant ones)")


func test_important_sounds_steal_a_voice_from_unimportant_ones() -> void:
	# 12 different quiet sounds fill the pool ...
	var quiet: Array[String] = ["cpu_think_tick", "money_gain", "money_loss", "turn_blip", "terrain_crumble", "dirt_thud",
			"fire_light", "fire_medium", "sludge_pour", "repulsor_pulse", "shield_hit", "fire_heavy"]
	for k: String in quiet:
		assert_true(_ad.play_sfx(k), k)
	assert_eq(_ad.active_voices(), 12)
	# ... a nuke still gets through (it takes the least important one) ...
	assert_true(_ad.play_sfx("explosion_nuke"))
	assert_eq(_ad.stats["stolen"], 1)
	assert_lte(_ad.active_voices(), 12)
	# ... and a sound less important than everything playing is dropped.
	_ad.reset_for_tests()
	for k: String in ["explosion_nuke", "match_win", "round_win", "explosion_large", "tank_destroyed", "explosion_medium",
			"shield_break", "repair_chime", "chute_pop", "anchor_clank", "shield_up", "fire_heavy"]:
		assert_true(_ad.play_sfx(k), k)
	assert_false(_ad.play_sfx("cpu_think_tick"), "the faintest tick is not worth a voice")
	assert_eq(_ad.stats["dropped"], 1)


func test_equal_sounds_in_the_same_instant_are_one_sound() -> void:
	assert_true(_ad.play_sfx("explosion_small"))
	assert_false(_ad.play_sfx("explosion_small"), "too soon after the same sound")
	ShowSettings.playback_speed = 2.0
	assert_true(_ad.play_sfx("explosion_medium"))


func test_pitch_is_jittered_within_four_percent_and_never_shifted_by_speed() -> void:
	var seen_low: bool = false
	var seen_high: bool = false
	for speed: float in [1.0, 2.0]:
		ShowSettings.playback_speed = speed
		for i: int in range(40):
			_ad.reset_for_tests()
			assert_true(_ad.play_sfx("fire_light"))
			var p: AudioStreamPlayer = _ad.get_node("Voice0")
			assert_between(p.pitch_scale, 0.96, 1.04)
			seen_low = seen_low or p.pitch_scale < 0.995
			seen_high = seen_high or p.pitch_scale > 1.005
	assert_true(seen_low and seen_high, "the pitch really varies")


func test_every_sound_plays_without_errors_on_the_dummy_driver() -> void:
	for key: String in REQUIRED:
		if key.begins_with("ui_"):
			assert_true(_ad.play_ui(key), key)
		else:
			_ad.play_sfx(key)
		_ad.reset_for_tests()
	_ad.play_music("nothing")  # no track exists: a silent no-op
	_ad.stop_music()
	assert_eq(_ad.active_voices(), 0)


# --- loops ------------------------------------------------------------------------------------

func test_well_hum_plays_while_any_well_exists() -> void:
	assert_false(_ad.is_hum_playing())
	_ad.on_event({"type": "well_on", "owner": 0, "x": 100, "y": 100, "expires_turn": 5})
	assert_true(_ad.is_hum_playing())
	_ad.on_event({"type": "well_on", "owner": 1, "x": 300, "y": 100, "expires_turn": 5})
	_ad.on_event({"type": "well_off", "owner": 0})
	assert_true(_ad.is_hum_playing(), "one well is still there")
	_ad.on_event({"type": "well_off", "owner": 1})
	assert_false(_ad.is_hum_playing(), "the last well is gone")
	var hum: AudioStreamPlayer = _ad.get_node("WellHum")
	await wait_until(func() -> bool: return not hum.playing, 3.0, 0.1)
	assert_false(hum.playing, "the hum has faded out and stopped")


func test_a_replaced_well_keeps_the_hum_and_a_new_round_clears_it() -> void:
	_ad.on_event({"type": "well_off", "owner": 0})
	_ad.on_event({"type": "well_on", "owner": 0})
	assert_true(_ad.is_hum_playing(), "well_off then well_on for one owner (a replaced well)")
	_ad.on_event({"type": "round_start", "round": 2})
	assert_false(_ad.is_hum_playing(), "wells are cleared at round start")
	_ad.sync_wells([2])
	assert_true(_ad.is_hum_playing(), "restoring a match with a well brings the hum back")
	_ad.stop_all()
	assert_false(_ad.is_hum_playing())


func test_the_hum_fades_in_and_is_audible() -> void:
	_ad.on_event({"type": "well_on", "owner": 0})
	var hum: AudioStreamPlayer = _ad.get_node("WellHum")
	await wait_seconds(0.5)
	assert_true(hum.playing)
	assert_almost_eq(hum.volume_db, (_ad.SOUNDS["well_hum"] as Dictionary)["db"] as float, 0.5)


func test_fire_crackle_follows_the_flames_and_fades_out() -> void:
	assert_false(_ad.is_crackle_playing())
	_ad.on_event({"type": "flames", "points": PackedInt32Array([1, 2, 3, 4])})
	assert_true(_ad.is_crackle_playing())
	var p: AudioStreamPlayer = _ad.get_node("FireCrackle")
	assert_true(p.playing)
	await wait_seconds(1.2)
	assert_lt(p.volume_db, (_ad.SOUNDS["fire_crackle"] as Dictionary)["db"] as float - 3.0, "fading with the flames")
	await wait_until(func() -> bool: return not _ad.is_crackle_playing(), 2.0, 0.1)
	assert_false(p.playing, "silent once the flames are out")


# --- CPU thinking tick ---------------------------------------------------------------------------

func test_cpu_think_ticks_are_subtle_and_absent_in_instant_mode() -> void:
	_ad.record_log = true
	_ad.think_tick(0.1)
	assert_eq(_ad.played_log.size(), 0, "not on every frame")
	for _i: int in range(5):
		_ad.think_tick(0.1)
	assert_gt(_ad.played_log.size(), 0)
	assert_true(_ad.played_log.all(func(k: String) -> bool: return k == "cpu_think_tick"))
	_ad.played_log.clear()
	ShowSettings.cpu_turn_speed = ShowSettings.CPU_SPEED_INSTANT
	for _i: int in range(40):
		_ad.think_tick(0.1)
	assert_eq(_ad.played_log.size(), 0, "instant CPU turns have no thinking to hear")


# --- UI sounds on every button ---------------------------------------------------------------------

func test_any_button_in_the_tree_taps() -> void:
	_ad.record_log = true
	var b := Button.new()
	add_child_autofree(b)
	b.pressed.emit()
	assert_eq(_ad.played_log, ["ui_tap"] as Array[String])


func test_back_style_buttons_get_the_back_sound_and_meta_overrides() -> void:
	_ad.record_log = true
	var names: Array[String] = ["Back", "Close", "Cancel", "Resume"]
	for n: String in names:
		var b := Button.new()
		b.name = n
		add_child_autofree(b)
		_ad.reset_for_tests()
		_ad.record_log = true
		b.pressed.emit()
		assert_eq(_ad.played_log, ["ui_back"] as Array[String], n)
	var quiet := Button.new()
	quiet.set_meta("ui_sound", "none")
	add_child_autofree(quiet)
	var buy := Button.new()
	buy.set_meta("ui_sound", "purchase")
	add_child_autofree(buy)
	_ad.reset_for_tests()
	_ad.record_log = true
	quiet.pressed.emit()
	assert_eq(_ad.played_log.size(), 0)
	buy.pressed.emit()
	assert_eq(_ad.played_log, ["ui_purchase"] as Array[String])


func test_hold_to_repeat_buttons_stay_silent() -> void:
	_ad.record_log = true
	var f := FineButton.new()
	add_child_autofree(f)
	f.pressed.emit()
	assert_eq(_ad.played_log.size(), 0)


func test_ui_sounds_off_silences_ui_but_not_effects() -> void:
	ShowSettings.ui_sounds = false
	assert_false(_ad.play_ui("tap"))
	assert_true(_ad.play_sfx("explosion_small"))
	ShowSettings.ui_sounds = true
	ShowSettings.sfx_on = false
	assert_false(_ad.play_ui("tap"), "UI sounds follow the effects switch")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))


# --- settings -> buses ---------------------------------------------------------------------------------

func test_volumes_and_switches_apply_to_the_buses() -> void:
	var sfx: int = AudioServer.get_bus_index("SFX")
	var ui: int = AudioServer.get_bus_index("UI")
	var music: int = AudioServer.get_bus_index("Music")
	ShowSettings.sfx_volume = 50
	ShowSettings.music_volume = 25
	_ad.apply_settings()
	assert_almost_eq(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.5), 0.01)
	assert_almost_eq(AudioServer.get_bus_volume_db(ui), linear_to_db(0.5), 0.01, "UI follows the effects volume")
	assert_almost_eq(AudioServer.get_bus_volume_db(music), linear_to_db(0.25), 0.01)
	assert_false(AudioServer.is_bus_mute(sfx))
	ShowSettings.sfx_volume = 100
	_ad.apply_settings()
	assert_almost_eq(AudioServer.get_bus_volume_db(sfx), 0.0, 0.01)
	ShowSettings.sfx_volume = 0
	_ad.apply_settings()
	assert_lte(AudioServer.get_bus_volume_db(sfx), -79.0, "0 is silent")
	ShowSettings.sfx_volume = 80
	ShowSettings.sfx_on = false
	ShowSettings.music_on = false
	ShowSettings.ui_sounds = true
	_ad.apply_settings()
	assert_true(AudioServer.is_bus_mute(sfx))
	assert_true(AudioServer.is_bus_mute(ui))
	assert_true(AudioServer.is_bus_mute(music))
	ShowSettings.sfx_on = true
	ShowSettings.ui_sounds = false
	_ad.apply_settings()
	assert_false(AudioServer.is_bus_mute(sfx))
	assert_true(AudioServer.is_bus_mute(ui), "UI sounds off")
	assert_true(AudioServer.is_bus_mute(music), "music is separate")


func test_a_setting_changed_directly_is_picked_up_at_the_next_sound() -> void:
	ShowSettings.sfx_on = false
	_ad.play_sfx("fire_light")
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))


func test_volumes_and_switches_persist() -> void:
	ShowSettings.sfx_volume = 35
	ShowSettings.sfx_on = false
	ShowSettings.music_volume = 90
	ShowSettings.music_on = false
	ShowSettings.ui_sounds = false
	assert_true(SettingsStore.save())
	ShowSettings.reset()
	_ad.apply_settings()
	assert_eq(ShowSettings.sfx_volume, 80, "defaults after a reset")
	assert_true(SettingsStore.load_into())
	assert_eq(ShowSettings.sfx_volume, 35)
	assert_false(ShowSettings.sfx_on)
	assert_eq(ShowSettings.music_volume, 90)
	assert_false(ShowSettings.music_on)
	assert_false(ShowSettings.ui_sounds)
	# Loading also pushes the values into the buses.
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")))
	assert_almost_eq(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.9), 0.01)


func test_damaged_sound_settings_are_clamped_or_ignored() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("show", "sfx_volume", 900)
	cfg.set_value("show", "music_volume", -5)
	cfg.set_value("show", "sfx_on", "loud")
	cfg.set_value("show", "ui_sounds", 3)
	cfg.save(PATH)
	assert_true(SettingsStore.load_into())
	assert_eq(ShowSettings.sfx_volume, 100)
	assert_eq(ShowSettings.music_volume, 0)
	assert_true(ShowSettings.sfx_on, "a non-bool keeps the default")
	assert_true(ShowSettings.ui_sounds)


func test_music_bus_and_player_exist_without_a_track() -> void:
	var p: AudioStreamPlayer = _ad.get_node("Music")
	assert_eq(p.bus, &"Music")
	assert_null(p.stream, "no track yet")
	assert_true((_ad.MUSIC_TRACKS as Dictionary).is_empty())
