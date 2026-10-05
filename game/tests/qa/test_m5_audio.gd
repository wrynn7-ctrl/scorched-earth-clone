@warning_ignore_start("integer_division")
extends GutTest
## M5 QA: AudioDirector (docs/ARCHITECTURE.md section 33). Every event type the core can emit (found by
## scanning game/core/** for `"type": "..."` literals, subfolders included) must have a decision: a registered
## sound or an explicit silence. Real timelines from every weapon, the items and a Love Edition match are
## pushed through the map, and a 500-event burst must never exceed the voice caps.

const QaUtil = preload("res://tests/qa/qa_util.gd")
const M5 = preload("res://tests/qa/qa_m5.gd")

## Event types that are deliberately silent as one-shots (loops, or the sound belongs to another event).
## This is the list in audio_director.gd's closing comment of sound_for_event().
const EXPLICIT_SILENT: Array[String] = ["projectile", "projectile_end", "terrain_carve", "wind", "beam", "tank_fall",
		"tank_move", "well_on", "well_off", "flames", "ready", "repulsor_down", "round_start"]

var _ad: Node = null


func before_each() -> void:
	_ad = get_tree().root.get_node("AudioDirector")
	ShowSettings.reset()
	_ad.reset_for_tests()
	_ad.apply_settings()


func after_each() -> void:
	_ad.reset_for_tests()
	ShowSettings.reset()
	_ad.apply_settings()


# --- the scan -------------------------------------------------------------------------------------

func _scan_dir(dir: String, re: RegEx, found: Dictionary) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			for m: RegExMatch in re.search_all(FileAccess.get_file_as_string(dir + f)):
				found[m.get_string(1)] = true
	for d: String in DirAccess.get_directories_at(dir):
		_scan_dir(dir + d + "/", re, found)


func _core_event_types() -> Array[String]:
	var re := RegEx.new()
	re.compile("\"type\"\\s*:\\s*\"([a-z_0-9]+)\"")
	var found: Dictionary = {}
	_scan_dir("res://core/", re, found)
	var out: Array[String] = []
	for k: Variant in found.keys():
		out.append(str(k))
	out.sort()
	return out


## Representative events per type (every variant that changes the decision).
func _samples() -> Dictionary:
	return {
		"fire": [{"type": "fire", "weapon": "spark_dart"}, {"type": "fire", "weapon": "heart"},
				{"type": "fire", "weapon": "photon_lance"}, {"type": "fire", "weapon": "nova_core"}],
		"projectile": [{"type": "projectile", "id": 0, "weapon": "heart", "path": PackedInt32Array([1, 2])}],
		"projectile_end": [{"type": "projectile_end", "id": 0, "reason": "terrain", "x": 1, "y": 2}],
		"explosion": [{"type": "explosion", "radius": 1}, {"type": "explosion", "radius": 30}, {"type": "explosion", "radius": 160}],
		"terrain_carve": [{"type": "terrain_carve", "x": 1, "y": 2, "radius": 3}],
		"terrain_settle": [{"type": "terrain_settle", "x0": 0, "x1": 5, "falls": [{"x": 1, "from_y": 2, "to_y": 5, "length": 3}]},
				{"type": "terrain_settle", "x0": 0, "x1": 5, "falls": []}],
		"damage": [{"type": "damage", "cause": "explosion"}, {"type": "damage", "cause": "fall"}, {"type": "damage", "cause": "burn"}],
		"tank_fall": [{"type": "tank_fall", "tank": 0, "from_y": 1, "to_y": 9}],
		"tank_destroyed": [{"type": "tank_destroyed", "tank": 0}],
		"wind": [{"type": "wind", "wind": -7}],
		"turn": [{"type": "turn", "tank": 1}],
		"round_end": [{"type": "round_end", "winner": 0}, {"type": "round_end", "winner": -1}],
		# TEMPORARY SILENCE: section 42 wants a sound + banner when sudden death starts; the show layer adds the
		# sound, then moves "sudden_death" off EXPLICIT_SILENT above.
		"sudden_death": [{"type": "sudden_death"}],
		"round_start": [{"type": "round_start", "round": 0}],
		"money": [{"type": "money", "delta": 5, "reason": "damage"}, {"type": "money", "delta": -5, "reason": "self_damage"},
				{"type": "money", "delta": -5, "reason": "buy"}, {"type": "money", "delta": 5, "reason": "sell"},
				{"type": "money", "delta": 1000, "reason": "survive"}],
		"shield_hit": [{"type": "shield_hit", "tank": 0, "absorbed": 3, "hp": 5}],
		"shield_down": [{"type": "shield_down", "tank": 0}],
		"shield_on": [{"type": "shield_on", "tank": 0, "item": "glow_shield", "hp": 30}],
		"repulsor_on": [{"type": "repulsor_on", "tank": 0, "charge": 100}],
		"repulsor_down": [{"type": "repulsor_down", "tank": 0}],
		"chute": [{"type": "chute", "tank": 0}],
		"repair": [{"type": "repair", "tank": 0, "amount": 40, "health": 100}],
		"tank_move": [{"type": "tank_move", "tank": 0, "from_x": 1, "to_x": 5, "fuel": 3}],
		"ready": [{"type": "ready", "tank": 0}],
		"well_off": [{"type": "well_off", "owner": 0}],
		"well_on": [{"type": "well_on", "owner": 0, "x": 1, "y": 2, "expires_turn": 3}],
		"tunnel": [{"type": "tunnel", "x0": 1, "y0": 2, "x1": 3, "y1": 4, "radius": 5}],
		"terrain_add": [{"type": "terrain_add", "x": 1, "y": 2, "radius": 3, "material": 1}],
		"terrain_pour": [{"type": "terrain_pour", "x": 1, "cells": PackedInt32Array([1, 2]), "material": 1}],
		"flames": [{"type": "flames", "points": PackedInt32Array([1, 2])}],
		"beam": [{"type": "beam", "x0": 1, "y0": 2, "x1": 3, "y1": 4}],
		"tank_drag": [{"type": "tank_drag", "tank": 0, "from_x": 1, "to_x": 90}, {"type": "tank_drag", "tank": 0, "from_x": 1, "to_x": 1}],
		"heart_burst": [{"type": "heart_burst", "x": 1, "y": 2, "radius": 30}],
		"love": [{"type": "love", "tank": 1, "amount": 34, "love": 34, "from": 0}],
	}


func test_every_event_type_in_core_has_a_decision() -> void:
	var types: Array[String] = _core_event_types()
	gut.p("AUDIO  core event types found by the scan (%d): %s" % [types.size(), ", ".join(types)])
	assert_gt(types.size(), 30, "the recursive scan finds the core's events")
	for must: String in ["heart_burst", "love", "round_end", "tunnel", "terrain_pour", "well_on"]:
		assert_true(types.has(must), "scan sees '%s'" % must)
	var samples: Dictionary = _samples()
	var sounds: Dictionary = _ad.SOUNDS
	for t: String in types:
		assert_true(samples.has(t), "event type '%s' is new: give AudioDirector a sound or an explicit silence, then add it here" % t)
		if not samples.has(t):
			continue
		var any_sound: bool = false
		for e: Dictionary in samples[t]:
			var key: String = _ad.sound_for_event(e)
			assert_true(key == "" or sounds.has(key), "'%s' -> '%s' is a registered sound" % [str(e), key])
			any_sound = any_sound or key != ""
		if EXPLICIT_SILENT.has(t):
			assert_false(any_sound, "'%s' is documented as silent but plays a sound" % t)
		else:
			assert_true(any_sound, "'%s' is not on the silent list yet no sample of it makes a sound" % t)
	for t: String in EXPLICIT_SILENT:
		assert_true(types.has(t), "the silent list names '%s' but the core never emits it" % t)
	for t: Variant in samples.keys():
		assert_true(types.has(str(t)), "stale sample for '%s'" % str(t))


func test_love_events_have_their_own_sounds() -> void:
	assert_eq(_ad.sound_for_event({"type": "heart_burst", "radius": 30}), "heart_burst")
	assert_eq(_ad.sound_for_event({"type": "love", "tank": 1, "amount": 12}), "love_fire")
	assert_eq(_ad.sound_for_event({"type": "fire", "weapon": "heart"}), "love_fire")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": 0}, true, true), "love_win")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": 1}, false, true), "love_win", "love has one round")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": -1}, true, true), "", "no winner, no jingle")
	assert_eq(_ad.sound_for_event({"type": "round_end", "winner": 0}, true, false), "match_win")
	for key: String in ["love_fire", "heart_burst", "love_win", "love_found"]:
		assert_true((_ad.SOUNDS as Dictionary).has(key), key)
	# A love shot is silent where a standard shot is loud: no explosion, no crumble, no money, no tank_destroyed.
	var s: MatchState = M5.flat_love([300, 480], 0)
	s.current_tank = 0
	var ev: Array[Dictionary] = Simulation.apply_action(s, M5.heart(0, 450, 560))
	var keys: Array[String] = []
	for e: Dictionary in ev:
		var k: String = _ad.sound_for_event(e, false, true)
		if k != "":
			keys.append(k)
	assert_true(keys.has("love_fire"), "the shot chimes: %s" % str(keys))
	for bad: String in ["explosion_small", "explosion_medium", "terrain_crumble", "dirt_thud", "money_gain", "tank_destroyed", "match_win", "round_win"]:
		assert_false(keys.has(bad), "a heart must not play %s" % bad)


# --- real timelines ----------------------------------------------------------------------------------------

## Events from every shop weapon (one shot each on flat ground with a target in range), the usable items,
## movement, and a few love shots. Returns all events.
func _real_events() -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for id: String in WeaponDefs.DEFS.keys():
		for power: int in [480, 300, 560]:
			var s: MatchState = QaUtil.flat_state([300, 520, 760], 600, 3)
			s.tanks[0].set_stock(id, 3)
			s.tanks[1].set_stock("glow_shield", 1)
			s.tanks[1].shield_type = Catalog.index_of("glow_shield")
			s.tanks[1].shield_hp = 30
			s.tanks[2].health = 12
			var a: Dictionary = {"kind": "fire", "tank": 0, "angle": 450, "power": power, "weapon": id}
			if Simulation.validate_action(s, a) == "":
				all.append_array(Simulation.apply_action(s, a))
	var s2: MatchState = QaUtil.flat_state([300, 520], 600, 3)
	s2.tanks[0].set_stock("glow_shield", 2)
	s2.tanks[0].set_stock("repulsor_field", 1)
	s2.tanks[0].set_stock("nanorepair_kit", 1)
	s2.tanks[0].set_stock("fuel_cell", 2)
	s2.tanks[0].health = 40
	for a: Dictionary in [{"kind": "use_item", "tank": 0, "item": "glow_shield"}, {"kind": "use_item", "tank": 0, "item": "repulsor_field"},
			{"kind": "move", "tank": 0, "dx": 30}, {"kind": "use_item", "tank": 0, "item": "nanorepair_kit"}]:
		if Simulation.validate_action(s2, a) == "":
			all.append_array(Simulation.apply_action(s2, a))
	var shop: MatchState = Simulation.new_match(QaUtil.settings(5, 2, 1))
	all.append_array(Simulation.apply_action(shop, {"kind": "buy", "tank": 0, "item": "pulse_missile", "qty": 1}))
	all.append_array(Simulation.apply_action(shop, {"kind": "sell", "tank": 0, "item": "pulse_missile", "qty": 2}))
	all.append_array(Simulation.apply_action(shop, {"kind": "ready", "tank": 0}))
	all.append_array(Simulation.apply_action(shop, {"kind": "ready", "tank": 1}))
	all.append_array(Simulation.start_round(shop))
	var love: MatchState = Simulation.new_match(M5.love_settings(8, 3, 3, 30))
	var guard: int = 0
	while love.phase == SimConstants.PHASE_AIM and guard < 60:
		guard += 1
		all.append_array(Simulation.apply_action(love, AiPlayer.next_action(love, love.current_tank)))
	return all


func test_real_timelines_only_ever_map_to_registered_sounds() -> void:
	var events: Array[Dictionary] = _real_events()
	var seen: Dictionary = {}
	var sounds: Dictionary = _ad.SOUNDS
	for e: Dictionary in events:
		seen[e["type"]] = true
		for flags: Array in [[false, false], [true, false], [false, true], [true, true]]:
			var key: String = _ad.sound_for_event(e, flags[0] as bool, flags[1] as bool)
			assert_true(key == "" or sounds.has(key), "%s with %s -> '%s'" % [str(e["type"]), str(flags), key])
	var core_types: Array[String] = _core_event_types()
	var missing: Array[String] = []
	for t: String in core_types:
		if not seen.has(t):
			missing.append(t)
	gut.p("AUDIO  %d real events, %d of %d core types exercised; not reached by this scenario set: %s" % [
			events.size(), seen.size(), core_types.size(), ", ".join(missing)])
	assert_gt(seen.size(), 24, "the scenarios produce a wide variety of events")
	assert_true(seen.has("heart_burst") and seen.has("love") and seen.has("terrain_pour"))


## Events missing fields, and types the director has never heard of. (Wrong field TYPES are not tested: the
## core always emits the types of docs/ARCHITECTURE.md section 10, and the director casts them directly.)
func test_events_with_missing_fields_and_unknown_types_never_crash_the_director() -> void:
	var odd: Array[Dictionary] = [
		{}, {"type": ""}, {"type": "no_such_event"}, {"type": "explosion"}, {"type": "explosion", "radius": -50},
		{"type": "explosion", "radius": 2147483647}, {"type": "fire"}, {"type": "fire", "weapon": ""},
		{"type": "fire", "weapon": "not_a_weapon"}, {"type": "terrain_settle"}, {"type": "terrain_settle", "falls": null},
		{"type": "terrain_settle", "falls": 3}, {"type": "money"}, {"type": "money", "delta": 0, "reason": ""},
		{"type": "round_end"}, {"type": "tank_drag"}, {"type": "damage"}, {"type": "well_on"}, {"type": "well_off"},
		{"type": "love"}, {"type": "heart_burst"}, {"type": "shield_on"}, {"type": "turn"},
	]
	for e: Dictionary in odd:
		var key: String = _ad.sound_for_event(e)
		assert_true(key == "" or (_ad.SOUNDS as Dictionary).has(key), "%s -> '%s'" % [str(e), key])
		_ad.on_event(e, false, false)
		_ad.on_event(e, true, true)
	_ad.stop_all()
	assert_lte(_ad.active_voices(), 12)


# --- the burst ------------------------------------------------------------------------------------------------------

func _ui_busy() -> int:
	var n: int = 0
	for p: AudioStreamPlayer in _ad._ui_voices:
		if p.playing:
			n += 1
	return n


func _player_count() -> int:
	var n: int = 0
	for c: Node in _ad.get_children():
		if c is AudioStreamPlayer:
			n += 1
	return n


func test_a_500_event_burst_never_exceeds_the_voice_caps() -> void:
	var events: Array[Dictionary] = _real_events()
	assert_gt(events.size(), 50)
	var players_before: int = _player_count()
	_ad.record_log = true
	var expected_requests: int = 0
	var peak: int = 0
	var peak_ui: int = 0
	var love_run: bool = false
	for i: int in range(500):
		var e: Dictionary = events[(i * 7) % events.size()]  # a scrambled but reproducible mix
		var love: bool = (i / 100) % 2 == 1
		love_run = love_run or love
		if _ad.sound_for_event(e, i % 50 == 49, love) != "":
			expected_requests += 1
		_ad.on_event(e, i % 50 == 49, love)
		peak = maxi(peak, _ad.active_voices())
		assert_lte(_ad.active_voices(), _ad.MAX_VOICES, "voice cap after event %d" % i)
		if i % 5 == 0:
			_ad.play_ui("tap")
			peak_ui = maxi(peak_ui, _ui_busy())
			assert_lte(_ui_busy(), _ad.UI_VOICES, "UI voice cap after event %d" % i)
		if i % 40 == 39:
			await get_tree().process_frame  # time passes: gaps expire, voices finish and get stolen
			await wait_seconds(0.03)
	assert_true(love_run)
	assert_eq(_player_count(), players_before, "no player node was created or freed while playing")
	var counted: int = (_ad.stats["played"] as int) + (_ad.stats["dropped"] as int)
	assert_eq(counted, _ad.played_log.size(), "every request was either played or refused")
	assert_gte(_ad.played_log.size(), expected_requests, "every mapped event asked for its sound (plus the UI taps)")
	gut.p("AUDIO  500-event burst: peak %d/%d effect voices, peak %d/%d UI voices, stats %s" % [peak, _ad.MAX_VOICES,
			peak_ui, _ad.UI_VOICES, str(_ad.stats)])
	assert_gt(_ad.stats["played"], 20, "plenty was heard")
	assert_gt(_ad.stats["dropped"], 0, "and an over-full pool refused some")
	_ad.stop_all()
	assert_lte(_ad.active_voices(), _ad.MAX_VOICES)


func test_a_tight_burst_of_500_in_one_frame_holds_the_cap() -> void:
	# No time passes at all: the equal-sound gap and the pool are the only brakes.
	var keys: Array = (_ad.SOUNDS as Dictionary).keys()
	keys.erase("fire_crackle")
	keys.erase("well_hum")
	keys.sort()
	for i: int in range(500):
		_ad.play_sfx(keys[(i * 5) % keys.size()] as String)
		assert_lte(_ad.active_voices(), _ad.MAX_VOICES)
	assert_lte(_ad.active_voices(), _ad.MAX_VOICES)
	for i: int in range(500):
		_ad.play_ui("tap" if i % 2 == 0 else "back")
		assert_lte(_ui_busy(), _ad.UI_VOICES)
