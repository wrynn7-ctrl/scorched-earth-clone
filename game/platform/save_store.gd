class_name SaveStore
extends RefCounted
## Autosave file IO (docs/ARCHITECTURE.md section 22). The bytes come from SaveCodec; this
## class compresses them, writes them atomically (write `.tmp`, then rename over the real
## file), reads them back and deletes them. All paths default to `user://autosave.crtl`.
##
## File layout (little endian), written by save():
##   "CRZ1"  u32 uncompressed size  u32 meta length  meta (JSON, show-layer extras)
##   zstd( SaveCodec bytes )
## The uncompressed size lets decompress() allocate once and doubles as an integrity check.
## Files that do not start with "CRZ1" are treated as raw SaveCodec bytes (older saves, and
## tests that write bytes directly), so reading stays backward compatible.
##
## The `meta` dictionary is for things the simulation does not own, such as the players'
## chosen colours/emblems and the summary shown after a round. It is never hashed.

const AUTOSAVE_PATH: String = "user://autosave.crtl"
const TMP_SUFFIX: String = ".tmp"
const MAGIC: String = "CRZ1"
const HEADER_LEN: int = 12
## Biggest uncompressed size we accept (a save is ~1.5 MB; this only stops garbage headers).
const MAX_RAW_SIZE: int = 64 * 1024 * 1024

## Timing and size of the last save()/load_save(), for diagnostics (ms and bytes).
static var last_encode_ms: float = 0.0
static var last_raw_bytes: int = 0
static var last_file_bytes: int = 0


## Encodes, compresses and writes the state + action log. Returns true on success. On failure
## the previous save (if any) is untouched.
static func save(state: MatchState, actions: Array[Dictionary], path: String = AUTOSAVE_PATH,
		meta: Dictionary = {}) -> bool:
	var t0: int = Time.get_ticks_usec()
	var raw: PackedByteArray = SaveCodec.encode(state, actions)
	var file_bytes: PackedByteArray = pack(raw, meta)
	last_encode_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_raw_bytes = raw.size()
	last_file_bytes = file_bytes.size()
	return write_bytes(file_bytes, path)


## Wraps SaveCodec bytes in the compressed container.
static func pack(raw: PackedByteArray, meta: Dictionary = {}) -> PackedByteArray:
	var meta_bytes: PackedByteArray = JSON.stringify(meta).to_utf8_buffer() if not meta.is_empty() else PackedByteArray()
	var b := StreamPeerBuffer.new()
	b.put_data(MAGIC.to_ascii_buffer())
	b.put_32(raw.size())
	b.put_32(meta_bytes.size())
	b.put_data(meta_bytes)
	b.put_data(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return b.data_array


## Returns {ok, raw (SaveCodec bytes), meta}. Raw (uncompressed) files pass straight through.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	var out: Dictionary = {"ok": false, "raw": PackedByteArray(), "meta": {}}
	if bytes.size() < MAGIC.length() or bytes.slice(0, MAGIC.length()) != MAGIC.to_ascii_buffer():
		out["ok"] = not bytes.is_empty()
		out["raw"] = bytes
		return out
	if bytes.size() < HEADER_LEN:
		return out
	var head := StreamPeerBuffer.new()
	head.data_array = bytes.slice(4, HEADER_LEN)
	var raw_size: int = head.get_32()
	var meta_len: int = head.get_32()
	if raw_size <= 0 or raw_size > MAX_RAW_SIZE or meta_len < 0 or HEADER_LEN + meta_len >= bytes.size():
		return out
	if meta_len > 0:
		var parsed: Variant = JSON.parse_string(bytes.slice(HEADER_LEN, HEADER_LEN + meta_len).get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			out["meta"] = parsed
	var raw: PackedByteArray = bytes.slice(HEADER_LEN + meta_len).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return out
	out["raw"] = raw
	out["ok"] = true
	return out


## Atomic write: the data goes to `<path>.tmp` first and replaces `path` only once complete.
static func write_bytes(bytes: PackedByteArray, path: String = AUTOSAVE_PATH) -> bool:
	var tmp: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.flush()
	var write_err: Error = f.get_error()
	f.close()
	if write_err != OK:
		DirAccess.remove_absolute(tmp)
		return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		# Some platforms refuse to rename over an existing file: remove it and retry.
		DirAccess.remove_absolute(path)
		if DirAccess.rename_absolute(tmp, path) != OK:
			DirAccess.remove_absolute(tmp)
			return false
	return true


## SaveCodec bytes of the save (decompressed), or an empty array if the file is missing,
## unreadable or its compressed payload is damaged.
static func read_bytes(path: String = AUTOSAVE_PATH) -> PackedByteArray:
	var file_bytes: PackedByteArray = read_file(path)
	if file_bytes.is_empty():
		return PackedByteArray()
	return unpack(file_bytes)["raw"] as PackedByteArray


## The file exactly as stored (compressed container), or empty.
static func read_file(path: String = AUTOSAVE_PATH) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## Reads and decodes the save. Same result shape as SaveCodec.decode plus `meta`; error
## "no_file" when there is no save, "corrupt" when the container or codec data is damaged.
static func load_save(path: String = AUTOSAVE_PATH) -> Dictionary:
	var file_bytes: PackedByteArray = read_file(path)
	if file_bytes.is_empty():
		return {"ok": false, "error": "no_file", "state": null, "actions": [] as Array[Dictionary], "meta": {}}
	var unpacked: Dictionary = unpack(file_bytes)
	if not (unpacked["ok"] as bool):
		return {"ok": false, "error": "corrupt", "state": null, "actions": [] as Array[Dictionary], "meta": {}}
	var res: Dictionary = SaveCodec.decode(unpacked["raw"] as PackedByteArray)
	res["meta"] = unpacked["meta"]
	return res


## Removes the save and any leftover temp file. Returns true if nothing is left.
static func delete(path: String = AUTOSAVE_PATH) -> bool:
	for p: String in [path, path + TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	return not FileAccess.file_exists(path)


## True if a save exists and decodes (magic, version, checksum and fingerprint all pass).
static func has_valid_save(path: String = AUTOSAVE_PATH) -> bool:
	return load_save(path)["ok"] as bool
