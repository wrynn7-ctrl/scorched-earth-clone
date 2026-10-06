extends GutTest
## LobbyModel: the lobby's rules as plain functions (no scene, no network).

const ME: String = "uidMe"
const OTHER: String = "uidOther"


func _meta(seats: Array, overrides: Dictionary = {}, host: String = ME) -> Dictionary:
	return OnlineFakes.lobby_meta(seats, overrides, host)


func _h(uid: String = "") -> Dictionary:
	return {"kind": "human", "uid": uid, "name": "X"} if uid != "" else {"kind": "human"}


func test_host_open_seats_and_membership() -> void:
	var m: Dictionary = _meta([_h(ME), _h(), OnlineFakes.cpu_seat()])
	assert_true(LobbyModel.is_host(m, ME))
	assert_false(LobbyModel.is_host(m, OTHER))
	assert_false(LobbyModel.is_host(m, ""))
	assert_eq(LobbyModel.open_count(m), 1)
	assert_eq(LobbyModel.human_count(m), 2)
	assert_eq(LobbyModel.cpu_count(m), 1)
	assert_eq(LobbyModel.seats_held_by(m, ME), [0] as Array[int])
	assert_true(LobbyModel.is_member(m, ME))
	assert_false(LobbyModel.is_member(m, OTHER))


func test_start_check_reasons() -> void:
	var none := PackedInt32Array([-1, -1, -1])
	assert_eq(LobbyModel.start_check(_meta([_h(ME), _h(), OnlineFakes.cpu_seat()]), ME, none)["reason"], "open_seats")
	assert_eq(LobbyModel.start_check(_meta([_h(ME), _h(OTHER)]), OTHER, none)["reason"], "not_host")
	assert_true(LobbyModel.start_check(_meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()]), ME, none)["ok"])
	assert_eq(LobbyModel.start_check(_meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()]), ME, PackedInt32Array([0, -1, 1]))["reason"], "need_all")
	assert_eq(LobbyModel.start_check(_meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()]), ME, PackedInt32Array([0, 0, 0]))["reason"], "need_two")
	assert_true(LobbyModel.start_check(_meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()]), ME, PackedInt32Array([0, 1, 1]))["ok"])


func test_teams_param_is_empty_unless_usable() -> void:
	assert_eq(LobbyModel.teams_param(PackedInt32Array([-1, -1])), [])
	assert_eq(LobbyModel.teams_param(PackedInt32Array([0, -1])), [])
	assert_eq(LobbyModel.teams_param(PackedInt32Array([0, 0])), [])
	assert_eq(LobbyModel.teams_param(PackedInt32Array([0, 1, 1])), [0, 1, 1])


func test_teams_of_reads_the_settings_and_pads_missing_entries() -> void:
	var m: Dictionary = _meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()], {"teams": [0, 1]})
	assert_eq(LobbyModel.teams_of(m), PackedInt32Array([0, 1, -1]))
	assert_eq(LobbyModel.teams_of(_meta([_h(ME), _h(OTHER)])), PackedInt32Array([-1, -1]))


func test_seat_specs_carry_held_seats_by_uid() -> void:
	var m: Dictionary = _meta([_h(ME), _h(), OnlineFakes.cpu_seat(3), _h(ME)])
	var specs: Array = LobbyModel.seat_specs(m)
	assert_eq(specs[0], {"kind": "human", "uid": ME})
	assert_eq(specs[1], {"kind": "human"})
	assert_eq(specs[2], {"kind": "cpu", "level": 3})
	assert_eq(specs[3], {"kind": "human", "uid": ME})


func test_add_remove_and_limits() -> void:
	var m: Dictionary = _meta([_h(ME), _h(OTHER)])
	assert_eq(LobbyModel.add_cpu(m, 2).size(), 3)
	assert_eq(LobbyModel.remove_seat(m, 1).size(), 2, "never below two seats")
	var m3: Dictionary = _meta([_h(ME), _h(OTHER), OnlineFakes.cpu_seat()])
	assert_eq(LobbyModel.remove_seat(m3, 2).size(), 2)
	assert_eq(LobbyModel.remove_seat(m3, 1).size(), 3, "a held seat stays")
	var full: Array = []
	for i: int in range(8):
		full.append(_h(ME) if i == 0 else OnlineFakes.cpu_seat())
	assert_eq(LobbyModel.add_cpu(_meta(full), 2).size(), 8)


func test_love_lobbies_are_frozen() -> void:
	var m: Dictionary = _meta([_h(ME), _h()], {"mode": 1})
	assert_true(LobbyModel.is_love(m))
	assert_eq(LobbyModel.add_cpu(m, 2).size(), 2)
	assert_eq(LobbyModel.add_human(m).size(), 2)
	assert_eq(LobbyModel.remove_seat(m, 1).size(), 2)


func test_level_and_value_cycles() -> void:
	assert_eq(LobbyModel.next_level(1), 2)
	assert_eq(LobbyModel.next_level(4), 1)
	assert_eq(LobbyModel.cycle([30, 60, 120], 120), 30)
	assert_eq(LobbyModel.cycle([30, 60, 120], 45), 30, "an unknown value starts the list")
	assert_eq(LobbyModel.cycle(["auto", "end"], "auto"), "end")


func test_timers_have_the_server_defaults() -> void:
	assert_eq(LobbyModel.timers_of({}), {"liveSec": 60, "asyncHours": 72, "asyncTimeout": "auto"})
	assert_eq(LobbyModel.timers_of({"timers": {"liveSec": 30, "asyncHours": 24, "asyncTimeout": "end"}}), {"liveSec": 30, "asyncHours": 24, "asyncTimeout": "end"})


func test_the_presets_are_the_ones_in_the_design() -> void:
	assert_eq(LobbyModel.LIVE_PRESETS, [30, 60, 120] as Array[int])
	assert_eq(LobbyModel.ASYNC_PRESETS, [24, 72] as Array[int])
	assert_eq(LobbyModel.ASYNC_TIMEOUTS, ["auto", "end"] as Array[String])
