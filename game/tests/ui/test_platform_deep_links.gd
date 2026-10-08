extends GutTest
## charredhorizons://join/CODE parsing, the code alphabet (section 45: no 0/O/1/I), and exactly-once delivery of links that
## start the game or arrive while it runs, using ShareFake in place of the Android plugin.

var _got: Array[String] = []


func before_each() -> void:
	_got.clear()


func _collect(code: String) -> void:
	_got.append(code)


# --- parsing --------------------------------------------------------------------------------

func test_valid_links() -> void:
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/ABC234"), "ABC234")
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/K7M2QX"), "K7M2QX")
	assert_eq(DeepLinks.parse_join_link("  charredhorizons://join/ABC234  "), "ABC234", "surrounding spaces are ignored")


func test_link_tolerances() -> void:
	assert_eq(DeepLinks.parse_join_link("CHARREDHORIZONS://JOIN/ABC234"), "ABC234", "scheme and host are case-insensitive")
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/abc234"), "ABC234", "a lower-case code is upper-cased")
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/ABC234/"), "ABC234", "trailing slash")
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/ABC234?utm=x"), "ABC234", "query ignored")
	assert_eq(DeepLinks.parse_join_link("charredhorizons://join/ABC234#frag"), "ABC234", "fragment ignored")


func test_invalid_links() -> void:
	var bad: Array[String] = [
		"",
		"   ",
		"charredhorizons://join/",
		"charredhorizons://join",
		"charredhorizons://join/ABC23",       # too short
		"charredhorizons://join/ABC2345",     # too long
		"charredhorizons://join/ABC 234",     # space inside
		"charredhorizons://join/ABC-234",
		"charredhorizons://join/ABC23O",      # O is not in the alphabet
		"charredhorizons://join/ABC231",      # 1 is not in the alphabet
		"charredhorizons://join/ABC230",      # 0 is not in the alphabet
		"charredhorizons://join/ABCI23",      # I is not in the alphabet
		"charredhorizons://join/ABC234/extra",
		"charredhorizons://join//ABC234",
		"charredhorizons://friend/ABC234",    # another host
		"charredhorizons:///join/ABC234",
		"charredhorizons:join/ABC234",
		"https://join/ABC234",
		"https://charredhorizons.example/join/ABC234",
		"charredhorizonsx://join/ABC234",
		"ABC234",
		"charredhorizons://join/ÄBC234",
		"charredhorizons://join/ABC234\u0000",
	]
	for url: String in bad:
		assert_eq(DeepLinks.parse_join_link(url), "", "rejected: %s" % url.c_escape())


func test_overlong_input_is_rejected_quickly() -> void:
	var long_url: String = "charredhorizons://join/" + "A".repeat(100000)
	assert_eq(DeepLinks.parse_join_link(long_url), "")


# --- alphabet and codes ---------------------------------------------------------------------

func test_alphabet_is_unambiguous() -> void:
	assert_eq(DeepLinks.CODE_ALPHABET.length(), 32)
	for c: String in ["0", "O", "1", "I"]:
		assert_eq(DeepLinks.CODE_ALPHABET.find(c), -1, "%s must not be in the alphabet" % c)
	for c: String in DeepLinks.CODE_ALPHABET.split(""):
		assert_eq(c, c.to_upper(), "alphabet is upper case")
	# every character is unique
	var seen: Dictionary = {}
	for c: String in DeepLinks.CODE_ALPHABET.split(""):
		assert_false(seen.has(c), "duplicate %s" % c)
		seen[c] = true


func test_normalize_code_for_typed_input() -> void:
	assert_eq(DeepLinks.normalize_code("abc234"), "ABC234")
	assert_eq(DeepLinks.normalize_code(" abc-234 "), "ABC234", "typed codes may carry spaces and hyphens")
	assert_eq(DeepLinks.normalize_code("ABC 234"), "ABC234")
	assert_eq(DeepLinks.normalize_code("ABC23"), "")
	assert_eq(DeepLinks.normalize_code("ABC23O"), "")
	assert_eq(DeepLinks.normalize_code(""), "")


func test_normalize_code_other_lengths() -> void:
	assert_eq(DeepLinks.normalize_code("abcd2345", 8), "ABCD2345", "friend codes have 8 characters")
	assert_eq(DeepLinks.normalize_code("ABC234", 8), "")


func test_is_valid_code() -> void:
	assert_true(DeepLinks.is_valid_code("ABC234"))
	assert_false(DeepLinks.is_valid_code("abc234"), "only the canonical upper-case form counts")
	assert_false(DeepLinks.is_valid_code("ABC 234"))
	assert_false(DeepLinks.is_valid_code(""))
	assert_true(DeepLinks.is_valid_code("ABCD2345", 8))


func test_build_join_link_round_trips() -> void:
	assert_eq(DeepLinks.build_join_link("abc234"), "charredhorizons://join/ABC234")
	assert_eq(DeepLinks.parse_join_link(DeepLinks.build_join_link("K7M2QX")), "K7M2QX")
	assert_eq(DeepLinks.build_join_link("ABC1"), "", "an invalid code makes no link")


# --- delivery -------------------------------------------------------------------------------

func test_unavailable_without_plugin_does_nothing() -> void:
	var links: DeepLinks = DeepLinks.new()
	links.start()
	assert_false(links.available, "no singleton on desktop")
	assert_eq(links.take_pending_code(), "")
	links.poll()
	assert_false(links.has_pending())


func test_launch_link_waits_for_a_handler() -> void:
	var fake: ShareFake = ShareFake.new()
	fake.simulate_launch_link("charredhorizons://join/ABC234")
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	assert_true(links.available)
	assert_true(links.has_pending())
	assert_eq(links.take_pending_code(), "ABC234")
	assert_eq(links.take_pending_code(), "", "delivered once")
	assert_eq(fake.consume_pending_link(), "", "the plugin's copy was consumed too")


func test_running_link_is_emitted_to_a_connected_handler_once() -> void:
	var fake: ShareFake = ShareFake.new()
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	links.join_requested.connect(_collect)
	fake.simulate_link("charredhorizons://join/ABC234")
	assert_eq(_got, ["ABC234"] as Array[String])
	assert_false(links.has_pending(), "a handled link does not wait in the slot")
	links.poll()
	assert_eq(_got.size(), 1, "polling does not deliver it again")


func test_running_link_without_handler_waits() -> void:
	var fake: ShareFake = ShareFake.new()
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	fake.simulate_link("charredhorizons://join/ABC234")
	assert_eq(links.take_pending_code(), "ABC234")


func test_junk_links_are_dropped() -> void:
	var fake: ShareFake = ShareFake.new()
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	links.join_requested.connect(_collect)
	fake.simulate_link("charredhorizons://join/NOPE")
	fake.simulate_link("charredhorizons://friend/ABC234")
	fake.simulate_link("")
	assert_eq(_got.size(), 0)
	assert_false(links.has_pending())


func test_later_link_replaces_an_unclaimed_one() -> void:
	var fake: ShareFake = ShareFake.new()
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	fake.simulate_link("charredhorizons://join/ABC234")
	fake.simulate_link("charredhorizons://join/K7M2QX")
	assert_eq(links.take_pending_code(), "K7M2QX", "the newest link wins")


func test_poll_picks_up_a_link_that_arrived_while_paused() -> void:
	var fake: ShareFake = ShareFake.new()
	var links: DeepLinks = DeepLinks.new(fake)
	links.start()
	fake.simulate_launch_link("charredhorizons://join/ABC234")  # kept by the plugin, no signal
	links.poll()
	assert_eq(links.take_pending_code(), "ABC234")
