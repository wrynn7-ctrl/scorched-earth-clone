class_name SkinStore
extends RefCounted
## Skins on this device only (docs/ARCHITECTURE.md section 35): `user://skins/<id>.json`, an optional
## 128x64 `<id>.png` next to it, and `assign.cfg` mapping a player slot (tank id) to a skin id.
## Nothing here ever leaves the device.
##
## Everything validates on load: a damaged JSON, a wrong type, an odd file name or a missing
## picture is ignored or clamped (SkinData.from_dict), never a crash. At most MAX_SKINS skins are kept.

const DEFAULT_DIR: String = "user://skins"
const ASSIGN_FILE: String = "assign.cfg"
const ASSIGN_SECTION: String = "assign"
const MAX_SKINS: int = 50
const MAX_SLOTS: int = 8
## Bigger files are not ours (a skin JSON is well under 1 KB).
const MAX_JSON_BYTES: int = 65536

## Where everything lives. Tests point this at a scratch folder.
static var dir: String = DEFAULT_DIR
## Headless runs (the test suite) must not read the developer's real skins: while `dir` is the
## default, skin_for_slot() answers "no skin" there unless a test turns this on.
static var allow_headless_default: bool = false


# --- ids and paths ------------------------------------------------------------------------

## Ids become file names, so only a small safe alphabet is accepted.
static func valid_id(skin_id: String) -> bool:
	if skin_id.is_empty() or skin_id.length() > 40:
		return false
	for ch: String in skin_id:
		var c: int = ch.unicode_at(0)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95 or c == 45
		if not ok:
			return false
	return true


static func new_id() -> String:
	var existing: PackedStringArray = list_ids()
	for _attempt: int in range(32):
		var candidate: String = "s%d_%04x" % [int(Time.get_unix_time_from_system()), randi() & 0xffff]
		if not existing.has(candidate):
			return candidate
	return "s%d_%08x" % [int(Time.get_ticks_usec()), randi()]


static func json_path(skin_id: String) -> String:
	return "%s/%s.json" % [dir, skin_id]


static func image_path(skin_id: String) -> String:
	return "%s/%s.png" % [dir, skin_id]


static func assign_path() -> String:
	return "%s/%s" % [dir, ASSIGN_FILE]


static func _ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(dir):
		return true
	return DirAccess.make_dir_recursive_absolute(dir) == OK


# --- skins --------------------------------------------------------------------------------

## Ids of the skins on disk, oldest first (ids start with their creation time).
static func list_ids() -> PackedStringArray:
	var out: Array[String] = []
	if not DirAccess.dir_exists_absolute(dir):
		return PackedStringArray()
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var skin_id: String = f.trim_suffix(".json")
			if valid_id(skin_id):
				out.append(skin_id)
	out.sort()
	return PackedStringArray(out)


static func count() -> int:
	return list_ids().size()


static func is_full() -> bool:
	return count() >= MAX_SKINS


## The readable skins, oldest first, at most MAX_SKINS (the first ones in that order, even when more
## files were copied in by hand). Unreadable files are skipped and do not use up a place.
static func list_skins(with_image: bool = true) -> Array[SkinData]:
	var out: Array[SkinData] = []
	for skin_id: String in list_ids():
		if out.size() >= MAX_SKINS:
			break
		var s: SkinData = load_skin(skin_id, with_image)
		if s != null:
			out.append(s)
	return out


## The skin with this id, or null when it is missing or its file is not a JSON object.
static func load_skin(skin_id: String, with_image: bool = true) -> SkinData:
	if not valid_id(skin_id) or not FileAccess.file_exists(json_path(skin_id)):
		return null
	var f: FileAccess = FileAccess.open(json_path(skin_id), FileAccess.READ)
	if f == null or f.get_length() > MAX_JSON_BYTES:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parser := JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return null
	var s: SkinData = SkinData.from_dict(parser.data as Dictionary, skin_id)
	if with_image and s.image_file != "":
		s.image = load_image(skin_id)
		if s.image == null:
			s.image_file = ""
	return s


## Writes the skin (and its picture, or removes the old one). A new skin is refused when MAX_SKINS
## already exist. Returns false on any problem; the old file stays untouched then.
static func save_skin(skin: SkinData) -> bool:
	if skin == null or not valid_id(skin.id):
		return false
	var is_new: bool = not FileAccess.file_exists(json_path(skin.id))
	if is_new and count() >= MAX_SKINS:
		return false
	if not _ensure_dir():
		return false
	skin.name = SkinData.clean_name(skin.name)
	if skin.image != null and not _write_image(skin):
		return false
	skin.image_file = (skin.id + ".png") if skin.image != null else ""
	if skin.image == null and FileAccess.file_exists(image_path(skin.id)):
		DirAccess.remove_absolute(image_path(skin.id))
	return _write_text(json_path(skin.id), JSON.stringify(skin.to_dict(), "\t"))


static func delete_skin(skin_id: String) -> void:
	if not valid_id(skin_id):
		return
	for p: String in [json_path(skin_id), image_path(skin_id)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for slot: int in slots_using(skin_id):
		unassign(slot)


## Saves a copy under a new id. Returns the copy, or null at the cap / on a write error.
static func duplicate_skin(skin_id: String, copy_name: String = "") -> SkinData:
	var src: SkinData = load_skin(skin_id)
	if src == null or is_full():
		return null
	var copy: SkinData = src.duplicate_skin(new_id(), copy_name if copy_name != "" else src.name)
	return copy if save_skin(copy) else null


static func load_image(skin_id: String) -> Image:
	if not valid_id(skin_id) or not FileAccess.file_exists(image_path(skin_id)):
		return null
	# SkinImage.decode looks at the first bytes before any decoder runs, so a damaged file is a quiet null.
	var img: Image = SkinImage.decode(FileAccess.get_file_as_bytes(image_path(skin_id)))
	if img == null:
		return null
	if img.get_width() != SkinData.IMAGE_W or img.get_height() != SkinData.IMAGE_H:
		img.resize(SkinData.IMAGE_W, SkinData.IMAGE_H, Image.INTERPOLATE_BILINEAR)
	return img


static func _write_image(skin: SkinData) -> bool:
	return skin.image.save_png(image_path(skin.id)) == OK


## Atomic: write a temporary file, then rename over the target.
static func _write_text(path: String, text: String) -> bool:
	var tmp: String = path + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


# --- assignments --------------------------------------------------------------------------

## Slot (0-based tank id) -> skin id. Slots out of range and ids that are not valid are dropped.
static func assignments() -> Dictionary:
	var out: Dictionary = {}
	var cfg := ConfigFile.new()
	if cfg.load(assign_path()) != OK:
		return out
	for slot: int in range(MAX_SLOTS):
		var v: Variant = cfg.get_value(ASSIGN_SECTION, "slot%d" % (slot + 1), "")
		if typeof(v) == TYPE_STRING and valid_id(v as String):
			out[slot] = v as String
	return out


static func assigned_id(slot: int) -> String:
	return str(assignments().get(slot, ""))


## Gives `slot` this skin. Returns false for a bad slot or a skin that does not exist.
static func assign(slot: int, skin_id: String) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or not valid_id(skin_id) or not FileAccess.file_exists(json_path(skin_id)):
		return false
	var a: Dictionary = assignments()
	a[slot] = skin_id
	return _write_assignments(a)


static func unassign(slot: int) -> void:
	var a: Dictionary = assignments()
	if a.erase(slot):
		_write_assignments(a)


static func slots_using(skin_id: String) -> Array[int]:
	var out: Array[int] = []
	var a: Dictionary = assignments()
	for slot: int in range(MAX_SLOTS):
		if a.get(slot, "") == skin_id:
			out.append(slot)
	return out


static func _write_assignments(a: Dictionary) -> bool:
	if not _ensure_dir():
		return false
	var cfg := ConfigFile.new()
	for slot: int in range(MAX_SLOTS):
		if a.has(slot):
			cfg.set_value(ASSIGN_SECTION, "slot%d" % (slot + 1), a[slot])
	return cfg.save(assign_path()) == OK


## The skin a Human tank in `slot` wears on this device, or null for the default look (nothing
## assigned, or the skin file is gone or unreadable).
static func skin_for_slot(slot: int) -> SkinData:
	if DisplayServer.get_name() == "headless" and dir == DEFAULT_DIR and not allow_headless_default:
		return null
	var skin_id: String = assigned_id(slot)
	return load_skin(skin_id) if skin_id != "" else null
