extends GutTest
## Guards NetProtocol.VERSION. Two phones with different game versions must never play one match, so any change to
## simulation or AI behaviour has to bump the version. This test plays a fixed scripted match through NetReplay and compares
## the entry count and final fingerprint with stored values; it fails when the game's behaviour changed.
##
## If it fails: you changed the rules, a weapon, terrain or wind generation, the AI, or the log format. Bump
## NetProtocol.VERSION (see its comment), then paste the new values printed by the failure message below.

const GOLDEN_ENTRIES: int = 27
const GOLDEN_FINGERPRINT: String = "cdaf3c0814f91f76"
const GOLDEN_PROTOCOL: int = 1


func _play() -> Dictionary:
	var meta: Dictionary = NetTestUtil.meta([NetTestUtil.human("a"), NetTestUtil.cpu(2), NetTestUtil.cpu(4)],
			{"rounds": 2, "wind_max": 50, "start_money": 8000}, {}, 20240607)
	var replay: NetReplay = NetReplay.create(meta)
	var log: Array[Dictionary] = NetTestUtil.play_through(replay, 500)
	return {"entries": log.size(), "fp": replay.fingerprint(), "ended": replay.ended}


func test_golden_match_fingerprint() -> void:
	var got: Dictionary = _play()
	assert_true(got["ended"], "the golden match finishes")
	var msg: String = "Game behaviour changed. Bump NetProtocol.VERSION (now %d) and set GOLDEN_ENTRIES=%d, GOLDEN_FINGERPRINT=\"%s\", GOLDEN_PROTOCOL=%d" \
			% [NetProtocol.VERSION, got["entries"], got["fp"], NetProtocol.VERSION + 1]
	assert_eq(got["entries"], GOLDEN_ENTRIES, msg)
	assert_eq(got["fp"], GOLDEN_FINGERPRINT, msg)


func test_protocol_version_was_bumped_with_the_golden() -> void:
	assert_eq(NetProtocol.VERSION, GOLDEN_PROTOCOL, "NetProtocol.VERSION changed: also refresh the golden values in this file")


func test_replay_is_repeatable() -> void:
	assert_eq(_play()["fp"], _play()["fp"])
