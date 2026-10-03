@warning_ignore_start("integer_division")
class_name SaveCodec
extends RefCounted
## Binary save format (docs/ARCHITECTURE.md section 22). Pure: bytes in, bytes out; the
## file IO lives in game/platform/save_store.gd.
##
## Layout (little endian):
##   "CRTL"  u32 SAVE_VERSION
##   state snapshot (StateSerial.write, same field order as the fingerprint)
##   u32 json length, action log as JSON (sorted keys)
##   16 ASCII bytes: Simulation.fingerprint(state)
##   32 bytes: SHA-256 of everything above (detects any flipped byte)
## Bump SAVE_VERSION when StateSerial's layout or the catalog changes.

const MAGIC: String = "CRTL"
const SAVE_VERSION: int = 2
const FP_LEN: int = 16
const SUM_LEN: int = 32


static func encode(state: MatchState, actions: Array[Dictionary]) -> PackedByteArray:
	var snapshot: PackedByteArray = StateSerial.serialize(state)
	var json: PackedByteArray = JSON.stringify(actions).to_utf8_buffer()
	var b := StreamPeerBuffer.new()
	b.put_data(MAGIC.to_ascii_buffer())
	b.put_32(SAVE_VERSION)
	b.put_data(snapshot)
	b.put_32(json.size())
	b.put_data(json)
	b.put_data(StateSerial.hash_hex(snapshot).to_ascii_buffer())
	var body: PackedByteArray = b.data_array
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	var out: PackedByteArray = body.duplicate()
	out.append_array(ctx.finish())
	return out


## Returns {ok: bool, error: String, state: MatchState or null, actions: Array[Dictionary]}.
## Errors: too_short, bad_magic, bad_version, corrupt, fingerprint, invalid_state.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var result: Dictionary = {"ok": false, "error": "", "state": null, "actions": [] as Array[Dictionary]}
	if bytes.size() < MAGIC.length() + 4 + SUM_LEN + FP_LEN + 4:
		result["error"] = "too_short"
		return result
	if bytes.slice(0, 4) != MAGIC.to_ascii_buffer():
		result["error"] = "bad_magic"
		return result
	var head := StreamPeerBuffer.new()
	head.data_array = bytes.slice(4, 8)
	if head.get_32() != SAVE_VERSION:
		result["error"] = "bad_version"
		return result
	var body: PackedByteArray = bytes.slice(0, bytes.size() - SUM_LEN)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(body)
	if ctx.finish() != bytes.slice(bytes.size() - SUM_LEN):
		result["error"] = "corrupt"
		return result
	var b := StreamPeerBuffer.new()
	b.data_array = body
	b.seek(8)
	var state: MatchState = StateSerial.read(b)
	if state == null or b.get_available_bytes() < 4 + FP_LEN:
		result["error"] = "corrupt"
		return result
	var json_len: int = b.get_32()
	if json_len < 0 or b.get_available_bytes() != json_len + FP_LEN:
		result["error"] = "corrupt"
		return result
	var json_bytes: PackedByteArray = b.get_data(json_len)[1]
	var stored_fp: String = (b.get_data(FP_LEN)[1] as PackedByteArray).get_string_from_ascii()
	var actions: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string(json_bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		result["error"] = "corrupt"
		return result
	for item: Variant in (parsed as Array):
		if typeof(item) != TYPE_DICTIONARY:
			result["error"] = "corrupt"
			return result
		actions.append(Simulation.normalize_action(item as Dictionary))
	if Simulation.fingerprint(state) != stored_fp:
		result["error"] = "fingerprint"
		return result
	# Checksums only catch accidents: a re-sealed, hand-edited state still has to be one the
	# simulation could have produced.
	if StateSerial.validate(state) != "":
		result["error"] = "invalid_state"
		return result
	result["ok"] = true
	result["state"] = state
	result["actions"] = actions
	return result
