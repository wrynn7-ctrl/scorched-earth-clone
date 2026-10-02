class_name BattleConfig
extends RefCounted
## Hand-off from the title screen (or a test) to the battle scene. A seed of 0 means "pick a
## random one": the seed is only an *input* to the deterministic simulation, so it may come
## from the system clock here in the show layer.

const ROUND_CHOICES: Array[int] = [1, 3, 5]

static var rounds: int = 3
static var seed_value: int = 0
## Test mode: timelines are applied immediately, without animation or waiting.
static var instant: bool = false


static func reset() -> void:
	rounds = 3
	seed_value = 0
	instant = false
