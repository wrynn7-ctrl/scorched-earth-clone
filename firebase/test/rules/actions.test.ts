// Rules for the append-only action log (ARCHITECTURE section 46): who may write, in what order and in what shape.
import {
  append,
  as,
  assertFails,
  assertSucceeds,
  auto,
  fire,
  HOUR,
  MID,
  ref,
  seedAll,
  seed,
  turnFor,
  update,
  useRulesEnv,
  DEFAULT_SEATS,
  type Seat,
} from './helpers';

const NEXT_TURN = (tank: number, uid: string, index = 4): ReturnType<typeof turnFor> => turnFor(tank, uid, index);

describe('rules: action log - who may append', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll(); // turn: tank 0, held by host; 3 entries already in the log
  });

  it('lets the turn holder append their action and hand the turn on, in one update', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0)], NEXT_TURN(1, 'bob'))));
  });

  it('lets the holder append an action that does not end the turn, without touching the turn', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [{ kind: 'move', tank: 0, dx: -20 }])));
  });

  it('lets a shared-phone holder act for any seat they hold when it is that seat\'s turn', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(3, 'host') });
    await assertSucceeds(update(ref(as('host')), append(count, [fire(3)], NEXT_TURN(0, 'host'))));
  });

  it('refuses a player who is not the turn holder, and a tank that is not theirs', async () => {
    await assertFails(update(ref(as('bob')), append(count, [fire(0)], NEXT_TURN(1, 'bob')))); // host's turn
    await assertFails(update(ref(as('bob')), append(count, [fire(1)], NEXT_TURN(0, 'host')))); // own seat, wrong turn
    await assertFails(update(ref(as('host')), append(count, [fire(1)]))); // tank 1 is bob's
    await assertFails(update(ref(as('host')), append(count, [fire(3)]))); // own seat but not the current tank
  });

  it('refuses outsiders, signed-out clients and writers when the match is not playing', async () => {
    await assertFails(update(ref(as('cat')), append(count, [fire(0)], NEXT_TURN(1, 'bob'))));
    await assertFails(update(ref(as('host')), { ...append(count, [fire(0)]), [`matches/${MID}/meta/status`]: 'lobby' }));
    for (const status of ['lobby', 'over', 'abandoned']) {
      await seed({ [`matches/${MID}/meta/status`]: status });
      await assertFails(update(ref(as('host')), append(count, [fire(0)])));
    }
  });

  it('refuses a human action for a CPU seat', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(2, 'cpu') });
    await assertFails(update(ref(as('host')), append(count, [fire(2)])));
    await assertFails(update(ref(as('bob')), append(count, [fire(2)])));
  });

  it('refuses a log entry without the actionCount bump, and a bump without an entry', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count}`]: fire(0) }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/actionCount`]: count + 1 }));
  });

  it('makes entries write-once: no overwrite, no delete, no rewind of the count', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/0`]: fire(0) }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/0`]: null }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count - 1}`]: fire(0), [`matches/${MID}/meta/actionCount`]: count }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/meta/actionCount`]: count - 1 }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions`]: null }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}`]: null }));
  });

  it('refuses to write over an entry that already sits in the next slot (a half-finished server timeout)', async () => {
    await seed({ [`matches/${MID}/actions/${count}`]: { kind: 'timeout', tank: 0 } });
    await assertFails(update(ref(as('host')), append(count, [fire(0)])));
  });

  it('requires consecutive indices: no gap, no skipped slot, no phantom count', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count + 1}`]: fire(0), [`matches/${MID}/meta/actionCount`]: count + 2 }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count}`]: fire(0), [`matches/${MID}/meta/actionCount`]: count + 2 }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count + 5}`]: fire(0), [`matches/${MID}/meta/actionCount`]: count + 1 }));
    await assertFails(update(ref(as('host')), { ...append(count, [fire(0)]), [`matches/${MID}/actions/${count + 3}`]: auto(2) }));
  });

  it('lets a stale writer lose: a second append at the same index is refused (optimistic concurrency)', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0)], NEXT_TURN(1, 'bob'))));
    await assertFails(update(ref(as('host')), append(count, [fire(0)], NEXT_TURN(1, 'bob', 5))));
  });

  it('lets one update carry the human action plus the CPU turns that follow', async () => {
    await assertSucceeds(update(ref(as('host')), append(count, [fire(0), auto(2), { kind: 'auto_shop', tank: 2, level: 2 }], NEXT_TURN(1, 'bob'))));
  });

  it('accepts a full batch of 16 entries and refuses 17', async () => {
    const sixteen = [fire(0), ...Array.from({ length: 15 }, () => auto(2))];
    await assertSucceeds(update(ref(as('host')), append(count, sixteen, NEXT_TURN(1, 'bob'))));
  });

  it('refuses a batch of 17 entries', async () => {
    const seventeen = [fire(0), ...Array.from({ length: 16 }, () => auto(2))];
    await assertFails(update(ref(as('host')), append(count, seventeen, NEXT_TURN(1, 'bob'))));
  });

  it('refuses a second human action in the same batch', async () => {
    await assertFails(update(ref(as('host')), append(count, [fire(0), fire(0)], NEXT_TURN(1, 'bob'))));
    await assertFails(update(ref(as('host')), append(count, [fire(0), { kind: 'pass', tank: 3 }], NEXT_TURN(1, 'bob'))));
  });

  it('lets auto entries target CPU seats only, and only after a first entry or when the turn needs resolving', async () => {
    await assertFails(update(ref(as('host')), append(count, [auto(2)], NEXT_TURN(1, 'bob')))); // j=0 while a human holds the turn
    await assertFails(update(ref(as('host')), append(count, [fire(0), auto(1)], NEXT_TURN(1, 'bob')))); // seat 1 is human
    await seed({ [`matches/${MID}/meta/turn`]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    await assertSucceeds(update(ref(as('bob')), append(count, [auto(2), auto(2)], NEXT_TURN(1, 'bob'))));
  });

  it('lets any member resolve a "needs resolve" turn, but refuses human actions while it is pending', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: { tank: -1, uid: 'any', deadline: 0, index: 3 } });
    await assertFails(update(ref(as('host')), append(count, [fire(0)], NEXT_TURN(1, 'bob'))));
    await assertSucceeds(update(ref(as('bob')), append(count, [{ kind: 'auto_shop', tank: 2, level: 2 }], NEXT_TURN(-2, 'any'))));
  });

  it('lets a CPU turn be played by any member when the turn is marked "cpu"', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(2, 'cpu') });
    await assertSucceeds(update(ref(as('bob')), append(count, [auto(2)], NEXT_TURN(0, 'host'))));
  });
});

describe('rules: action log - shop phase', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll({ turn: turnFor(-2, 'any') });
  });

  it('lets each player buy, sell and ready only for their own seats', async () => {
    await assertSucceeds(update(ref(as('bob')), append(count, [{ kind: 'buy', tank: 1, item: 'pulse_missile', qty: 2 }])));
    await assertSucceeds(update(ref(as('host')), append(count + 1, [{ kind: 'sell', tank: 0, item: 'pulse_missile', qty: 1 }])));
    await assertSucceeds(update(ref(as('host')), append(count + 2, [{ kind: 'ready', tank: 3 }])));
  });

  it('refuses shopping for somebody else\'s seat or a CPU seat, and from outside the match', async () => {
    await assertFails(update(ref(as('bob')), append(count, [{ kind: 'buy', tank: 0, item: 'pulse_missile', qty: 1 }])));
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'ready', tank: 1 }])));
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'ready', tank: 2 }])));
    await assertFails(update(ref(as('cat')), append(count, [{ kind: 'ready', tank: 1 }])));
  });

  it('lets one player batch several shop entries for their own seats, and a ready that starts the round', async () => {
    await assertSucceeds(
      update(ref(as('host')), append(count, [{ kind: 'buy', tank: 0, item: 'nova_core', qty: 1 }, { kind: 'ready', tank: 0 }, { kind: 'ready', tank: 3 }], NEXT_TURN(1, 'bob'))),
    );
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'ready', tank: 0 }, { kind: 'ready', tank: 1 }])));
  });

  it('refuses shop entries outside the shop phase and aim entries during it', async () => {
    await assertFails(update(ref(as('host')), append(count, [fire(0)])));
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(0, 'host') });
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'ready', tank: 0 }])));
  });

  it('lets a CPU shop visit be appended during the shop phase', async () => {
    await assertSucceeds(update(ref(as('bob')), append(count, [{ kind: 'auto_shop', tank: 2, level: 3 }])));
    await assertFails(update(ref(as('bob')), append(count, [{ kind: 'auto_shop', tank: 1, level: 3 }])));
  });
});

describe('rules: action log - timeouts', () => {
  useRulesEnv();
  let count = 0;
  // `async: 1` is the hard-deadline kind (the AI plays), without it a timeout is a live skip (ARCHITECTURE section 52).
  const asyncEntry = { kind: 'timeout', tank: 0, async: 1 };
  const liveEntry = { kind: 'timeout', tank: 0 };

  beforeEach(async () => {
    count = await seedAll({ turn: turnFor(0, 'host', 3, { deadline: Date.now() - 1000 }) }); // hard deadline passed
  });

  it('lets any member write an async timeout once the hard deadline has passed', async () => {
    await assertSucceeds(update(ref(as('bob')), append(count, [asyncEntry], { tank: -1, uid: 'any', deadline: 0, index: 4 })));
  });

  it('lets the same update carry the CPU turns that follow the timeout', async () => {
    await assertSucceeds(update(ref(as('bob')), append(count, [asyncEntry, auto(2)], NEXT_TURN(1, 'bob'))));
  });

  it('refuses an async timeout before the deadline, for the wrong tank, or from a non-member', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(0, 'host') });
    await assertFails(update(ref(as('bob')), append(count, [asyncEntry])));
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(0, 'host', 3, { deadline: Date.now() - 1000 }) });
    await assertFails(update(ref(as('bob')), append(count, [{ kind: 'timeout', tank: 1, async: 1 }])));
    await assertFails(update(ref(as('cat')), append(count, [asyncEntry])));
  });

  it('refuses a timeout without async after the hard deadline alone: that is not a live skip', async () => {
    await assertFails(update(ref(as('bob')), append(count, [liveEntry])));
  });

  it('accepts only async: 1 as the optional field', async () => {
    await assertFails(update(ref(as('bob')), append(count, [{ ...asyncEntry, async: 2 }])));
    await assertFails(update(ref(as('bob')), append(count, [{ ...asyncEntry, async: true }])));
    await assertFails(update(ref(as('bob')), append(count, [{ ...asyncEntry, level: 2 }])));
  });

  it('refuses an async field on any other kind of entry', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(0, 'host') });
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'pass', tank: 0, async: 1 }])));
  });

  it('refuses a timeout on a CPU seat', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(2, 'cpu', 3, { deadline: Date.now() - 1000 }) });
    await assertFails(update(ref(as('bob')), append(count, [{ kind: 'timeout', tank: 2, async: 1 }, auto(2)])));
  });

  it('allows a live skip after the live deadline only while the holder is online', async () => {
    const live = turnFor(0, 'host', 3, { deadline: Date.now() + HOUR, liveDeadline: Date.now() - 500 });
    await seed({ [`matches/${MID}/meta/turn`]: live });
    await assertFails(update(ref(as('bob')), append(count, [liveEntry]))); // no heartbeat at all
    await seed({ [`matches/${MID}/presence/host`]: Date.now() - 200000 });
    await assertFails(update(ref(as('bob')), append(count, [liveEntry]))); // stale heartbeat: only the async kind (after the hard deadline) is possible
    await seed({ [`matches/${MID}/presence/host`]: Date.now() - 1000 });
    await assertSucceeds(update(ref(as('bob')), append(count, [liveEntry], { tank: -1, uid: 'any', deadline: 0, index: 4 })));
  });

  it('does not let the live deadline stand in for the hard one: an async timeout still needs the hard deadline', async () => {
    const live = turnFor(0, 'host', 3, { deadline: Date.now() + HOUR, liveDeadline: Date.now() - 500 });
    await seed({ [`matches/${MID}/meta/turn`]: live, [`matches/${MID}/presence/host`]: Date.now() - 1000 });
    await assertFails(update(ref(as('bob')), append(count, [asyncEntry])));
  });

  it('refuses a live skip before the live deadline', async () => {
    await seed({
      [`matches/${MID}/meta/turn`]: turnFor(0, 'host', 3, { liveDeadline: Date.now() + 30000 }),
      [`matches/${MID}/presence/host`]: Date.now() - 1000,
    });
    await assertFails(update(ref(as('bob')), append(count, [liveEntry])));
  });

  it('lets a shop timeout (always async) target a human seat after the shop deadline', async () => {
    await seed({ [`matches/${MID}/meta/turn`]: turnFor(-2, 'any', 3, { deadline: Date.now() - 1000 }) });
    await assertSucceeds(update(ref(as('host')), append(count, [{ kind: 'timeout', tank: 1, async: 1 }])));
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'timeout', tank: 1 }])));
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'timeout', tank: 2, async: 1 }])));
  });
});

describe('rules: action log - entry shape and ranges', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll();
  });
  const tryWrite = (entryValue: Record<string, unknown>) => update(ref(as('host')), append(count, [entryValue]));

  it('accepts the smallest legal fire', async () => {
    await assertSucceeds(tryWrite({ kind: 'fire', tank: 0, angle: 0, power: 1, weapon: 'spark_dart' }));
  });

  it('accepts the other kinds with legal values (aim phase)', async () => {
    const legal = [
      { kind: 'move', tank: 0, dx: 200 },
      { kind: 'move', tank: 0, dx: -200 },
      { kind: 'use_item', tank: 0, item: 'glow_shield' },
      { kind: 'pass', tank: 0 },
      { kind: 'fire', tank: 0, angle: 1800, power: 1000, weapon: 'heart' },
    ];
    for (const [offset, value] of legal.entries()) {
      await assertSucceeds(update(ref(as('host')), append(count + offset, [value])));
    }
  });

  it('refuses out-of-range fire fields', async () => {
    for (const bad of [{ angle: -1 }, { angle: 1801 }, { power: 0 }, { power: 1001 }, { angle: 45.5 }, { power: 'strong' }, { angle: null }]) {
      await assertFails(tryWrite({ ...fire(0), ...bad }));
    }
  });

  it('refuses malformed weapon and item ids', async () => {
    for (const weapon of ['', 'Pulse', 'pulse missile', '../x', 'a'.repeat(33), 7, '1abc']) {
      await assertFails(tryWrite({ ...fire(0), weapon }));
    }
    await assertFails(tryWrite({ kind: 'use_item', tank: 0, item: 'Glow Shield' }));
  });

  it('refuses out-of-range move distances', async () => {
    for (const dx of [0, 201, -201, 1.5, '5']) await assertFails(tryWrite({ kind: 'move', tank: 0, dx }));
  });

  it('refuses a missing, extra or foreign field, an unknown kind and a bad tank', async () => {
    await assertFails(tryWrite({ kind: 'fire', tank: 0, angle: 45, power: 50 })); // no weapon
    await assertFails(tryWrite({ ...fire(0), extra: 1 }));
    await assertFails(tryWrite({ kind: 'pass', tank: 0, angle: 10 }));
    await assertFails(tryWrite({ kind: 'dance', tank: 0 }));
    await assertFails(tryWrite({ tank: 0 }));
    await assertFails(tryWrite({ kind: 'pass' }));
    await assertFails(tryWrite({ kind: 'pass', tank: -1 }));
    await assertFails(tryWrite({ kind: 'pass', tank: 8 }));
    await assertFails(tryWrite({ kind: 'pass', tank: '0' }));
    await assertFails(tryWrite({ kind: 'pass', tank: 0.5 }));
  });

  it('refuses a string or number where the entry should be an object', async () => {
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count}`]: 'fire', [`matches/${MID}/meta/actionCount`]: count + 1 }));
    await assertFails(update(ref(as('host')), { [`matches/${MID}/actions/${count}`]: 5, [`matches/${MID}/meta/actionCount`]: count + 1 }));
  });
});

describe('rules: action log - shop entry ranges and auto levels', () => {
  useRulesEnv();
  let count = 0;
  beforeEach(async () => {
    count = await seedAll({ turn: turnFor(-2, 'any') });
  });
  const shop = (entryValue: Record<string, unknown>) => update(ref(as('bob')), append(count, [entryValue]));

  it('limits buy and sell quantities to 1..99', async () => {
    await assertSucceeds(shop({ kind: 'buy', tank: 1, item: 'fuel_cell', qty: 99 }));
    for (const qty of [0, 100, -3, 2.5, '2']) {
      await assertFails(shop({ kind: 'buy', tank: 1, item: 'fuel_cell', qty }));
      await assertFails(shop({ kind: 'sell', tank: 1, item: 'fuel_cell', qty }));
    }
    await assertFails(shop({ kind: 'buy', tank: 1, item: 'fuel_cell' }));
  });

  it('limits CPU levels to 1..4', async () => {
    for (const level of [0, 5, 2.5, '2']) await assertFails(shop({ kind: 'auto_shop', tank: 2, level }));
    await assertSucceeds(shop({ kind: 'auto_shop', tank: 2, level: 4 }));
  });

  it('keeps seat data intact when a different seat layout is used', async () => {
    const seats: Seat[] = [...DEFAULT_SEATS.slice(0, 3)];
    await seed({ [`matches/${MID}/meta/seats`]: seats });
    await assertFails(update(ref(as('host')), append(count, [{ kind: 'ready', tank: 3 }])));
  });
});
