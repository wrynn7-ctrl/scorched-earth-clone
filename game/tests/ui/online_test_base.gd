class_name OnlineTestBase
extends GutTest
## Shared set-up of the online UI tests: scratch settings, no real scene changes, a free (not full) player by default,
## and a clean OnlineHub. Subclasses call `super.before_each()` / `super.after_each()` when they override them.

const PREFS: String = "user://test_online_prefs.cfg"


func before_each() -> void:
	OnlineHub.reset()
	OnlineHub.intercept_navigation = true
	SettingsStore.path = PREFS
	SettingsStore.delete()
	SettingsStore.love_found = false
	SettingsStore.online_named = true
	SettingsStore.online_muted = PackedStringArray()
	ShotArgs.love_found = false
	UiScale.reset_overrides()
	ShowSettings.reset()
	Entitlement.reset_for_tests(false)
	AudioDirector.reset_for_tests()
	PlayerNames.reset()
	PlayerLooks.reset()


func after_each() -> void:
	OnlineHub.reset()
	SettingsStore.delete()
	SettingsStore.path = SettingsStore.DEFAULT_PATH
	SettingsStore.love_found = false
	SettingsStore.online_named = false
	SettingsStore.online_muted = PackedStringArray()
	ShowSettings.reset()
	UiScale.reset_overrides()
	Entitlement.forget_for_tests()
	AudioDirector.reset_for_tests()
	PlayerNames.reset()
	PlayerLooks.reset()


## A phone-sized screen (2340x1080 at 500 dpi) for layout-sensitive checks.
func phone() -> void:
	UiScale.dpi_override = 500.0
	UiScale.window_px_override = Vector2(2340.0, 1080.0)


## A tablet (2048x1536 at 264 dpi).
func tablet() -> void:
	UiScale.dpi_override = 264.0
	UiScale.window_px_override = Vector2(2048.0, 1536.0)


func settle(frames: int = 3) -> void:
	await wait_process_frames(frames)
