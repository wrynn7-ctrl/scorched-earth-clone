class_name NetProtocol
extends RefCounted
## Constants every online client must agree on (docs/ARCHITECTURE.md sections 45 and 46, firebase/README.md).
##
## HOW TO BUMP `VERSION`
## Bump it (and add a line to HISTORY) in the same change as ANY of these:
##   * a rule of the simulation (game/core), a weapon or item number, terrain generation, wind or placement;
##   * the AI (game/ai): a decision, a shop purchase, a profile number;
##   * the log format or how NetReplay expands `auto`, `auto_shop` and `timeout`.
## A client refuses to join or play a match whose protocol differs (typed error PROTOCOL_MISMATCH), because the two
## phones would replay different games. `test_net_protocol_golden.gd` replays a fixed log and compares its fingerprint
## with a stored one: when that test fails you changed the game's behaviour, so bump VERSION and refresh the golden value
## printed by the failure message. Never bump it for UI, audio or other show-layer changes.
##
## HISTORY
##   1  first online release (M7).
const VERSION: int = 1

## Most log entries one database update may append (rules: MAX_BATCH in firebase/rules/build_rules.mjs).
const MAX_BATCH: int = 16
## Quick messages: how many presets exist (the rules accept 0..MSG_COUNT-1) and the minimum gap per player.
const MSG_COUNT: int = 8
const MSG_INTERVAL_MS: int = 3000
## A player is "online" when the last heartbeat is younger than this; the client writes one every HEARTBEAT_SEC.
const PRESENCE_FRESH_MS: int = 75000
const HEARTBEAT_SEC: float = 30.0
## Turn markers in `meta/turn.tank` (section 51).
const TURN_NEEDS_RESOLVE: int = -1
const TURN_SHOP: int = -2
## `meta/turn.uid` values that are not a player.
const UID_ANY: String = "any"
const UID_CPU: String = "cpu"
## The AI level that plays for a player who timed out in an async match (section 46).
const TIMEOUT_AI_LEVEL: int = SimConstants.CTRL_NORMAL
## Match status values in `meta/status`.
const STATUS_LOBBY: String = "lobby"
const STATUS_PLAYING: String = "playing"
const STATUS_OVER: String = "over"
const STATUS_ABANDONED: String = "abandoned"
## Longest a quick message or a name may be, mirrored from the rules.
const NAME_MAX: int = 12
