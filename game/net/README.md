# game/net: the online client (M7-N)

Pure GDScript over `HTTPRequest` and `HTTPClient` (no native Firebase SDK). Talks to the backend in `firebase/`
(contract: `docs/ARCHITECTURE.md` sections 43 to 51, `firebase/README.md`). Default target: the local Firebase emulators.
Nothing in here has UI text; failures are typed codes, the UI maps them to `tr()` strings.

## The one object to hold: `NetSession`

```gdscript
var net := NetSession.create()                       # NetConfig.current(); sign-in kept in user://net_auth.cfg
var r: NetResult = await net.start()                 # anonymous sign-in (or restore) + ensureProfile
if not r.ok: ...                                     # r.code (NetError.Code), r.reason, r.details
await net.account.set_name("Hana")
var m: NetResult = await net.open_match(match_id)    # m.value is an OnlineMatch
net.close()                                          # closes streams and matches (stays signed in)
```

Every async call returns a `NetResult`: `ok`, `value` (Variant; `.dict()` / `.list()` helpers), `code`, `reason`,
`details`, `http_status`, `is_code(c)`, `is_transient()`. Nothing throws.

Parts: `net.account`, `net.friends`, `net.lobby`, `net.matches`, `net.db`, `net.functions`, `net.auth`, `net.clock`.

### Error codes (`NetError.Code`)

| Code | Meaning / what the UI does |
|---|---|
| `OFFLINE`, `TIMEOUT`, `SERVER` | no network / slow / server trouble: "Reconnecting", retry later (`is_transient()`) |
| `SIGN_IN_REQUIRED` | no valid account (rare: the session refreshes tokens itself) |
| `PERMISSION` | refused. `reason`: `full_required` (show the Unlock screen), `not_host`, `not_friends`, `not_a_member`, `permission_denied` (rules) |
| `NOT_FOUND` | `unknown_code` (also for a blocked pair), `unknown_match`, `unknown_user`, `no_request` |
| `INVALID` | bad input: `bad_code`, `bad_seats`, `bad_timers`, `bad_teams`, ... |
| `PRECONDITION` | `not_in_lobby`, `seats_not_filled`, `not_joinable`, `own_code`, `google_already_linked`, ... |
| `ALREADY_EXISTS` | `already_friends`, `already_in_match`, `token_used` |
| `EXHAUSTED` | `match_full`, `not_enough_seats`, `too_many_matches`, `too_many_requests` |
| `PROTOCOL_MISMATCH` | different game version. `details = {hostProtocol, yourProtocol}`: "Please update the game" |
| `NAME_REJECTED` | NameFilter refused (`reason` `empty` or `blocked`); nothing was sent |
| `RATE_LIMITED` | quick message inside 3 s |
| `ILLEGAL_ACTION` | the simulation refuses; `reason` is its key (`not_your_turn`, `bad_phase`, ...) or `not_your_seat` |
| `STALE` | legal when chosen, not any more after catching up; `contention` after 4 refused writes |
| `DISPUTED` | the match is disputed, play has stopped |
| `CLOSED`, `NOT_STARTED`, `UNAVAILABLE`, `CANCELLED`, `BAD_RESPONSE` | closed object / still a lobby / Google or push not available (`reason`: `unavailable`, `config`, `no_account`, `anonymous_disabled`, `not_configured`) / player backed out / malformed answer |

Backend reasons are passed through unchanged in `reason` (full list: `firebase/README.md`).

## Account (`net.account`)

`ensure_profile()` (called by `start()`), `profile` (`friendCode, name, nameHidden, full, protocol, serverTime`),
`friend_code()`, `is_full()`, `my_name()`, `set_name(raw)`, `refresh_profile()`, `fetch_public(uid)` ->
`{uid, name, hidden, display}` (hidden names read `PLAYER AB12`), `NetAccount.public_name(name, hidden, uid)`,
`verify_purchase(token)`, `delete_my_data()` (signs out afterwards; `profile_changed` signal),
`bind_push(PushService)` / `register_push_token(token)` (key = first 32 hex of SHA-256),
`link_google(GoogleSignIn)` (CANCELLED is not an error to show; `google_already_linked` -> offer `restore_with_google`),
`restore_with_google(GoogleSignIn)` (new phone; the uid changes, call `ensure_profile` after).
`net.auth`: `uid`, `anonymous`, `email`, `sign_out()`, signals `signed_in`, `signed_out`, `account_replaced`.

## Friends (`net.friends`)

`send_request(code)` -> `{status: "sent"|"friends", name}`, `respond(from_uid, accept)`, `remove_friend(uid)`,
`block(uid)`, `unblock(uid)`, `report(uid)`, `list_friends()` `[{uid, name, display, since}]`, `list_requests()`
`[{uid, name, at}]`, `list_blocks()`, `list_invites()` `[{matchId, fromUid, fromName, at, code, mode}]`,
`dismiss_invite(matchId)`, `NetFriends.visible_invites(list, love_found)` (hides Love invites without the Love
Edition). `watch()` / `unwatch()` keep `friends`, `requests`, `invites` current: signals `friends_changed`,
`requests_changed`, `invites_changed`.

## Lobby (`net.lobby`) and "Your matches" (`net.matches`)

```gdscript
var made := await net.lobby.create(NetLobby.settings({"rounds": 3}),
        [NetLobby.seat_human(true), NetLobby.seat_human(), NetLobby.seat_cpu(2)], NetLobby.timers(60, 72, "auto"))
net.lobby.watch(match_id)              # lobby_changed(meta), lobby_started(meta), lobby_abandoned(meta)
await net.lobby.invite(friend_uid, match_id)
await net.lobby.update(match_id, settings, seats, timers)   # host, lobby only
await net.lobby.start(match_id)        # host; then net.open_match(match_id)
var joined := await net.lobby.join("abc234", 1)             # seat_count > 1 = shared phone; value {matchId, seats, alreadyJoined}
await net.lobby.leave(match_id)
```

Settings keys: `rounds, wind_max, start_money, mode (0 standard, 1 Love), teams, friendly_fire, theme`. Timers:
`liveSec` (0 or 10..600), `asyncHours`, `asyncTimeout` (`auto` | `end`). `net.matches.watch()` -> `changed(list)` with
`[{matchId, updated, yourTurn, status, hostName}]` sorted (your turn, waiting, lobbies, finished); `refresh()`,
`dismiss(matchId)`.

## Playing: `OnlineMatch`

`var om: OnlineMatch = (await net.open_match(id)).value`, `om.close()` when leaving the match screen.

State: `om.state` (the authoritative `MatchState`, only this class mutates it), `om.fork_state()` (a copy for previews
and the shop), `om.my_seats` (several = shared phone), `om.seats()`, `om.seat_name(tank)`, `om.status`
(`playing|over|abandoned`), `om.turn_info()`, `om.is_my_turn()`, `om.live_seconds_left()`, `om.now_ms()` (server time),
`om.is_online(uid)`, `om.connection` (`LIVE|RECONNECTING|OFFLINE|CLOSED`), `om.is_disputed()`, `om.replay`.

`turn_info()` = `{tank, uid, deadline, liveDeadline?, index, mine, shop, resolving, cpu, name}`. `shop` is the shop phase
(tank -2; `mine` while one of my seats is not ready). `resolving` is a CPU turn or "needs resolve" that some member's
client is writing right now (show "..." and wait).

Acting:
- `await om.submit(action)` where `action` is a normal core action Dictionary for one of `my_seats` (`fire`, `move`,
  `use_item`, `pass`, `buy`, `sell`, `ready`). It simulates, writes your entry plus the CPU entries that follow plus the new
  turn in one update, retries after a lost race, and returns `NetResult` (`value = {index, entries}`).
- `await om.submit_many([...])`: several shop actions (buy, sell, ready) in one update; an aim action goes alone. Use it to
  send a whole shop visit on READY.
- `wait_online_sec` (2nd argument, default 0) keeps retrying while offline for that long ("actions queued").
- `await om.send_message(index, seat)` quick message 0..7 (3 s limit, `RATE_LIMITED`).
- `await om.abandon()` host only.

Signals: `entry_applied(index, result)` (every log entry in order; `result.steps = [{action, events}]` is the timeline,
`result.events` all events, `result.catch_up` true while replaying history after open or reconnect (skip animations),
`result.by_me`, `result.turn_ended`, `result.fingerprint`), `turn_changed(turn_info)`, `status_changed(status)`,
`presence_changed(uid, online)`, `message_received(seat, msg, uid)`, `seats_changed(seats)` (a player left: their
seat is now CPU Normal), `connection_changed(c)`, `disputed(reason, index)` (stop; host may `abandon()`), `failed(code,
reason)`, `opened`, `closed`.

Integration hint for the battle screen: build it on `om.state`, feed `entry_applied` steps to the playback, send local
input through `om.submit`, never call `Simulation.apply_action` on `om.state` yourself.

## How it works (so the UI folks know what to expect)

- A match is meta (settings, seed, seats, timers) plus an append-only log. `NetReplay` (pure) applies entries through the
  real `Simulation`: real actions as they are, and the markers `auto` (AiPlayer plays the turn), `auto_shop` (CPU shop
  visit) and `timeout` expanded exactly like the offline game does it. `start_round` is automatic when the shop is all ready.
  Tests prove equal fingerprints against the offline `MatchSession` path.
- `timeout` entries are `{kind: "timeout", tank, async?: 1}` (ARCHITECTURE section 52). With `async: 1` (written after the
  hard deadline by the sweep or a client) the AI plays the turn at level 2 (in the shop it buys and readies), or the match
  ends when `asyncTimeout` is `end`. Without it it is a live skip: the player passes (in the shop: ready). The rules allow a
  live skip only after `liveDeadline` while the holder's heartbeat is fresh, and `async: 1` only after `deadline`.
- Writers: any member resolves "needs resolve" turns and continues CPU turns left by a full batch (staggered by seat so
  they do not all race), and writes `timeout` entries after a deadline. Deadlines come from the server clock.
- Disputed: an entry the simulation refuses, an `auto` for a human seat, history that changed, a stored turn that
  disagrees with the simulation for more than 2.5 s, or a fingerprint reported by another player that differs.
- Streams (SSE over `HTTPClient`): meta, actions (from the next index), fp, msgs and one presence stream per other
  human. They reconnect with backoff, the database resends the current data, and replay applies it by index.

## Config

`NetConfig.current()`: emulator unless `NetConfig.USE_PRODUCTION` is true or `CRATERLINE_NET=production`. Emulator hosts:
`CRATERLINE_EMULATOR_HOST` (for a phone, the PC's LAN address) or the `FIREBASE_*_EMULATOR_HOST` variables.
Production values: constants at the top of `net_config.gd` marked OWNER / LEAD (project id, API key, database URL, web
client id). `NetProtocol.VERSION`: bump when simulation, AI or the log format changes (see the comment there and
`tests/net/test_net_protocol_golden.gd`, which fails when behaviour changed).

## Tests

`tools/run_tests.sh --suite net` starts the emulators (`tools/firebase/with_emulators.sh`, Java 21 + Node 22), sets
`CRATERLINE_NET_EMULATOR=1` and runs `game/tests/net`: unit tests (no emulator) and `test_it_*.gd` integration tests
with several simulated phones (one `NetSession` each) in one Godot process. Without the variable the integration tests
report "pending". Test-only hooks on `OnlineMatch`: `debug_deadline_offset_ms`, `debug_live_offset_ms`,
`debug_drop_streams(hold_sec)`, `heartbeat_interval_ms`.
