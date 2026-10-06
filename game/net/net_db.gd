class_name NetDb
extends RefCounted
## Realtime Database over REST (docs/ARCHITECTURE.md sections 45-47, firebase/README.md): get, put, patch (also the
## multi-path update the action log uses), delete, server timestamps, and streaming subscriptions.
##
## Every call adds `auth=<ID token>` (refreshed first when needed). An answer that says the token is bad is retried once
## after a forced refresh. Streams: see NetStream; one stream per subscribed path.

var config: NetConfig = null
var auth: NetAuth = null
var http: NetHttp = null
var _streams: Array[NetStream] = []


func _init(cfg: NetConfig, http_client: NetHttp, authentication: NetAuth) -> void:
	config = cfg
	http = http_client
	auth = authentication


## `{".sv": "timestamp"}`: the server fills in its clock (presence, quick messages).
static func server_timestamp() -> Dictionary:
	return {".sv": "timestamp"}


## Query parameters selecting the children whose key is >= `first_index` (keys are the log indexes, which the database
## orders numerically).
static func from_index(first_index: int) -> Dictionary:
	return {"orderBy": "\"$key\"", "startAt": "\"%d\"" % first_index}


## The most recent `n` children by key.
static func last_n(n: int) -> Dictionary:
	return {"orderBy": "\"$key\"", "limitToLast": str(n)}


## https://host/<path>.json?ns=..&auth=..&<params>. `params` values are used as given and percent-encoded here.
func url(path: String, params: Dictionary = {}, token: String = "") -> String:
	var parts: PackedStringArray = PackedStringArray()
	if config.database_namespace != "":
		parts.append("ns=" + config.database_namespace.uri_encode())
	if token != "":
		parts.append("auth=" + token.uri_encode())
	for k: Variant in params.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(params[k]).uri_encode()])
	var clean: String = path.trim_prefix("/").trim_suffix("/")
	return "%s/%s.json?%s" % [config.database_url, clean, "&".join(parts)]


func get_value(path: String, params: Dictionary = {}) -> NetResult:
	return await _call(HTTPClient.METHOD_GET, path, params, null)


func put(path: String, value: Variant) -> NetResult:
	return await _call(HTTPClient.METHOD_PUT, path, {}, value)


## Writes the given keys (which may be deep paths such as "actions/5") in one atomic update.
func patch(path: String, values: Dictionary) -> NetResult:
	return await _call(HTTPClient.METHOD_PATCH, path, {}, values)


func delete(path: String) -> NetResult:
	return await _call(HTTPClient.METHOD_DELETE, path, {}, null)


## Subscribes to `path`. `params` may be a Dictionary or a Callable returning one (evaluated at every reconnect, so a
## stream can resume "from index n"). The stream starts at once; free it with `stream.close()`.
func stream(path: String, params: Variant = {}, cache: bool = true) -> NetStream:
	var s := NetStream.new()
	s.setup(self, path, params, cache)
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	tree.root.add_child(s)
	_streams.append(s)
	s.tree_exited.connect(func() -> void: _streams.erase(s))
	s.start()
	return s


func close_all_streams() -> void:
	for s: NetStream in _streams.duplicate():
		if is_instance_valid(s):
			s.close()
	_streams.clear()


func stream_count() -> int:
	return _streams.size()


func _call(method: int, path: String, params: Dictionary, body: Variant) -> NetResult:
	var res: NetResult = null
	for attempt: int in range(2):
		var token: String = await auth.token()
		if token == "":
			return NetResult.failure(NetError.Code.SIGN_IN_REQUIRED, "no_token")
		res = await http.json_request(method, url(path, params, token), body)
		if res.ok or res.code != NetError.Code.SIGN_IN_REQUIRED or attempt > 0:
			break
		await auth.refresh()
	if not res.ok and res.code == NetError.Code.PERMISSION:
		res.reason = "permission_denied"
	return res
