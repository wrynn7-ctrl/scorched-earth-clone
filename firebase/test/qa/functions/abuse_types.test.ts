// M7-Q functions abuse, part 1: wrong types, missing fields, huge and odd strings, path-injection ids and non-standard
// request bodies against EVERY callable. A callable must answer with a clean client-class error (or work); an INTERNAL,
// UNKNOWN or non-JSON answer means unvalidated input reached code that threw.
import assert from 'node:assert/strict';
import { befriend, hostLobby } from '../../functions/harness';
import { callWith } from '../../functions/harness';
import { inParallel, newUser, outcome, rawCall, reasonOf, rest, unsignedToken, type TestUser } from './qa_harness';

const CLEAN = new Set(['OK', 'INVALID_ARGUMENT', 'NOT_FOUND', 'PERMISSION_DENIED', 'FAILED_PRECONDITION', 'ALREADY_EXISTS', 'RESOURCE_EXHAUSTED', 'UNAUTHENTICATED']);

function deepObject(depth: number): unknown {
  let node: unknown = { leaf: 1 };
  for (let i = 0; i < depth; i += 1) node = { a: node };
  return node;
}

const JUNK: [string, unknown][] = [
  ['null', null],
  ['true', true],
  ['false', false],
  ['zero', 0],
  ['negative', -1],
  ['fraction', 1.5],
  ['huge number', 1e308],
  ['2^53', 2 ** 53],
  ['empty string', ''],
  ['space', ' '],
  ['10k string', 'x'.repeat(10000)],
  ['fullwidth', 'ＡＢＣＤ１２３４'],
  ['emoji', '😀😀😀😀'],
  ['NUL', 'a\u0000b'],
  ['bidi override', '‮evil'],
  ['path', '../users/x'],
  ['slash', 'a/b'],
  ['json text', '{"a":1}'],
  ['empty array', []],
  ['array of null', [null]],
  ['nested arrays', [[[[]]]]],
  ['empty object', {}],
  ['object', { a: { b: { c: 1 } } }],
  ['deep object', deepObject(300)],
  ['constructor', 'constructor'],
  ['__proto__ object', JSON.parse('{"__proto__":{"polluted":true},"x":1}') as unknown],
];

// A representative subset for the per-field matrix (the full list runs against `data` itself and the nested fields).
const PER_FIELD: [string, unknown][] = JUNK.filter(([label]) => ['null', 'true', 'fraction', 'huge number', 'empty string', '10k string', 'emoji', 'NUL', 'path', 'array of null', 'object', 'deep object', '__proto__ object'].includes(label));

describe('QA functions: wrong types and odd strings on every callable', function () {
  this.timeout(300000);
  let me: TestUser;
  let friend: TestUser;
  let lobby: { matchId: string; code: string };

  before(async () => {
    me = await newUser({ full: true, name: 'Qa Me' });
    friend = await newUser({ name: 'Qa Friend' });
    await befriend(me, friend);
    lobby = await hostLobby(me, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'cpu' }]);
  });

  // [callable, base arguments (valid or near valid)]
  const calls = (): [string, Record<string, unknown>][] => [
    ['ensureProfile', { protocol: 1 }],
    ['sendFriendRequest', { code: 'ABCDEFGH' }],
    ['sendFriendRequestToUid', { targetUid: friend.uid, matchId: lobby.matchId }],
    ['respondFriendRequest', { fromUid: friend.uid, accept: true }],
    ['removeFriend', { friendUid: 'nobody123' }],
    ['block', { targetUid: 'nobody123' }],
    ['unblock', { targetUid: 'nobody123' }],
    ['reportName', { targetUid: friend.uid, reason: 'offensive_name' }],
    ['createMatch', { settings: { rounds: 1 }, seats: [{ kind: 'human' }, { kind: 'cpu' }], timers: { liveSec: 60 } }],
    ['updateLobby', { matchId: lobby.matchId, settings: { rounds: 2 }, seats: [{ kind: 'human', uid: me.uid }, { kind: 'human' }, { kind: 'cpu' }], timers: { liveSec: 30 } }],
    ['joinMatch', { code: 'ABCDEF', seatCount: 1, names: ['A'] }],
    ['leaveMatch', { matchId: 'nonexistent' }],
    ['startMatch', { matchId: lobby.matchId }],
    ['invite', { friendUid: friend.uid, matchId: lobby.matchId }],
    ['verifyPurchase', { purchaseToken: 'junk-token' }],
  ];

  it('answers every junk value in every field with a clean error (or success), never INTERNAL', async () => {
    const bad: string[] = [];
    let n = 0;
    for (const [name, base] of calls()) {
      for (const field of Object.keys(base)) {
        for (const [label, junk] of PER_FIELD) {
          n += 1;
          const got = await outcome(me.call(name, { ...base, [field]: junk }));
          if (!CLEAN.has(got)) bad.push(`${name}.${field}=${label}: ${got}`);
        }
        const without = { ...base };
        delete without[field];
        n += 1;
        const got = await outcome(me.call(name, without));
        if (!CLEAN.has(got)) bad.push(`${name} without ${field}: ${got}`);
      }
    }
    console.log(`      ${n} junk calls`);
    assert.deepEqual(bad, []);
  });

  it('answers a junk top-level `data` (not an object) cleanly', async () => {
    const bad: string[] = [];
    for (const [name] of calls()) {
      for (const [label, junk] of JUNK.slice(0, 26)) {
        const got = await outcome(me.call(name, junk));
        if (!CLEAN.has(got)) bad.push(`${name}(${label}): ${got}`);
      }
    }
    assert.deepEqual(bad, []);
  });

  it('answers junk inside createMatch / updateLobby seats, settings and timers cleanly', async () => {
    const bad: string[] = [];
    const seatFields = ['kind', 'level', 'name', 'mine', 'uid'];
    for (const [label, junk] of JUNK) {
      for (const field of seatFields) {
        const seats = [{ kind: 'human', mine: true, [field]: junk }, { kind: 'cpu', level: 2, [field]: junk }];
        for (const run of [() => me.call('createMatch', { settings: { rounds: 1 }, seats }), () => me.call('updateLobby', { matchId: lobby.matchId, seats })]) {
          const got = await outcome(run());
          if (!CLEAN.has(got)) bad.push(`seat.${field}=${label}: ${got}`);
        }
      }
      for (const field of ['rounds', 'wind_max', 'start_money', 'mode', 'teams', 'friendly_fire', 'theme', 'num_tanks', 'seed', 'controllers', 'full_unlocked']) {
        const settings = { rounds: 1, [field]: junk };
        for (const run of [() => me.call('createMatch', { settings, seats: [{ kind: 'human' }, { kind: 'cpu' }] }), () => me.call('updateLobby', { matchId: lobby.matchId, settings })]) {
          const got = await outcome(run());
          if (!CLEAN.has(got)) bad.push(`settings.${field}=${label}: ${got}`);
        }
      }
      for (const field of ['liveSec', 'asyncHours', 'asyncTimeout']) {
        const got = await outcome(me.call('createMatch', { settings: {}, seats: [{ kind: 'human' }, { kind: 'cpu' }], timers: { [field]: junk } }));
        if (!CLEAN.has(got)) bad.push(`timers.${field}=${label}: ${got}`);
      }
    }
    assert.deepEqual(bad, []);
  });

  it('refuses ids that could address another database path, for every id field', async () => {
    const evil = ['../users/x', 'a/b', 'a.b', 'a$b', 'a#b', 'a[0]', 'a b', 'ü', ' ', 'x'.repeat(129), '\n', '%2e%2e', 'a\\b'];
    const idFields: [string, string][] = [
      ['sendFriendRequestToUid', 'targetUid'],
      ['sendFriendRequestToUid', 'matchId'],
      ['respondFriendRequest', 'fromUid'],
      ['removeFriend', 'friendUid'],
      ['block', 'targetUid'],
      ['unblock', 'targetUid'],
      ['reportName', 'targetUid'],
      ['updateLobby', 'matchId'],
      ['leaveMatch', 'matchId'],
      ['startMatch', 'matchId'],
      ['invite', 'matchId'],
      ['invite', 'friendUid'],
    ];
    const base = new Map(calls());
    const accepted: string[] = [];
    for (const [name, field] of idFields) {
      for (const id of evil) {
        const got = await reasonOf(me.call(name, { ...(base.get(name) as Record<string, unknown>), accept: true, [field]: id }));
        if (!got.startsWith('INVALID_ARGUMENT')) accepted.push(`${name}.${field}=${JSON.stringify(id)}: ${got}`);
      }
    }
    assert.deepEqual(accepted, []);
    // and nothing was written under a path the id could have escaped to
    const probe = await rest(null, 'GET', 'users');
    assert.notEqual(probe.status, 200); // the database stays closed to anonymous reads
  });

  // FIXED (was a medium bug): the id "__proto__" hung updateLobby and startMatch for the whole function timeout (60 s).
  //   input:    any signed-in account with a profile: startMatch {matchId: "__proto__"} (same for updateLobby)
  //   expected: INVALID_ARGUMENT / NOT_FOUND `unknown_match` within a second or two, like any other unknown id
  //             ("constructor" or "nonexistent" answer NOT_FOUND at once).
  //   actual:   no answer until the emulator kills it: "Your function timed out after ~60s" (probe: 60008 ms, and the call is
  //             reported as a success by the callable layer). In production every such call keeps an instance busy for 60 s and
  //             is billed; maxInstances 10 per function, so a handful of calls from one anonymous account stall startMatch.
  //   cause:    functions/src/errors.ts reqId() accepts any [A-Za-z0-9_-]+ id, so matches.ts mutateMeta() runs
  //             `ref("matches/__proto__/meta").transaction(...)`; the Admin SDK's path tree is a plain object and "__proto__" is
  //             not a normal key there (matches.ts:~85 mutateMeta, called from startMatch:~330 and updateLobby:~215).
  //   fix idea: check `exists(matches/{id}/meta)` before the transaction, and/or reject ids starting with "__" in reqId().
  it('answers the id __proto__ quickly instead of hanging until the function timeout', async () => {
    for (const name of ['startMatch', 'updateLobby']) {
      const started = Date.now();
      const got = await Promise.race([reasonOf(me.call(name, { matchId: '__proto__' })), new Promise<string>((resolve) => setTimeout(() => resolve('HUNG'), 8000))]);
      assert.notEqual(got, 'HUNG', `${name} did not answer in 8 s`);
      assert.ok(Date.now() - started < 8000);
      assert.match(got, /^(INVALID_ARGUMENT|NOT_FOUND)/);
    }
  });

  it('rejects tokens that are not a JWT at all, for callables and for the database', async () => {
    for (const junk of ['not.a.token', 'x', '', 'Bearer', 'a.b.c', `${'A'.repeat(5000)}.${'B'.repeat(5000)}.C`]) {
      if (junk === '') continue; // an empty header is the same as signed out
      assert.equal(await outcome(callWith('ensureProfile', {}, junk)), 'UNAUTHENTICATED', junk.slice(0, 20));
      const r = await rest(junk, 'GET', `users/${me.uid}/name`);
      assert.ok([400, 401, 403].includes(r.status), `database answered HTTP ${r.status} to a junk token`);
    }
    assert.equal(await outcome(callWith('ensureProfile', {}, null)), 'UNAUTHENTICATED');
  });

  // Information, not a bug: the Auth and Database emulators hand out and accept UNSIGNED tokens and do not check `exp`, so a forged
  // or expired token (claiming any uid) is accepted here. A real project verifies the signature and expiry, so those two attacks
  // (a forged token, a stale token) cannot be tested against the emulators; this test pins the emulator behaviour so that it is
  // noticed if that ever changes.
  it('documents: the emulators accept an unsigned token for any uid and ignore expiry (a real project does not)', async () => {
    const forged = unsignedToken(me.uid);
    const expired = unsignedToken(me.uid, { exp: Math.floor(Date.now() / 1000) - 7200 });
    assert.equal(await outcome(callWith('ensureProfile', {}, forged)), 'OK');
    assert.equal(await outcome(callWith('ensureProfile', {}, expired)), 'OK');
    assert.equal((await rest(expired, 'GET', `users/${me.uid}/name`)).status, 200);
  });

  it('survives non-standard request bodies with a 4xx answer, not a crash', async () => {
    const bodies: [string, string, string][] = [
      ['not json', 'not json', 'application/json'],
      ['empty', '', 'application/json'],
      ['json array', '[1,2]', 'application/json'],
      ['no data key', '{}', 'application/json'],
      ['data null', '{"data":null}', 'application/json'],
      ['text/plain', '{"data":{}}', 'text/plain'],
      ['huge', JSON.stringify({ data: { code: 'x'.repeat(3_000_000) } }), 'application/json'],
      ['deep', `{"data":${'['.repeat(2000)}${']'.repeat(2000)}}`, 'application/json'],
    ];
    const bad: string[] = [];
    for (const [label, body, type] of bodies) {
      const r = await rawCall('sendFriendRequest', body, me.token, type);
      if (r.status >= 500) bad.push(`${label}: HTTP ${r.status} ${r.text.slice(0, 80)}`);
    }
    assert.deepEqual(bad, []);
  });

  it('handles many concurrent junk calls without any server error', async () => {
    const results = await inParallel(16, (i) => outcome(me.call('joinMatch', { code: JUNK[i % JUNK.length]?.[1] })));
    assert.ok(results.every((r) => CLEAN.has(r)), results.join(','));
  });
});
