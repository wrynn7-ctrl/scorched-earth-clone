class_name NetClock
extends RefCounted
## Server-time estimate. The rules compare deadlines with the database's `now`, so deadlines must be written from the
## server's clock, not the phone's. `NetAccount.ensure_profile` feeds `sync_to` with the function's `serverTime`.

var offset_ms: int = 0
## Tests: when >= 0 the clock stands still at this value (ms, server time).
var fixed_ms: int = -1


static func local_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func now_ms() -> int:
	return fixed_ms if fixed_ms >= 0 else local_ms() + offset_ms


func sync_to(server_ms: int) -> void:
	offset_ms = server_ms - local_ms()
