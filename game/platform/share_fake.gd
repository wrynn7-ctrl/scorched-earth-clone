class_name ShareFake
extends RefCounted
## Stands in for the CraterlineShare Android singleton (share sheet + deep links) in tests. Same method and signal
## names as android_plugins/share/.../CraterlineShare.kt, plus `simulate_*` helpers.

signal deep_link_received(url: String)

var share_result: bool = true
var last_title: String = ""
var last_text: String = ""
var share_calls: int = 0
var _pending_link: String = ""


func share_text(title: String, text: String) -> bool:
	share_calls += 1
	last_title = title
	last_text = text
	return share_result


func consume_pending_link() -> String:
	var url: String = _pending_link
	_pending_link = ""
	return url


## The game was started by a link (nobody is listening yet).
func simulate_launch_link(url: String) -> void:
	_pending_link = url


## A link arrives while the game is running.
func simulate_link(url: String) -> void:
	_pending_link = url
	deep_link_received.emit(url)
