// The whole path the Godot client takes, over plain REST: anonymous sign-in, callables, then database reads and writes with
// the ID token. It proves that the data the functions create is what the rules expect (seat arrays, turn markers) and that
// a multi-path PATCH works as the log append described in the README.
import assert from 'node:assert/strict';
import { db, eventually, hostLobby, newUser, value, type TestUser } from './harness';

const DB = `http://${process.env.FIREBASE_DATABASE_EMULATOR_HOST ?? '127.0.0.1:9000'}`;
const NS = 'demo-craterline-default-rtdb';
const HOUR = 3600 * 1000;

interface Rest {
  status: number;
  body: unknown;
}

async function rest(user: TestUser, method: 'GET' | 'PATCH' | 'PUT' | 'DELETE', path: string, body?: unknown): Promise<Rest> {
  const response = await fetch(`${DB}/${path}.json?ns=${NS}&auth=${encodeURIComponent(user.token)}`, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  return { status: response.status, body: text === '' ? null : (JSON.parse(text) as unknown) };
}

const ok = (r: Rest, what: string): void => assert.equal(r.status, 200, `${what}: ${r.status} ${JSON.stringify(r.body)}`);
const denied = (r: Rest, what: string): void => assert.equal(r.status, 401, `${what} should be refused, got ${r.status} ${JSON.stringify(r.body)}`);

describe('REST client flow (what M7-N will do)', () => {
  it('plays a match: lobby, start, resolve, shop, turns, CPU entries, concurrency, messages, end', async () => {
    const host = await newUser({ full: true, name: 'Hana' });
    const bob = await newUser({ name: 'Bob' });
    const { matchId, code } = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu', level: 2 }]);
    await bob.call('joinMatch', { code });
    await host.call('startMatch', { matchId });

    // Members read the match; an outsider cannot.
    const outsider = await newUser();
    const meta = await rest(host, 'GET', `matches/${matchId}/meta`);
    ok(meta, 'host reads meta');
    assert.equal((meta.body as { status: string }).status, 'playing');
    denied(await rest(outsider, 'GET', `matches/${matchId}/meta`), 'outsider reads meta');
    denied(await rest(host, 'GET', `matches/${matchId}`), 'whole-match read');

    // The host's client resolves "needs resolve": the CPU's shop visit, then the shop turn.
    const shop = { tank: -2, uid: 'any', deadline: Date.now() + HOUR, index: 1 };
    ok(
      await rest(host, 'PATCH', `matches/${matchId}`, { 'actions/0': { kind: 'auto_shop', tank: 2, level: 2 }, 'meta/actionCount': 1, 'meta/turn': shop }),
      'resolve into the shop',
    );

    // Shop: each player readies their own seat; the last ready also starts the first aim turn.
    ok(await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/1': { kind: 'ready', tank: 1 }, 'meta/actionCount': 2 }), 'bob ready');
    denied(await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/2': { kind: 'ready', tank: 0 }, 'meta/actionCount': 3 }), 'ready for another player');
    ok(
      await rest(host, 'PATCH', `matches/${matchId}`, {
        'actions/2': { kind: 'ready', tank: 0 },
        'meta/actionCount': 3,
        'meta/turn': { tank: 0, uid: host.uid, deadline: Date.now() + HOUR, liveDeadline: Date.now() + 60000, index: 2 },
      }),
      'host ready starts the round',
    );

    // Out of turn is refused; the holder's shot plus the CPU turn that follows go in one update.
    denied(await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/3': { kind: 'fire', tank: 1, angle: 900, power: 500, weapon: 'spark_dart' }, 'meta/actionCount': 4 }), 'bob out of turn');
    const shot = { kind: 'fire', tank: 0, angle: 452, power: 610, weapon: 'pulse_missile' };
    ok(
      await rest(host, 'PATCH', `matches/${matchId}`, {
        'actions/3': shot,
        'actions/4': { kind: 'auto', tank: 2, level: 2 },
        'meta/actionCount': 5,
        'meta/turn': { tank: 1, uid: bob.uid, deadline: Date.now() + HOUR, index: 3 },
      }),
      'shot and CPU turn',
    );

    // Concurrency: two clients race for index 5; exactly one wins.
    const bobShot = { kind: 'fire', tank: 1, angle: 1300, power: 700, weapon: 'spark_dart' };
    const winner = await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/5': bobShot, 'meta/actionCount': 6, 'meta/turn': { tank: 0, uid: host.uid, deadline: Date.now() + HOUR, index: 4 } });
    ok(winner, 'bob shoots');
    denied(await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/5': { ...bobShot, angle: 1, power: 1 }, 'meta/actionCount': 6 }), 'the same slot again');

    // Nobody can rewrite history.
    denied(await rest(host, 'PUT', `matches/${matchId}/actions/3`, { kind: 'pass', tank: 0 }), 'overwrite an entry');
    denied(await rest(host, 'DELETE', `matches/${matchId}/actions/3`), 'delete an entry');

    // Heartbeat, fingerprint, a quick message.
    ok(await rest(bob, 'PUT', `matches/${matchId}/presence/${bob.uid}`, { '.sv': 'timestamp' }), 'presence');
    const beat = (await rest(host, 'GET', `matches/${matchId}/presence/${bob.uid}`)).body as number;
    assert.ok(Math.abs(beat - Date.now()) < 60000, 'presence holds the server time');
    ok(await rest(host, 'PUT', `matches/${matchId}/fp/4/${host.uid}`, '0123456789abcdef'), 'fingerprint');
    ok(
      await rest(host, 'PATCH', `matches/${matchId}`, {
        'msgs/-Nrest0000000000001': { uid: host.uid, seat: 0, msg: 3, at: { '.sv': 'timestamp' } },
        [`lastMsg/${host.uid}`]: { '.sv': 'timestamp' },
        [`lastMsgKey/${host.uid}`]: '-Nrest0000000000001',
      }),
      'quick message',
    );
    denied(
      await rest(host, 'PATCH', `matches/${matchId}`, {
        'msgs/-Nrest0000000000002': { uid: host.uid, seat: 0, msg: 4, at: { '.sv': 'timestamp' } },
        [`lastMsg/${host.uid}`]: { '.sv': 'timestamp' },
        [`lastMsgKey/${host.uid}`]: '-Nrest0000000000002',
      }),
      'a second message within 3 s',
    );

    // The functions kept the lists in step while the turn moved.
    await eventually(async () => (await value(`userMatches/${host.uid}/${matchId}/yourTurn`)) === true, 'host flagged');
    // the trigger updates every member's entry in parallel, so bob's flag may trail the host's by a moment
    await eventually(async () => (await value(`userMatches/${bob.uid}/${matchId}/yourTurn`)) === false, 'bob not flagged');

    // The host's turn: the final shot ends the match.
    ok(
      await rest(host, 'PATCH', `matches/${matchId}`, { 'actions/6': shot, 'meta/actionCount': 7, 'meta/status': 'over' }),
      'last shot ends the match',
    );
    denied(await rest(bob, 'PATCH', `matches/${matchId}`, { 'actions/7': { kind: 'pass', tank: 1 }, 'meta/actionCount': 8 }), 'play after the end');
    await eventually(async () => (await value(`matchCodes/${code}`)) === null, 'code expired');
    // The code is expired before the lists are updated (two writes in one trigger), so wait for the list too.
    await eventually(async () => (await db.ref(`userMatches/${bob.uid}/${matchId}/status`).get()).val() === 'over', 'bob list shows over');
  });

  it('lets a client use its own data over REST: name, protocol, push token, lists, dismissals', async () => {
    const user = await newUser({ name: 'Zoe' });
    ok(await rest(user, 'PUT', `users/${user.uid}/name`, 'Zoe K'), 'rename');
    ok(await rest(user, 'PUT', `users/${user.uid}/protocol`, 2), 'protocol');
    ok(await rest(user, 'PUT', `users/${user.uid}/fcm/abcdefgh12345678`, 'tok'.repeat(20)), 'push token');
    denied(await rest(user, 'PUT', `users/${user.uid}/full`, true), 'grant yourself full');
    denied(await rest(user, 'PUT', `users/${user.uid}/nameHidden`, false), 'unhide yourself');
    const profile = await rest(user, 'GET', `users/${user.uid}`);
    ok(profile, 'read own profile');
    assert.equal((profile.body as { name: string }).name, 'Zoe K');
    for (const list of ['friends', 'friendRequests', 'blocks', 'invites', 'userMatches']) ok(await rest(user, 'GET', `${list}/${user.uid}`), `read own ${list}`);
    const friend = await newUser();
    denied(await rest(user, 'GET', `friends/${friend.uid}`), "read someone else's friends");
    ok(await rest(friend, 'GET', `users/${user.uid}/name`), "read someone else's name");
  });
});
