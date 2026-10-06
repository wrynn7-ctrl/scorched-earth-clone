extends SceneTree
## Writes the set of characters the game's NameFilter keeps (the ones its font can draw) as inclusive code point ranges, so the
## server filter (firebase/functions/src/name_filter.ts) deletes exactly the same characters. Run it through
## tools/firebase/gen_name_glyphs.sh; the path of the JSON file to write comes after `--`.
## Only the Basic Multilingual Plane is asked: NameFilter drops everything above U+FFFF without looking at the font.

const FIRST: int = 0
const LAST: int = 0xFFFF


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] == "":
		printerr("usage: godot --headless --path game -s tools/firebase/gen_name_glyphs.gd -- <output.json>")
		quit(2)
		return
	var ranges: Array = []
	var start: int = -1
	for code: int in range(FIRST, LAST + 2):
		var ok: bool = code <= LAST and NameFilter._drawable_uncached(code)
		if ok and start < 0:
			start = code
		elif not ok and start >= 0:
			ranges.append([start, code - 1])
			start = -1
	if ranges.is_empty() or (ranges[0] as Array)[0] != 0x20:
		printerr("the font did not load, or it has no basic letters: refusing to write a table")
		quit(1)
		return
	# One range per line keeps diffs readable.
	var lines: PackedStringArray = PackedStringArray()
	for r: Variant in ranges:
		lines.append("    [%d, %d]" % [(r as Array)[0], (r as Array)[1]])
	var text: String = "{\n  \"font\": \"%s\",\n  \"ranges\": [\n%s\n  ]\n}\n" % [NameFilter.FONT_PATH, ",\n".join(lines)]
	var f: FileAccess = FileAccess.open(args[0], FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % args[0])
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("wrote %d ranges to %s" % [ranges.size(), args[0]])
	quit(0)
