extends GutTest
## The game is called Charred Horizons (renamed from the working title). No text a player can see may still
## carry the old name. Internal identifiers (deep-link scheme, plugin singletons) are not user-visible and are
## covered by their own tests.

const OLD_NAME: String = "craterline"
const CSV: String = "res://locale/strings.csv"


func test_no_user_visible_string_contains_the_old_name() -> void:
	var f: FileAccess = FileAccess.open(CSV, FileAccess.READ)
	assert_not_null(f)
	var checked: int = 0
	var first: bool = true
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if first:
			first = false
			continue
		if row.size() < 2:
			continue
		checked += 1
		for cell: String in row:
			assert_false(cell.to_lower().contains(OLD_NAME), "%s still says the old name" % row[0])
	assert_gt(checked, 100, "the table was read")


func test_translated_strings_carry_the_new_name() -> void:
	assert_eq(tr("APP_TITLE"), "Charred Horizons")
	assert_eq(tr("TITLE_LOGO"), "CHARRED HORIZONS")
	assert_eq(tr("NET_SHARE_TITLE"), "Charred Horizons")
	assert_string_contains(tr("NET_SHARE_TEXT"), "Charred Horizons")
	assert_string_contains(tr("NET_SHARE_TEXT"), "{code}", "the code placeholder survives")
	assert_string_contains(tr("NET_UPDATE_TEXT"), "Charred Horizons")
	assert_string_contains(tr("NET_GATE_UPDATE_TEXT"), "Charred Horizons")
	assert_string_contains(tr("NET_SET_GOOGLE_TAKEN"), "Charred Horizons")


func test_translated_text_through_tr_has_no_old_name() -> void:
	var f: FileAccess = FileAccess.open(CSV, FileAccess.READ)
	var first: bool = true
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if first:
			first = false
			continue
		if row.size() >= 2 and row[0] != "":
			assert_false(tr(row[0]).to_lower().contains(OLD_NAME), "tr(%s)" % row[0])


func test_invite_text_from_the_template_names_the_new_game() -> void:
	var text: String = ShareService.invite_text(tr("NET_SHARE_TEXT"), "abc234")
	assert_string_contains(text, "Charred Horizons")
	assert_string_contains(text, "ABC234")
	assert_false(text.contains("{code}"))
