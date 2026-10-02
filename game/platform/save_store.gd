class_name SaveStore
extends RefCounted
## Autosave file IO (docs/ARCHITECTURE.md section 22). The bytes come from SaveCodec; this
## class only writes them atomically (write `.tmp`, then rename over the real file), reads
## them back and deletes them. All paths default to `user://autosave.crtl`.

const AUTOSAVE_PATH: String = "user://autosave.crtl"
const TMP_SUFFIX: String = ".tmp"


## Encodes and writes the state + action log. Returns true on success. On failure the
## previous save (if any) is untouched.
static func save(state: MatchState, actions: Array[Dictionary], path: String = AUTOSAVE_PATH) -> bool:
	return write_bytes(SaveCodec.encode(state, actions), path)


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


## Raw file bytes, or an empty array if the file is missing or unreadable.
static func read_bytes(path: String = AUTOSAVE_PATH) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## Reads and decodes the save. Same result shape as SaveCodec.decode; error "no_file" when
## there is no save.
static func load_save(path: String = AUTOSAVE_PATH) -> Dictionary:
	var bytes: PackedByteArray = read_bytes(path)
	if bytes.is_empty():
		return {"ok": false, "error": "no_file", "state": null, "actions": [] as Array[Dictionary]}
	return SaveCodec.decode(bytes)


## Removes the save and any leftover temp file. Returns true if nothing is left.
static func delete(path: String = AUTOSAVE_PATH) -> bool:
	for p: String in [path, path + TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	return not FileAccess.file_exists(path)


## True if a save exists and decodes (magic, version, checksum and fingerprint all pass).
static func has_valid_save(path: String = AUTOSAVE_PATH) -> bool:
	return load_save(path)["ok"] as bool
