extends GutTest
## ShareService: invite text, the share sheet through ShareFake, and the clipboard fallback.

const TEMPLATE: String = "Join my Charred Horizons match: {code}\n{link}"


func test_invite_text_fills_code_and_link() -> void:
	assert_eq(ShareService.invite_text(TEMPLATE, "abc234"), "Join my Charred Horizons match: ABC234\ncharredhorizons://join/ABC234")
	assert_eq(ShareService.invite_text("Code {code}", "K7M2QX"), "Code K7M2QX")
	assert_eq(ShareService.invite_text("{link}", "K7M2QX"), "charredhorizons://join/K7M2QX")


func test_invite_text_refuses_bad_codes() -> void:
	assert_eq(ShareService.invite_text(TEMPLATE, ""), "")
	assert_eq(ShareService.invite_text(TEMPLATE, "ABC10O"), "")
	assert_eq(ShareService.invite_text(TEMPLATE, "ABC23"), "")


func test_no_plugin_means_unavailable_and_false() -> void:
	var share: ShareService = ShareService.new()
	assert_false(share.available)
	assert_false(share.share_text("t", "hello"))


func test_share_text_goes_to_the_plugin() -> void:
	var fake: ShareFake = ShareFake.new()
	var share: ShareService = ShareService.new(fake)
	assert_true(share.available)
	assert_true(share.share_text("Invite", "hello"))
	assert_eq(fake.last_title, "Invite")
	assert_eq(fake.last_text, "hello")


func test_empty_text_is_never_shared() -> void:
	var fake: ShareFake = ShareFake.new()
	var share: ShareService = ShareService.new(fake)
	assert_false(share.share_text("Invite", "   "))
	assert_eq(fake.share_calls, 0)
	assert_eq(share.share_or_copy("Invite", ""), ShareService.Result.FAILED)


func test_share_invite_result_codes() -> void:
	var fake: ShareFake = ShareFake.new()
	var share: ShareService = ShareService.new(fake)
	assert_eq(share.share_invite("Invite", TEMPLATE, "abc234"), ShareService.Result.SHARED)
	assert_eq(fake.last_text, "Join my Charred Horizons match: ABC234\ncharredhorizons://join/ABC234")
	assert_eq(share.share_invite("Invite", TEMPLATE, "bad"), ShareService.Result.FAILED, "invalid code: nothing shared")
	assert_eq(fake.share_calls, 1)


func test_falls_back_to_the_clipboard_when_the_sheet_fails() -> void:
	var fake: ShareFake = ShareFake.new()
	fake.share_result = false
	var share: ShareService = ShareService.new(fake)
	assert_eq(share.share_or_copy("Invite", "copy me"), ShareService.Result.COPIED)
	var plain: ShareService = ShareService.new()
	assert_eq(plain.share_or_copy("Invite", "copy me too"), ShareService.Result.COPIED, "desktop: clipboard")
