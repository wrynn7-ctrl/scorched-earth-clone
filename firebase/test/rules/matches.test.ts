// Rules for match metadata, turn and status, presence, fingerprints, quick messages and the "Your matches" list
// (ARCHITECTURE sections 45 and 46).
import { get } from 'firebase/database';
import {
  anonymous,
  append,
  as,
  assertFails,
  assertSucceeds,
  fire,
  HOUR,
  MID,
  ref,
  seed,
  seedAll,
  seedUsers,
  serverTimestamp,
  set,
  turnFor,
  update,
  useRulesEnv,
  type TurnState,
} from './helpers';

const NEXT = (tank: number, uid: string, extra: Partial<TurnState> = {}): TurnState => turnFor(tank, uid, 4, extra);

describe('rules: reading a match', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll({ presence: { host: Date.now(), bob: Date.now() } });
    await seed({ [`matches/${MID}/fp/2/host`]: 'abcdef0123456789', [`matches/${MID}/msgs/-Nabc`]: { uid: 'bob', seat: 1, msg: 2, at: 1 } });
  });

  it('lets members read meta, actions, fingerprints and messages', async () => {
    for (const uid of ['host', 'bob']) {
      for (const path of ['meta', 'meta/turn', 'meta/seats', 'actions', 'actions/0', 'fp', 'fp/2', 'msgs', 'presence/host', 'presence/bob']) {
        await assertSucceeds(get(ref(as(uid), `matches/${MID}/${path}`)));
      }
    }
  });

  it('refuses outsiders and signed-out clients everything, and the whole-match read even for members', async () => {
    for (const path of ['', '/meta', '/meta/seats', '/actions', '/actions/0', '/fp', '/msgs', '/presence/host']) {
      await assertFails(get(ref(as('cat'), `matches/${MID}${path}`)));
      await assertFails(get(ref(anonymous(), `matches/${MID}${path}`)));
    }
    await assertFails(get(ref(as('host'), `matches/${MID}`)));
    await assertFails(get(ref(as('host'), 'matches')));
  });

  it('stops being readable once a player has left (their membership entry is gone)', async () => {
    await seed({ [`userMatches/bob/${MID}`]: null });
    await assertFails(get(ref(as('bob'), `matches/${MID}/meta`)));
  });

  it('hides presence between a blocked pair but not from other members', async () => {
    await seed({ 'blocks/bob/host': true });
    await assertFails(get(ref(as('host'), `matches/${MID}/presence/bob`)));
    await assertFails(get(ref(as('bob'), `matches/${MID}/presence/host`)));
    await assertSucceeds(get(ref(as('host'), `matches/${MID}/presence/host`)));
    await seed({ [`userMatches/cat/${MID}`]: { updated: 1, yourTurn: false, status: 'playing' } });
    await assertSucceeds(get(ref(as('cat'), `matches/${MID}/presence/bob`)));
  });
});

describe('rules: creating and editing a match', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedUsers();
  });

  it('does not let any client create a match, even a full (paying) host: createMatch is a function', async () => {
    const meta = {
      hostUid: 'host',
      code: 'ZZZ999',
      protocol: 1,
      created: 1,
      status: 'lobby',
      settings: {},
      seats: [{ kind: 'human', uid: 'host' }],
      timers: { liveSec: 60, asyncHours: 72, asyncTimeout: 'auto' },
      actionCount: 0,
    };
    await assertFails(set(ref(as('host'), 'matches/NEW/meta'), meta));
    await assertFails(set(ref(as('host'), 'matches/NEW'), { meta }));
    await assertFails(set(ref(as('bob'), 'matches/NEW/meta'), meta));
    await assertFails(set(ref(as('host'), 'matchCodes/ZZZ999'), 'NEW'));
    await assertFails(set(ref(as('host'), 'userMatches/host/NEW'), { updated: 1, yourTurn: true, status: 'lobby' }));
  });

  it('keeps host, settings, seed, seats, timers, code and protocol server-only', async () => {
    await seedAll();
    for (const [path, value] of [
      ['hostUid', 'bob'],
      ['code', 'XYZ234'],
      ['protocol', 2],
      ['seed', 99],
      ['settings', { seed: 1 }],
      ['settings/rounds', 20],
      ['seats', []],
      ['seats/1/uid', 'host'],
      ['seats/2', { kind: 'human', uid: 'host' }],
      ['timers/asyncHours', 1],
      ['created', 5],
    ] as const) {
      await assertFails(set(ref(as('host'), `matches/${MID}/meta/${path}`), value));
      await assertFails(set(ref(as('bob'), `matches/${MID}/meta/${path}`), value));
    }
    await assertFails(set(ref(as('host'), `matches/${MID}/meta`), null));
  });

  it('lets a user write nothing under another match member\'s node', async () => {
    await seedAll();
    await assertFails(set(ref(as('host'), `matches/${MID}/other`), { x: 1 }));
    await assertFails(set(ref(as('cat'), `matches/${MID}/meta/actionCount`), 99));
  });
});

describe('rules: turn handover', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll();
  });
  const handOver = (turn: unknown) => update(ref(as('host')), { ...append(count, [fire(0)]), [`matches/${MID}/meta/turn`]: turn });

  it('accepts a well-formed turn for a human seat, a CPU seat, the shop and "needs resolve"', async () => {
    await assertSucceeds(handOver(NEXT(1, 'bob')));
  });

  it('accepts the other turn markers', async () => {
    await assertSucceeds(handOver({ tank: 2, uid: 'cpu', deadline: Date.now() + HOUR, index: 4 }));
  });

  it('accepts the shop marker', async () => {
    await assertSucceeds(handOver({ tank: -2, uid: 'any', deadline: Date.now() + HOUR, index: 4 }));
  });

  it('accepts the needs-resolve marker with no deadline', async () => {
    await assertSucceeds(handOver({ tank: -1, uid: 'any', deadline: 0, index: 4 }));
  });

  it('refuses a turn that names the wrong holder for a seat', async () => {
    await assertFails(handOver(NEXT(1, 'host')));
    await assertFails(handOver(NEXT(0, 'bob')));
    await assertFails(handOver(NEXT(2, 'bob'))); // CPU seat must say "cpu"
    await assertFails(handOver(NEXT(5, 'cpu'))); // no such seat
    await assertFails(handOver({ tank: -2, uid: 'bob', deadline: Date.now() + HOUR, index: 4 }));
  });

  it('refuses out-of-range tanks and a non-incrementing index', async () => {
    await assertFails(handOver(NEXT(-3, 'any')));
    await assertFails(handOver(NEXT(8, 'any')));
    await assertFails(handOver(turnFor(1, 'bob', 3)));
    await assertFails(handOver(turnFor(1, 'bob', 9)));
  });

  it('refuses deadlines in the past (an instant timeout), far in the future, or missing', async () => {
    await assertFails(handOver(NEXT(1, 'bob', { deadline: Date.now() - 10 * 60 * 1000 })));
    await assertFails(handOver(NEXT(1, 'bob', { deadline: 0 })));
    await assertFails(handOver(NEXT(1, 'bob', { deadline: Date.now() + 100 * HOUR })));
    await assertFails(handOver({ tank: 1, uid: 'bob', index: 4 }));
    await assertFails(handOver({ tank: -1, uid: 'any', deadline: Date.now() + HOUR, index: 4 }));
  });

  it('bounds the live deadline by the live timer', async () => {
    await assertSucceeds(handOver(NEXT(1, 'bob', { liveDeadline: Date.now() + 60000 })));
  });

  it('refuses a live deadline beyond the live timer, or on a non-aim turn', async () => {
    await assertFails(handOver(NEXT(1, 'bob', { liveDeadline: Date.now() + 10 * 60000 })));
    await assertFails(handOver({ tank: -2, uid: 'any', deadline: Date.now() + HOUR, liveDeadline: Date.now() + 1000, index: 4 }));
  });

  it('refuses extra turn fields', async () => {
    await assertFails(handOver({ ...NEXT(1, 'bob'), winner: 1 }));
  });

  it('refuses a turn change with no new log entry', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/turn`]: NEXT(1, 'bob') }));
    await assertFails(set(ref(as('bob')), null));
  });

  it('lets a member set the turn alone only to resolve a "needs resolve" marker', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    await assertFails(update(ref(as('cat')), { [`matches/${MID}/meta/turn`]: NEXT(1, 'bob') }));
    await assertSucceeds(update(ref(as('bob')), { [`matches/${MID}/meta/turn`]: NEXT(1, 'bob') }));
  });

  it('does not let a deleted or replaced turn through', async () => {
    await assertFails(update(ref(as('host')), { ...append(count, [fire(0)]), [`matches/${MID}/meta/turn`]: null }));
  });
});

describe('rules: match status', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll();
  });

  it('lets a member mark the match over together with the last entry', async () => {
    await assertSucceeds(update(ref(as('host')), { ...append(count, [fire(0)]), [`matches/${MID}/meta/status`]: 'over' }));
  });

  it('refuses over without a new entry, from an outsider, or from a state other than playing', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'over' }));
    await assertFails(update(ref(as('cat')), { ...append(count, [fire(0)]), [`matches/${MID}/meta/status`]: 'over' }));
    await seed({ [`matches/${MID}/meta/status`]: 'lobby' });
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'over' }));
  });

  it('lets only the host abandon, and not undo it', async () => {
    await assertFails(update(ref(as('bob')), { [`matches/${MID}/meta/status`]: 'abandoned' }));
    await assertFails(update(ref(as('cat')), { [`matches/${MID}/meta/status`]: 'abandoned' }));
    await assertSucceeds(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'abandoned' }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'playing' }));
  });

  it('refuses to start, restart, or delete the status from a client', async () => {
    await seed({ [`matches/${MID}/meta/status`]: 'lobby' });
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'playing' }));
    await seed({ [`matches/${MID}/meta/status`]: 'over' });
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'playing' }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/status`]: null }));
  });

  it('lets the host abandon a lobby', async () => {
    await seed({ [`matches/${MID}/meta/status`]: 'lobby' });
    await assertSucceeds(update(ref(as('host')), { [`matches/${MID}/meta/status`]: 'abandoned' }));
  });
});

describe('rules: presence', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
  });

  it('lets a member write their own heartbeat as a server timestamp', async () => {
    await assertSucceeds(set(ref(as('bob'), `matches/${MID}/presence/bob`), serverTimestamp()));
  });

  it('refuses client-chosen times, other users\' heartbeats, outsiders and deletes', async () => {
    await assertFails(set(ref(as('bob'), `matches/${MID}/presence/bob`), Date.now() + 100000));
    await assertFails(set(ref(as('bob'), `matches/${MID}/presence/bob`), 5));
    await assertFails(set(ref(as('bob'), `matches/${MID}/presence/host`), serverTimestamp()));
    await assertFails(set(ref(as('cat'), `matches/${MID}/presence/cat`), serverTimestamp()));
    await assertFails(set(ref(anonymous(), `matches/${MID}/presence/bob`), serverTimestamp()));
    await seed({ [`matches/${MID}/presence/bob`]: Date.now() });
    await assertFails(set(ref(as('bob'), `matches/${MID}/presence/bob`), null));
  });
});

describe('rules: fingerprints', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
  });

  it('lets a member report their own fingerprint for an existing entry, once', async () => {
    await assertSucceeds(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), '0123456789abcdef'));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), 'fedcba9876543210'));
  });

  it('refuses malformed fingerprints, other users\', outsiders\', and entries that do not exist yet', async () => {
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), '0123456789ABCDEF'));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), '0123'));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), 12345));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/host`), '0123456789abcdef'));
    await assertFails(set(ref(as('cat'), `matches/${MID}/fp/1/cat`), '0123456789abcdef'));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/7/bob`), '0123456789abcdef'));
    await assertFails(set(ref(as('bob'), `matches/${MID}/fp/1/bob`), null));
  });
});

describe('rules: quick messages', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
  });
  const send = (uid: string, overrides: Record<string, unknown> = {}, key = '-Nmsg00000000000001', stamp: unknown = serverTimestamp()) =>
    update(ref(as(uid)), {
      [`matches/${MID}/msgs/${key}`]: { uid, seat: uid === 'host' ? 0 : 1, msg: 3, at: serverTimestamp(), ...overrides },
      [`matches/${MID}/lastMsg/${uid}`]: stamp,
    });

  it('lets a member send a preset message from one of their seats', async () => {
    await assertSucceeds(send('bob'));
    await assertSucceeds(send('host', { seat: 3 }, '-Nmsg00000000000003'));
  });

  it('refuses presets outside the table (0..7) and non-integers', async () => {
    for (const msg of [8, -1, 3.5, '3', 100]) await assertFails(send('bob', { msg }));
    await assertSucceeds(send('bob', { msg: 0 }));
    await assertSucceeds(send('host', { msg: 7 }, '-Nmsg00000000000002'));
  });

  it('refuses typed text and extra fields', async () => {
    await assertFails(send('bob', { msg: 'hello' }));
    await assertFails(send('bob', { text: 'hello' }));
  });

  it('refuses a message from a seat the sender does not hold, a forged sender and a forged time', async () => {
    await assertFails(send('bob', { seat: 0 }));
    await assertFails(send('bob', { seat: 2 }));
    await assertFails(send('bob', { seat: 9 }));
    await assertFails(send('bob', { uid: 'host' }));
    await assertFails(send('bob', { at: 12345 }));
    await assertFails(send('cat'));
  });

  it('rate-limits to one message per 3 seconds per player', async () => {
    await assertSucceeds(send('bob'));
    await assertFails(send('bob', {}, '-Nmsg00000000000009')); // immediately again
    await seed({ [`matches/${MID}/lastMsg/bob`]: Date.now() - 4000 });
    await assertSucceeds(send('bob', {}, '-Nmsg0000000000000a'));
    await seed({ [`matches/${MID}/lastMsg/bob`]: Date.now() - 1000 });
    await assertFails(send('bob', {}, '-Nmsg0000000000000b'));
  });

  it('does not let one player\'s message use up (or dodge) another\'s limit', async () => {
    await assertSucceeds(send('bob'));
    await assertSucceeds(send('host', { seat: 0 }, '-Nmsg0000000000000c'));
  });

  it('refuses a message that does not bump the limiter, and a limiter value that is not "now"', async () => {
    await assertFails(
      update(ref(as('bob')), { [`matches/${MID}/msgs/-Nmsg0000000000000d`]: { uid: 'bob', seat: 1, msg: 1, at: serverTimestamp() } }),
    );
    await assertFails(send('bob', {}, '-Nmsg0000000000000e', 12345));
  });

  it('is write-once and refuses oversized keys, deletes, and play outside a running match', async () => {
    await assertSucceeds(send('bob', {}, '-Nmsg0000000000000f'));
    await seed({ [`matches/${MID}/lastMsg/bob`]: Date.now() - 4000 });
    await assertFails(send('bob', { msg: 4 }, '-Nmsg0000000000000f')); // same key again
    await assertFails(send('bob', {}, 'k'.repeat(40)));
    await assertFails(set(ref(as('bob'), `matches/${MID}/msgs/-Nmsg0000000000000f`), null));
    await seed({ [`matches/${MID}/meta/status`]: 'over' });
    await assertFails(send('bob', {}, '-Nmsg00000000000010'));
  });

  it('lets only members read other players\' last-message times', async () => {
    await assertSucceeds(get(ref(as('bob'), `matches/${MID}/lastMsg`)));
    await assertFails(get(ref(as('cat'), `matches/${MID}/lastMsg`)));
  });
});

describe('rules: your matches list', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll();
    await seed({ [`userMatches/bob/M2`]: { updated: 5, yourTurn: false, status: 'over' }, [`userMatches/bob/M3`]: { updated: 6, yourTurn: false, status: 'abandoned' } });
  });

  it('lets users read only their own list, ordered by update time', async () => {
    await assertSucceeds(get(ref(as('bob'), 'userMatches/bob')));
    await assertFails(get(ref(as('host'), 'userMatches/bob')));
    await assertFails(get(ref(anonymous(), 'userMatches/bob')));
    await assertFails(get(ref(as('bob'), 'userMatches')));
  });

  it('lets a user remove a finished match from their list but not a running one', async () => {
    await assertSucceeds(set(ref(as('bob'), 'userMatches/bob/M2'), null));
    await assertSucceeds(set(ref(as('bob'), 'userMatches/bob/M3'), null));
    await assertFails(set(ref(as('bob'), `userMatches/bob/${MID}`), null));
    await assertFails(set(ref(as('host'), 'userMatches/bob/M2'), null));
  });

  it('refuses client writes that would add or edit entries (which would grant match access)', async () => {
    await assertFails(set(ref(as('cat'), `userMatches/cat/${MID}`), { updated: 1, yourTurn: true, status: 'playing' }));
    await assertFails(set(ref(as('bob'), 'userMatches/bob/M2/status'), 'playing'));
    await assertFails(set(ref(as('bob'), 'userMatches/bob/M9'), { updated: 1, yourTurn: true, status: 'playing' }));
    await assertFails(set(ref(as('bob'), 'userMatches/bob'), null));
  });
});
