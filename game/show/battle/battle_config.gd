class_name BattleConfig
extends RefCounted
## Hand-off from the title/setup screens (or a test) to the battle scene. A seed of 0 means
## "pick a random one": the seed is only an *input* to the deterministic simulation, so it may
## come from the system clock here in the show layer.

const ROUND_CHOICES: Array[int] = [1, 3, 5, 10, 20]

static var rounds: int = 3
static var seed_value: int = 0
## Test mode: timelines are applied immediately, without animation or waiting.
static var instant: bool = false
## Settings chosen on the setup screen. null = use the quick defaults (2 players).
static var settings: MatchSettings = null
## True when the battle should restore the autosave instead of starting a new match.
static var resume: bool = false
## Where autosaves go. Tests point this at a scratch file; "" disables autosaving.
static var autosave_path: String = SaveStore.AUTOSAVE_PATH


static func reset() -> void:
	rounds = 3
	seed_value = 0
	instant = false
	settings = null
	resume = false
	autosave_path = SaveStore.AUTOSAVE_PATH
