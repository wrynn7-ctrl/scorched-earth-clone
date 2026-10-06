class_name NetJson
extends RefCounted
## JSON helpers for the REST layer. Godot's parser gives every number as a float; the simulation and the rules need ints,
## so everything that comes off the wire goes through `ints`.

const MAX_SAFE: int = 9007199254740992


## Parses `text`. Returns null for an empty text. `ok` (optional out via the returned Dictionary) is not needed:
## use `try_parse` when a parse failure must be told apart from a literal null.
static func parse(text: String) -> Variant:
	return try_parse(text)["value"]


## {ok: bool, value: Variant}. Whole-number floats become ints.
static func try_parse(text: String) -> Dictionary:
	if text.strip_edges() == "":
		return {"ok": true, "value": null}
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false, "value": null}
	return {"ok": true, "value": ints(parser.data)}


## Recursively turns whole-number floats (below 2^53, exactly representable) into ints.
static func ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v as float
			if is_finite(f) and f == floorf(f) and absf(f) < float(MAX_SAFE):
				return int(f)
			return v
		TYPE_DICTIONARY:
			var d: Dictionary = v as Dictionary
			var out: Dictionary = {}
			for k: Variant in d.keys():
				out[k] = ints(d[k])
			return out
		TYPE_ARRAY:
			var a: Array = v as Array
			var out_a: Array = []
			for item: Variant in a:
				out_a.append(ints(item))
			return out_a
	return v


static func stringify(v: Variant) -> String:
	return JSON.stringify(v)


## RTDB returns a list when the keys are 0..n-1 (and a Dictionary with string keys otherwise, for instance when some
## entries are missing). This gives a Dictionary int index -> value either way (nulls skipped).
static func indexed(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) == TYPE_ARRAY:
		var a: Array = v as Array
		for i: int in range(a.size()):
			if a[i] != null:
				out[i] = a[i]
	elif typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v as Dictionary
		for k: Variant in d.keys():
			var key: String = str(k)
			if key.is_valid_int() and d[k] != null:
				out[key.to_int()] = d[k]
	return out


## A list view of an RTDB "array" (see `indexed`), in index order, holes skipped.
static func as_list(v: Variant) -> Array:
	var idx: Dictionary = indexed(v)
	var keys: Array = idx.keys()
	keys.sort()
	var out: Array = []
	for k: Variant in keys:
		out.append(idx[k])
	return out
