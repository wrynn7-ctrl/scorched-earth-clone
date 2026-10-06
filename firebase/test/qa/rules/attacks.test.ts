// M7-Q adversarial rules tests: a malicious signed-in client against database.rules.json (ARCHITECTURE sections 44-46,
// firebase/README.md "The action log in the rules"). Everything here must be DENIED unless a test says otherwise.
//
// Tests that found a hole are marked `bug('BUG (severity): ...')` with the exact input, expected and actual in a
// comment, so they can be switched on again when the rules are fixed.
import { bug } from '../bug';
import assert from 'node:assert/strict';
import { get, query, orderByChild, equalTo } from 'firebase/database';
import {
  append,
  as,
  anonymous,
  assertFails,
  assertSucceeds,
  auto,
  fire,
  HOUR,
  MID,
  ref,
  seed,
  seedAll,
  serverTimestamp,
  set,
  turnFor,
  update,
  useRulesEnv,
} from '../../rules/helpers';

const NEXT = (tank: number, uid: string, extra: Record<string, unknown> = {}) => ({ ...turnFor(tank, uid, 4), ...extra });
const M = (path: string): string => `matches/${MID}/${path}`;

describe('QA rules: turn order, seats and indices', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll(); // turn: tank 0 (host); seats 0 host, 1 bob, 2 CPU, 3 host
  });

  it('refuses every wrong-seat / wrong-turn combination for every member and outsider', async () => {
    for (const actor of ['host', 'bob', 'cat']) {
      for (let tank = 0; tank < 8; tank += 1) {
        const allowed = actor === 'host' && tank === 0;
        const op = update(ref(as(actor)), append(count, [fire(tank)], NEXT(1, 'bob')));
        if (allowed) await assertSucceeds(op);
        else await assertFails(op);
        if (allowed) await seedAll();
      }
    }
  });

  it('refuses skipped, reused, negative, padded and fractional indices', async () => {
    const db = as('host');
    for (const idx of [count + 1, count - 1, 0, -1, count + 16, count + 17, 999999]) {
      await assertFails(update(ref(db), { [M(`actions/${idx}`)]: fire(0), [M('meta/actionCount')]: count + 1 }));
    }
    for (const key of [`0${count}`, ` ${count}`, `${count} `, `+${count}`, `${count}e0`, `00${count}`]) {
      await assertFails(update(ref(db), { [M(`actions/${key}`)]: fire(0), [M('meta/actionCount')]: count + 1 }));
    }
    for (const bad of [count + 0.5, `${count + 1}`, count, count + 17, -1, null, true, { a: 1 }, [count + 1]]) {
      await assertFails(update(ref(db), { [M(`actions/${count}`)]: fire(0), [M('meta/actionCount')]: bad }));
    }
  });

  it('refuses to write entries as separate leaf paths that would assemble an illegal entry', async () => {
    const db = as('bob'); // not the holder
    await assertFails(
      update(ref(db), {
        [M(`actions/${count}/kind`)]: 'fire',
        [M(`actions/${count}/tank`)]: 1,
        [M(`actions/${count}/angle`)]: 10,
        [M(`actions/${count}/power`)]: 10,
        [M(`actions/${count}/weapon`)]: 'spark_dart',
        [M('meta/actionCount')]: count + 1,
      }),
    );
    // even the holder cannot sneak an extra field in through a leaf path
    await assertFails(
      update(ref(as('host')), {
        [M(`actions/${count}/kind`)]: 'pass',
        [M(`actions/${count}/tank`)]: 0,
        [M(`actions/${count}/extra`)]: 1,
        [M('meta/actionCount')]: count + 1,
      }),
    );
  });

  it('refuses a whole-log rewrite, a log wipe and a match wipe from every account', async () => {
    for (const actor of ['host', 'bob', 'cat']) {
      const db = as(actor);
      await assertFails(set(ref(db, M('actions')), { 0: fire(0), 1: fire(0), 2: fire(0), 3: fire(0) }));
      await assertFails(set(ref(db, M('actions')), null));
      await assertFails(set(ref(db, `matches/${MID}`), null));
      await assertFails(set(ref(db, 'matches'), null));
      await assertFails(set(ref(db), null));
      await assertFails(set(ref(db, M('actions/1/tank')), 3));
      await assertFails(set(ref(db, M('actions/1/kind')), null));
      await assertFails(update(ref(db), { [M('actions/2')]: null, [M('meta/actionCount')]: count - 1 }));
    }
  });

  it('refuses a batch of 17 or more entries however it is assembled', async () => {
    const db = as('host');
    for (const total of [17, 18, 24, 40]) {
      const entries = [fire(0), ...Array.from({ length: total - 1 }, () => auto(2))];
      await assertFails(update(ref(db), append(count, entries, NEXT(1, 'bob'))));
    }
    // 16 entries but a count that claims 17
    const sixteen = [fire(0), ...Array.from({ length: 15 }, () => auto(2))];
    const lie = append(count, sixteen, NEXT(1, 'bob'));
    lie[M('meta/actionCount')] = count + 17;
    await assertFails(update(ref(db), lie));
    // 17 entries written, count only 16 ahead
    const seventeen = append(count, [fire(0), ...Array.from({ length: 16 }, () => auto(2))], NEXT(1, 'bob'));
    seventeen[M('meta/actionCount')] = count + 16;
    await assertFails(update(ref(db), seventeen));
  });

  it('refuses fake auto / auto_shop entries for human seats, in every position of a batch', async () => {
    const db = as('host');
    for (const tank of [0, 1, 3, 4, 7]) {
      await assertFails(update(ref(db), append(count, [fire(0), auto(tank)], NEXT(1, 'bob'))));
      await assertFails(update(ref(db), append(count, [fire(0), { kind: 'auto_shop', tank, level: 2 }], NEXT(1, 'bob'))));
      await assertFails(update(ref(db), append(count, [fire(0), auto(2), auto(tank)], NEXT(1, 'bob'))));
    }
    await seed({ [M('meta/turn')]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    for (const tank of [0, 1, 3]) {
      await assertFails(update(ref(as('bob')), append(count, [auto(tank)], NEXT(1, 'bob'))));
      await assertFails(update(ref(as('bob')), append(count, [{ kind: 'auto_shop', tank, level: 2 }], NEXT(1, 'bob'))));
    }
  });

  it('refuses to make the stored turn point at a seat the writer does not hold, or at nobody', async () => {
    const db = as('host');
    for (const turn of [NEXT(1, 'host'), NEXT(0, 'bob'), NEXT(0, 'cpu'), NEXT(2, 'host'), NEXT(0, 'any'), NEXT(-2, 'host'), NEXT(-1, 'host'), NEXT(0, ''), NEXT(0, 'x'.repeat(80))]) {
      await assertFails(update(ref(db), append(count, [fire(0)], turn)));
    }
  });
});

describe('QA rules: CPU entries written by a member', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll(); // seat 2 is a CPU of level 2
  });

  // BUG (medium): a member can pick the AI strength of any CPU turn.
  //   input:    host appends [fire(0), {kind:'auto', tank:2, level:4}] (seat 2 is CPU level 2), or
  //             {kind:'auto_shop', tank:2, level:1} during the shop.
  //   expected: denied: the entry's level must equal seats/2/level (an entry's `level` is authoritative in NetReplay, so the
  //             writer decides how well the opponent's (or his own team's) CPU plays; see game/tests/qa/test_net_replay_robustness.gd).
  //   actual:   accepted by the rules (only 1..4 is checked) and by NetReplay (net_replay.gd:_apply_auto only range-checks).
  //   cause:    build_rules.mjs firstEntryOk / followingEntryOk never compare `newData.child('level')` with the seat's level.
  bug('BUG (medium): refuses an auto entry whose level differs from the CPU seat\'s level', async () => {
    await assertFails(update(ref(as('host')), append(count, [fire(0), { kind: 'auto', tank: 2, level: 4 }], NEXT(1, 'bob'))));
    await assertFails(update(ref(as('host')), append(count, [fire(0), { kind: 'auto', tank: 2, level: 1 }], NEXT(1, 'bob'))));
    await seed({ [M('meta/turn')]: { tank: -2, uid: 'any', deadline: Date.now() + HOUR, index: 3 } });
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'auto_shop', tank: 2, level: 1 }])));
  });

  it('accepts the CPU turn with the seat\'s own level (control)', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0), auto(2, 2)], NEXT(1, 'bob'))));
  });
});

describe('QA rules: the turn marker and who may move it', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll();
  });

  it('refuses leaf writes into meta/turn and a turn written without a new entry', async () => {
    for (const actor of ['host', 'bob']) {
      const db = as(actor);
      await assertFails(set(ref(db, M('meta/turn/tank')), 1));
      await assertFails(set(ref(db, M('meta/turn/uid')), actor));
      await assertFails(set(ref(db, M('meta/turn/deadline')), Date.now() + 1000));
      await assertFails(set(ref(db, M('meta/turn/index')), 4));
      await assertFails(set(ref(db, M('meta/turn')), NEXT(1, 'bob')));
      await assertFails(set(ref(db, M('meta/turn')), null));
    }
  });

  it('keeps the turn index strictly +1 (no replay of an old turn, no jump)', async () => {
    for (const index of [0, 2, 3, 5, 100, -1, 3.5]) {
      await assertFails(update(ref(as('host')), append(count, [fire(0)], { ...NEXT(1, 'bob'), index })));
    }
  });

  it('refuses a turn deadline set far in the future by the holder (a turn held "forever")', async () => {
    for (const hours of [73, 100, 24 * 365]) {
      await assertFails(update(ref(as('host')), append(count, [fire(0)], NEXT(0, 'host', { deadline: Date.now() + hours * HOUR }))));
    }
  });

  it('refuses a live deadline beyond liveSec on the new turn', async () => {
    await assertFails(update(ref(as('host')), append(count, [fire(0)], NEXT(0, 'host', { liveDeadline: Date.now() + 5 * 60000 }))));
  });

  // ---------------------------------------------------------------------------------------------------------------
  // BUG (medium): a turn can be handed over already expired, which lets a member skip the next player's turn at once.
  //   input:    host (holder of tank 0) appends `fire` and sets meta/turn = {tank 1, uid bob, deadline: now - 100 s, index 4}
  //             (and/or liveDeadline: now - 100 s); then, in a second update, host appends {kind:'timeout', tank:1, async:1}.
  //   expected: denied: a freshly written turn must not be due, the AI must not play bob's turn before he can see it.
  //   actual:   both writes succeed. `deadline >= now - DEADLINE_SLACK_MS` (2 minutes of clock slack) accepts a past deadline,
  //             and `timeoutDue` then accepts `now > turn.deadline` at once. With `liveDeadline` the same works as a live skip
  //             while bob is online (a plain `pass` is written for him).
  //   cause:    firebase/rules/build_rules.mjs turnRule `.validate`: `${nDeadline} >= now - ${DEADLINE_SLACK_MS}` and the
  //             same slack on liveDeadline. The existing test only checks a deadline 10 minutes in the past.
  //   fix idea: lower bound `now - 5000` (the client uses the server clock), or `now` exactly, and reject a liveDeadline < now.
  // ---------------------------------------------------------------------------------------------------------------
  bug('BUG (medium): refuses a turn that is already past its hard deadline (within the 2 minute slack)', async () => {
    await assertFails(update(ref(as('host')), append(count, [fire(0)], NEXT(1, 'bob', { deadline: Date.now() - 100000 }))));
  });

  bug('BUG (medium): the next player cannot be skipped instantly with an async timeout written right after a stale turn', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0)], NEXT(1, 'bob', { deadline: Date.now() - 100000 }))));
    // the attacker's second write: the AI plays bob's turn
    await assertFails(update(ref(as('host')), append(count + 1, [{ kind: 'timeout', tank: 1, async: 1 }])));
  });

  bug('BUG (medium): a live deadline in the past lets the next player be passed at once while they are online', async () => {
    await seed({ [M('presence/bob')]: Date.now() });
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0)], NEXT(1, 'bob', { liveDeadline: Date.now() - 100000 }))));
    await assertFails(update(ref(as('host')), append(count + 1, [{ kind: 'timeout', tank: 1 }])));
  });

  it('documents what the rules cannot know: the holder may re-write the turn for himself (clients dispute it)', async () => {
    // Contract: full validation is client-side. A holder can set the turn to himself again, but it costs a legal action and
    // every client then calls the match disputed ("turn_tank"); checked in game/tests/net/qa_*.
    await assertSucceeds(update(ref(as('host')), append(count, [{ kind: 'move', tank: 0, dx: 5 }], NEXT(0, 'host'))));
  });

  it('lets a "needs resolve" marker be replaced only with a well-formed turn', async () => {
    await seed({ [M('meta/turn')]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    for (const turn of [
      NEXT(1, 'bob', { index: 9 }),
      NEXT(1, 'host'),
      { tank: 1, uid: 'bob', index: 4 },
      NEXT(1, 'bob', { deadline: Date.now() + 500 * HOUR }),
      { ...NEXT(1, 'bob'), extra: 1 },
    ]) {
      await assertFails(update(ref(as('cat')), { [M('meta/turn')]: turn }));
      await assertFails(update(ref(as('bob')), { [M('meta/turn')]: turn }));
    }
  });

  // Informational: while a turn is "needs resolve" ANY member can replace it with ANY seat's turn (no entry needed), and
  // nothing in the rules compares it with the log. Clients detect the mismatch after 2.5 s and call the match disputed.
  it('documents: a member can write a wrong-seat turn over a "needs resolve" marker (clients dispute it)', async () => {
    await seed({ [M('meta/turn')]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    await assertSucceeds(update(ref(as('bob')), { [M('meta/turn')]: NEXT(1, 'bob') }));
  });
});

describe('QA rules: timeouts', () => {
  useRulesEnv();
  let count = 0;
  const hard = { kind: 'timeout', tank: 0, async: 1 };
  const live = { kind: 'timeout', tank: 0 };
  beforeEach(async () => {
    count = await seedAll({ turn: turnFor(0, 'host', 3, { deadline: Date.now() + HOUR, liveDeadline: Date.now() + 30000 }) });
  });

  it('refuses any timeout before its deadline, from every account, in every form', async () => {
    await seed({ [M('presence/host')]: Date.now() - 500 });
    for (const actor of ['host', 'bob', 'cat']) {
      for (const entry of [hard, live, { ...hard, async: 0 }, { ...hard, async: 2 }, { ...hard, async: '1' }, { ...hard, async: true }, { ...hard, async: 1.5 }, { ...hard, async: null }]) {
        await assertFails(update(ref(as(actor)), append(count, [entry])));
      }
    }
  });

  it('refuses a timeout for another seat or a CPU seat, or when the turn is a marker', async () => {
    await seed({ [M('meta/turn')]: turnFor(0, 'host', 3, { deadline: Date.now() - 5000 }) });
    for (const tank of [1, 2, 3, 4, 7, -1, -2, 8]) {
      await assertFails(update(ref(as('bob')), append(count, [{ kind: 'timeout', tank, async: 1 }])));
    }
    await seed({ [M('meta/turn')]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    for (const tank of [0, 1]) await assertFails(update(ref(as('bob')), append(count, [{ kind: 'timeout', tank, async: 1 }])));
  });

  it('refuses a live skip whenever the holder is not provably present', async () => {
    await seed({ [M('meta/turn')]: turnFor(0, 'host', 3, { deadline: Date.now() + HOUR, liveDeadline: Date.now() - 500 }) });
    await assertFails(update(ref(as('bob')), append(count, [live]))); // no presence
    for (const age of [75001, 80000, 600000, 86400000]) {
      await seed({ [M('presence/host')]: Date.now() - age });
      await assertFails(update(ref(as('bob')), append(count, [live])));
    }
    // another member's heartbeat does not count for the holder
    await seed({ [M('presence/host')]: null, [M('presence/bob')]: Date.now() });
    await assertFails(update(ref(as('bob')), append(count, [live])));
  });

  it('refuses to forge the holder\'s presence, as the holder or as anyone else', async () => {
    await assertFails(set(ref(as('bob'), M('presence/host')), serverTimestamp()));
    await assertFails(set(ref(as('bob'), M('presence/bob')), Date.now()));
    await assertFails(set(ref(as('bob'), M('presence/bob')), Date.now() + 1e9));
    await assertFails(set(ref(as('cat'), M('presence/cat')), serverTimestamp()));
    await assertSucceeds(set(ref(as('bob'), M('presence/bob')), serverTimestamp()));
  });

  it('refuses a timeout appended after a human entry in the same batch', async () => {
    await seed({ [M('meta/turn')]: turnFor(0, 'host', 3, { deadline: Date.now() - 5000 }) });
    await assertFails(update(ref(as('host')), append(count, [fire(0), { kind: 'timeout', tank: 1, async: 1 }])));
    await assertFails(update(ref(as('bob')), append(count, [hard, { kind: 'timeout', tank: 1, async: 1 }])));
  });

  it('refuses timeouts on a match that is not playing, and from outsiders', async () => {
    await seed({ [M('meta/turn')]: turnFor(0, 'host', 3, { deadline: Date.now() - 5000 }) });
    await assertFails(update(ref(as('cat')), append(count, [hard])));
    await assertFails(update(ref(anonymous()), append(count, [hard])));
    for (const status of ['over', 'abandoned', 'lobby']) {
      await seed({ [M('meta/status')]: status });
      await assertFails(update(ref(as('bob')), append(count, [hard])));
    }
  });
});

describe('QA rules: status, settings and seats after the start', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll();
  });

  it('refuses every write to the fixed meta fields, from members and the host', async () => {
    const targets: Record<string, unknown> = {
      'meta/settings/rounds': 99,
      'meta/settings/seed': 1,
      'meta/settings/controllers/1': 4,
      'meta/settings': { seed: 7 },
      'meta/seed': 1,
      'meta/seats/0/uid': 'bob',
      'meta/seats/1/uid': 'host',
      'meta/seats/2/kind': 'human',
      'meta/seats/2/level': 1,
      'meta/seats/1': { kind: 'cpu', level: 1 },
      'meta/seats': [],
      'meta/timers/liveSec': 10,
      'meta/timers/asyncHours': 1,
      'meta/timers/asyncTimeout': 'end',
      'meta/timers': { liveSec: 10, asyncHours: 1, asyncTimeout: 'end' },
      'meta/hostUid': 'bob',
      'meta/code': 'ZZZZZZ',
      'meta/protocol': 2,
      'meta/created': 5,
      'meta/started': 5,
      'meta/extra': 1,
    };
    for (const actor of ['host', 'bob']) {
      for (const [path, value] of Object.entries(targets)) {
        await assertFails(set(ref(as(actor), M(path)), value));
        await assertFails(update(ref(as(actor)), { ...append(count, [fire(0)]), [M(path)]: value }));
      }
      await assertFails(set(ref(as(actor), M('meta')), null));
    }
  });

  it('refuses to mark the match over without an action, or with one the writer may not make', async () => {
    for (const actor of ['host', 'bob', 'cat']) {
      await assertFails(set(ref(as(actor), M('meta/status')), 'over'));
    }
    await assertFails(update(ref(as('bob')), { ...append(count, [fire(0)]), [M('meta/status')]: 'over' })); // bob does not hold tank 0
    await assertFails(update(ref(as('cat')), { ...append(count, [fire(0)]), [M('meta/status')]: 'over' }));
    await assertFails(update(ref(as('host')), { [M('meta/status')]: 'over', [M('meta/actionCount')]: count + 1 })); // count with no entry
  });

  it('refuses every status transition a client may not make', async () => {
    const db = as('host');
    for (const bad of ['lobby', 'playing', 'finished', 'OVER', '', 1, true, null, { a: 1 }]) {
      await assertFails(update(ref(db), { ...append(count, [fire(0)]), [M('meta/status')]: bad }));
    }
    for (const actor of ['bob', 'cat']) {
      await assertFails(set(ref(as(actor), M('meta/status')), 'abandoned'));
    }
    await seed({ [M('meta/status')]: 'over' });
    await assertFails(set(ref(db, M('meta/status')), 'abandoned'));
    await assertFails(set(ref(db, M('meta/status')), 'playing'));
    await seed({ [M('meta/status')]: 'abandoned' });
    await assertFails(set(ref(db, M('meta/status')), 'playing'));
    await assertFails(update(ref(as('host')), append(count, [fire(0)])));
  });

  // Informational: "over" is accepted together with any legal action even though the simulation is not over. The rules
  // cannot check that; the client side is checked in game/tests/net/qa_edge_flows.gd.
  it('documents: a holder can end the match early with a legal action plus status over', async () => {
    await assertSucceeds(update(ref(as('host')), { ...append(count, [fire(0)]), [M('meta/status')]: 'over' }));
  });
});

describe('QA rules: reading what a blocked pair, an outsider or a stranger must not see', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll({ members: ['host', 'bob', 'cat'], presence: { host: Date.now(), bob: Date.now(), cat: Date.now() } });
    await seed({
      'blocks/bob/cat': true,
      'friends/host/bob': { since: 1, by: 'bob' },
      'friendRequests/bob/cat': { name: 'CAT', at: 1 },
      'invites/bob/M9': { fromUid: 'host', fromName: 'HOST', at: 1, code: 'ABC234', mode: 0 },
      'friendCodes/BOBCODE22': 'bob',
      'matchCodes/ABC234': MID,
      'users/bob/fcm/abcdefgh12345678': 'x'.repeat(30),
      'users/bob/purchase': { at: 1, tokenHash: 'h' },
      'nameReports/bob/cat': true,
      'reports/r1': { reporterUid: 'cat', targetUid: 'bob', reason: 'offensive_name', at: 1 },
      'purchaseTokens/h': 'bob',
      'sweepQueue/M1': 5,
    });
  });

  it('hides presence, name, nameHidden and protocol between a blocked pair, both ways, and whole-profile reads', async () => {
    for (const [a, b] of [['cat', 'bob'], ['bob', 'cat']] as const) {
      await assertFails(get(ref(as(a), M(`presence/${b}`))));
      for (const f of ['name', 'nameHidden', 'protocol', 'friendCode', 'full', 'created', 'purchase', 'fcm']) {
        await assertFails(get(ref(as(a), `users/${b}/${f}`)));
      }
      await assertFails(get(ref(as(a), `users/${b}`)));
    }
    await assertSucceeds(get(ref(as('host'), M('presence/bob'))));
    await assertSucceeds(get(ref(as('host'), 'users/bob/name')));
  });

  it('refuses reading others\' friend codes, full flags, tokens, requests, blocks, friends and matches lists', async () => {
    const leaked: string[] = [];
    const probe = async (actor: string, path: string): Promise<void> => {
      try {
        await get(ref(as(actor), path));
        leaked.push(`${actor} read ${path}`);
      } catch {
        // denied, as expected
      }
    };
    for (const actor of ['host', 'cat', 'bob']) {
      for (const path of ['friendCodes', 'friendCodes/BOBCODE22', 'matchCodes', 'matchCodes/ABC234', 'reports', 'reports/r1', 'nameReports', 'nameReports/bob', 'purchaseTokens', 'sweepQueue', '_test', 'users', 'friends', 'blocks', 'invites', 'friendRequests', 'userMatches', 'matches', `matches/${MID}`, M('presence')]) {
        await probe(actor, path);
      }
    }
    for (const actor of ['host', 'cat']) {
      for (const path of ['users/bob/friendCode', 'users/bob/full', 'users/bob/created', 'users/bob/fcm', 'users/bob/fcm/abcdefgh12345678', 'users/bob/purchase', 'friends/bob', 'friends/bob/host', 'blocks/bob', 'blocks/bob/cat', 'friendRequests/bob', 'friendRequests/bob/cat', 'invites/bob', 'invites/bob/M9', 'userMatches/bob', `userMatches/bob/${MID}`]) {
        await probe(actor, path);
      }
    }
    await assertFails(get(ref(anonymous(), 'users/bob/name')));
    assert.deepEqual(leaked, []);
  });

  it('refuses queries that would enumerate users or friend codes', async () => {
    await assertFails(get(query(ref(as('cat'), 'users'), orderByChild('friendCode'), equalTo('BOBCODE22'))));
    await assertFails(get(query(ref(as('cat'), 'users'), orderByChild('name'), equalTo('BOB'))));
    await assertFails(get(query(ref(as('cat'), 'friendCodes'), orderByChild('x'))));
    await assertFails(get(query(ref(as('cat'), 'userMatches'), orderByChild('updated'))));
    await assertFails(get(query(ref(as('cat'), 'invites/bob'), orderByChild('at'))));
  });

  it('lets a member of a match read nothing of another match', async () => {
    await seed({ 'matches/M2/meta': { hostUid: 'x', status: 'playing', seats: [], actionCount: 0 }, 'matches/M2/actions/0': { kind: 'pass', tank: 0 } });
    for (const path of ['meta', 'actions', 'actions/0', 'fp', 'msgs', 'presence/host', 'lastMsg']) {
      await assertFails(get(ref(as('host'), `matches/M2/${path}`)));
    }
  });
});

describe('QA rules: quick messages, abuse of the rate limit', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
  });
  const msg = (seat = 0, n = 1): Record<string, unknown> => ({ uid: 'host', seat, msg: n, at: serverTimestamp() });
  const withLimiter = (extra: Record<string, unknown>): Record<string, unknown> => ({ [M('lastMsg/host')]: serverTimestamp(), ...extra });

  it('accepts exactly one message per update, then refuses the next inside 3 seconds', async () => {
    await assertSucceeds(update(ref(as('host')), withLimiter({ [M('msgs/m1')]: msg() })));
    await assertFails(update(ref(as('host')), withLimiter({ [M('msgs/m2')]: msg() })));
  });

  // BUG (low): the 3 s limit counts updates, not messages. One update may carry any number of messages.
  //   input:    update(matches/M1, {lastMsg/host: now, msgs/p0..p49: {uid, seat 0, msg 1, at: now}})
  //   expected: denied (or at most one message), like two separate updates inside 3 s.
  //   actual:   all 50 messages are written; each message's rule only compares lastMsg with its previous value.
  //   cause:    build_rules.mjs msgRule `.write`: the limiter clause is evaluated per message, not per update.
  //   impact:   chat flood: every member's bubble queue (message_received) fills; no cost or integrity risk. Use
  //             `newData.parent().val()` child counting is impossible; fix by validating that lastMsg/{uid} == $pid-derived key
  //             (for example require the push key to be exactly `m<lastMsg value>`), so only one key can match.
  bug('BUG (low): refuses a batch of messages in one update (rate limit bypass)', async () => {
    const batch: Record<string, unknown> = withLimiter({});
    for (let i = 0; i < 50; i += 1) batch[M(`msgs/p${i}`)] = msg();
    await assertFails(update(ref(as('host')), batch));
  });

  it('refuses out-of-range, mistyped and forged messages', async () => {
    const db = as('host');
    for (const n of [-1, 8, 9, 100, 1.5, '3', true, null, [1], { a: 1 }, 2 ** 53]) {
      await assertFails(update(ref(db), withLimiter({ [M('msgs/a')]: { ...msg(), msg: n } })));
    }
    for (const seat of [1, 2, 3.5, -1, 8, '0', null]) {
      await assertFails(update(ref(db), withLimiter({ [M('msgs/a')]: { ...msg(), seat } })));
    }
    for (const bad of [{ uid: 'bob' }, { at: 5 }, { at: Date.now() + 99999 }, { text: 'hello' }, { extra: 1 }, { uid: null }]) {
      await assertFails(update(ref(db), withLimiter({ [M('msgs/a')]: { ...msg(), ...bad } })));
    }
    await assertFails(update(ref(db), { [M('msgs/a')]: msg() })); // no limiter bump
    await assertFails(update(ref(as('cat')), { [M('lastMsg/cat')]: serverTimestamp(), [M('msgs/a')]: { uid: 'cat', seat: 0, msg: 1, at: serverTimestamp() } }));
    await assertFails(update(ref(db), withLimiter({ [`matches/${MID}/msgs/${'k'.repeat(31)}`]: msg() })));
  });

  it('refuses edits and deletes of messages and limiter values, and other players\' limiters', async () => {
    await assertSucceeds(update(ref(as('host')), withLimiter({ [M('msgs/m1')]: msg() })));
    await assertFails(set(ref(as('host'), M('msgs/m1/msg')), 2));
    await assertFails(set(ref(as('host'), M('msgs/m1')), null));
    await assertFails(set(ref(as('bob'), M('msgs/m1')), null));
    await assertFails(set(ref(as('host'), M('lastMsg/host')), null));
    await assertFails(set(ref(as('bob'), M('lastMsg/host')), serverTimestamp()));
    await assertFails(set(ref(as('host'), M('msgs')), null));
  });
});

describe('QA rules: account fields, friends, invites, forged ownership', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
    await seed({ 'invites/bob/M9': { fromUid: 'host', fromName: 'HOST', at: 1, code: 'ABC234', mode: 0 }, 'friends/bob/host': { since: 1, by: 'bob' }, 'friends/host/bob': { since: 1, by: 'bob' } });
  });

  it('refuses writes to server-only user fields, alone and next to a legal name write', async () => {
    const db = as('bob');
    for (const field of ['full', 'nameHidden', 'friendCode', 'created', 'purchase', 'extra']) {
      const value = field === 'full' || field === 'nameHidden' ? true : 'X1234567';
      await assertFails(set(ref(db, `users/bob/${field}`), value));
      await assertFails(update(ref(db), { 'users/bob/name': 'NEWNAME', [`users/bob/${field}`]: value }));
      await assertFails(update(ref(db, 'users/bob'), { [field]: value }));
    }
    await assertFails(set(ref(db, 'users/bob'), { name: 'BOB', full: true, friendCode: 'BOBCODE22', nameHidden: false, created: 1, protocol: 1 }));
    await assertFails(set(ref(db, 'users/bob'), null));
    await assertFails(set(ref(db, 'users/bob/fcm'), null));
    await assertFails(set(ref(db, 'users'), null));
    await assertFails(update(ref(as('cat')), { 'users/bob/name': 'HACKED' }));
    await assertFails(update(ref(as('cat')), { 'users/bob/protocol': 9 }));
    await assertFails(update(ref(as('cat')), { 'users/bob/fcm/abcdefgh12345678': 'y'.repeat(30) }));
  });

  it('refuses invalid names, deletes of the name, and non-integer or huge protocol numbers', async () => {
    const db = as('bob');
    for (const bad of ['', 'x'.repeat(13), 1, true, null, ['a'], { a: 1 }]) await assertFails(set(ref(db, 'users/bob/name'), bad));
    for (const bad of [-1, 1000001, 1.5, '3', null, true, 2 ** 60]) await assertFails(set(ref(db, 'users/bob/protocol'), bad));
  });

  it('refuses every write to friends, requests, blocks, userMatches, codes, reports and invites for every account', async () => {
    const writes: Record<string, unknown> = {
      'friends/bob/cat': { since: 1, by: 'bob' },
      'friends/cat/bob': { since: 1, by: 'bob' },
      'friends/bob': null,
      'friendRequests/bob/cat': { name: 'CAT', at: 1 },
      'friendRequests/cat/bob': { name: 'BOB', at: 1 },
      'sentRequests/bob/cat': true,
      'blocks/bob/host': true,
      'blocks/bob': null,
      'blocks/host/bob': null,
      [`userMatches/cat/${MID}`]: { updated: 1, yourTurn: true, status: 'playing' },
      [`userMatches/cat/${MID}/status`]: 'playing',
      [`userMatches/bob/${MID}/status`]: 'over',
      [`userMatches/bob/${MID}`]: null,
      userMatches: null,
      'friendCodes/ZZZZZZZZ': 'bob',
      'friendCodes/BOBCODE22': 'cat',
      'matchCodes/ZZZZZZ': MID,
      'reports/r9': { reporterUid: 'bob', targetUid: 'cat', reason: 'x', at: 1 },
      'nameReports/cat/bob': true,
      'nameReports/cat/host': true,
      'purchaseTokens/h': 'bob',
      'sweepQueue/M1': 1,
      '_test/fcm/x': { uid: 'bob' },
      'invitesSent/bob/M1/cat': true,
    };
    for (const actor of ['bob', 'host', 'cat']) {
      for (const [path, value] of Object.entries(writes)) {
        if (path === `userMatches/bob/${MID}` && actor === 'bob') continue; // own running match: covered below
        await assertFails(set(ref(as(actor), path), value));
      }
    }
  });

  it('refuses forged invites: other recipients, spoofed senders, non-members, overwrites and others\' dismissals', async () => {
    const forged = { fromUid: 'host', fromName: 'HOST', at: Date.now(), code: 'ABC234', mode: 0 };
    for (const actor of ['host', 'bob', 'cat']) {
      await assertFails(set(ref(as(actor), 'invites/cat/M1'), forged));
      await assertFails(set(ref(as(actor), 'invites/bob/M1'), forged));
      await assertFails(set(ref(as(actor), 'invites/bob/M9'), forged)); // overwrite an existing invite
      await assertFails(update(ref(as(actor)), { 'invites/cat/M1/code': 'ZZZZZZ' }));
    }
    await assertFails(set(ref(as('host'), 'invites/bob/M9'), null)); // not the recipient
    await assertFails(set(ref(as('cat'), 'invites/bob/M9'), null));
    await assertFails(set(ref(as('bob'), 'invites/bob/M9/code'), null)); // partial delete is an edit
    await assertFails(set(ref(as('bob'), 'invites/bob/M9/code'), 'ZZZZZZ'));
    await assertSucceeds(set(ref(as('bob'), 'invites/bob/M9'), null)); // dismissing is allowed
  });

  it('keeps a user\'s own running match in their list: only finished ones can be dropped', async () => {
    await assertFails(set(ref(as('bob'), `userMatches/bob/${MID}`), null));
    await assertFails(set(ref(as('bob'), `userMatches/bob/${MID}/status`), 'over'));
    await seed({ [M('meta/status')]: 'over', [`userMatches/bob/${MID}/status`]: 'over' });
    await assertSucceeds(set(ref(as('bob'), `userMatches/bob/${MID}`), null));
  });

  it('stops being a member the moment the entry is gone (a left player cannot append or read)', async () => {
    await seed({ [`userMatches/host/${MID}`]: null });
    await assertFails(update(ref(as('host')), append(3, [fire(0)])));
    await assertFails(get(ref(as('host'), M('meta'))));
    await assertFails(set(ref(as('host'), M('presence/host')), serverTimestamp()));
  });
});

describe('QA rules: push token storage', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
  });

  it('refuses malformed token keys and values', async () => {
    const db = as('bob');
    for (const key of ['short', 'a'.repeat(65), 'has space1234', 'bad!chars1234', 'x'.repeat(7)]) {
      await assertFails(set(ref(db, `users/bob/fcm/${key}`), 'x'.repeat(30)));
    }
    for (const value of ['short', 'x'.repeat(4097), 5, true, { a: 1 }]) {
      await assertFails(set(ref(db, 'users/bob/fcm/abcdefgh12345678'), value));
    }
  });

  // BUG (low): there is no cap on the number of stored push tokens.
  //   input:    one update writing users/bob/fcm/<64 distinct valid keys>, each a 4096-char token
  //   expected: denied past a small number (a phone has one token, a handful at most)
  //   actual:   every key is accepted, so one account can grow its node without bound (storage cost); the push sender also
  //             sends to every stored token (sendEachForMulticast has a 500 limit).
  //   cause:    build_rules.mjs users/$uid/fcm/$tokenHash has no per-node count limit.
  bug('BUG (low): caps the number of push tokens per user', async () => {
    const batch: Record<string, unknown> = {};
    for (let i = 0; i < 64; i += 1) batch[`users/bob/fcm/${String(i).padStart(8, '0')}${'k'.repeat(8)}`] = 'x'.repeat(4096);
    await assertFails(update(ref(as('bob')), batch));
  });
});
