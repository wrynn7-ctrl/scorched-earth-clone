// Rules for users, friend codes, friend requests, friends, blocks, invites, reports (ARCHITECTURE section 44).
import { get } from 'firebase/database';
import {
  anonymous,
  as,
  assertFails,
  assertSucceeds,
  ref,
  seed,
  seedAll,
  seedUsers,
  set,
  update,
} from './helpers';
import { useRulesEnv } from './helpers';

describe('rules: users', () => {
  useRulesEnv();
  beforeEach(seedUsers);

  it('lets the owner read the whole profile, including server-only fields and push tokens', async () => {
    await seed({ 'users/bob/fcm/abcdefgh12': 'x'.repeat(30) });
    const snap = await assertSucceeds(get(ref(as('bob'), 'users/bob')));
    const value = snap.val() as Record<string, unknown>;
    for (const key of ['name', 'friendCode', 'full', 'protocol', 'nameHidden', 'fcm']) {
      if (!(key in value)) throw new Error(`missing ${key}`);
    }
  });

  it('refuses to show a whole profile to anyone else, or to a signed-out client', async () => {
    await assertFails(get(ref(as('cat'), 'users/bob')));
    await assertFails(get(ref(anonymous(), 'users/bob')));
    await assertFails(get(ref(as('cat'), 'users')));
  });

  it('shows the public fields (name, nameHidden, protocol) to any signed-in user', async () => {
    await assertSucceeds(get(ref(as('cat'), 'users/bob/name')));
    await assertSucceeds(get(ref(as('cat'), 'users/bob/nameHidden')));
    await assertSucceeds(get(ref(as('cat'), 'users/bob/protocol')));
    await assertFails(get(ref(anonymous(), 'users/bob/name')));
  });

  it('hides friendCode, full and push tokens from other users', async () => {
    await seed({ 'users/bob/fcm/abcdefgh12': 'x'.repeat(30) });
    await assertFails(get(ref(as('cat'), 'users/bob/friendCode')));
    await assertFails(get(ref(as('cat'), 'users/bob/full')));
    await assertFails(get(ref(as('cat'), 'users/bob/fcm')));
  });

  it('hides the public fields between a blocked pair, in both directions', async () => {
    await seed({ 'blocks/bob/cat': true });
    await assertFails(get(ref(as('cat'), 'users/bob/name'))); // cat is blocked by bob
    await assertFails(get(ref(as('bob'), 'users/cat/name'))); // bob blocked cat
    await assertFails(get(ref(as('cat'), 'users/bob/protocol')));
    await assertSucceeds(get(ref(as('host'), 'users/bob/name'))); // everyone else still sees it
  });

  it('lets the owner set a valid name and refuses invalid ones', async () => {
    await assertSucceeds(set(ref(as('bob'), 'users/bob/name'), 'Anna K'));
    await assertSucceeds(set(ref(as('bob'), 'users/bob/name'), 'TWELVE_CHARS'));
    await assertFails(set(ref(as('bob'), 'users/bob/name'), 'THIRTEEN_CHAR'));
    await assertFails(set(ref(as('bob'), 'users/bob/name'), ''));
    await assertFails(set(ref(as('bob'), 'users/bob/name'), 42));
    await assertFails(set(ref(as('bob'), 'users/bob/name'), null));
  });

  it('refuses name writes for other users and signed-out clients', async () => {
    await assertFails(set(ref(as('cat'), 'users/bob/name'), 'HIJACK'));
    await assertFails(set(ref(anonymous(), 'users/bob/name'), 'HIJACK'));
  });

  it('refuses a name write before the server created the profile', async () => {
    await assertFails(set(ref(as('dave'), 'users/dave/name'), 'DAVE'));
  });

  it('keeps server-only fields read-only for their owner', async () => {
    const db = as('bob');
    await assertFails(set(ref(db, 'users/bob/nameHidden'), false));
    await assertFails(set(ref(db, 'users/bob/full'), true));
    await assertFails(set(ref(db, 'users/bob/friendCode'), 'MYOWNCODE'));
    await assertFails(set(ref(db, 'users/bob/created'), 5));
    await assertFails(set(ref(db, 'users/bob'), { name: 'X', full: true }));
    await assertFails(update(ref(db), { 'users/bob/full': true }));
  });

  it('accepts a protocol number only', async () => {
    await assertSucceeds(set(ref(as('bob'), 'users/bob/protocol'), 3));
    await assertFails(set(ref(as('bob'), 'users/bob/protocol'), -1));
    await assertFails(set(ref(as('bob'), 'users/bob/protocol'), 1.5));
    await assertFails(set(ref(as('bob'), 'users/bob/protocol'), 'two'));
    await assertFails(set(ref(as('bob'), 'users/bob/protocol'), null));
    await assertFails(set(ref(as('cat'), 'users/bob/protocol'), 3));
  });

  it('lets the owner store and remove push tokens, with a hashed key and a token-sized value', async () => {
    const db = as('bob');
    await assertSucceeds(set(ref(db, 'users/bob/fcm/abcdefgh12'), 't'.repeat(100)));
    await assertSucceeds(set(ref(db, 'users/bob/fcm/abcdefgh12'), null));
    await assertFails(set(ref(db, 'users/bob/fcm/short'), 't'.repeat(100)));
    await assertFails(set(ref(db, 'users/bob/fcm/bad key !!'), 't'.repeat(100)));
    await assertFails(set(ref(db, 'users/bob/fcm/abcdefgh12'), 'tiny'));
    await assertFails(set(ref(as('cat'), 'users/bob/fcm/abcdefgh12'), 't'.repeat(100)));
  });
});

describe('rules: friends, requests, blocks, codes (written only by functions)', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedUsers();
    await seed({
      'friendCodes/BOBCODE22': 'bob',
      'friendRequests/bob/cat': { name: 'CAT', at: 1 },
      'friends/bob/host': { since: 1 },
      'friends/host/bob': { since: 1 },
      'blocks/bob/cat': true,
    });
  });

  it('lets users read only their own friend list, requests and blocks', async () => {
    await assertSucceeds(get(ref(as('bob'), 'friends/bob')));
    await assertSucceeds(get(ref(as('bob'), 'friendRequests/bob')));
    await assertSucceeds(get(ref(as('bob'), 'blocks/bob')));
    await assertFails(get(ref(as('cat'), 'friends/bob')));
    await assertFails(get(ref(as('cat'), 'friendRequests/bob')));
    await assertFails(get(ref(as('host'), 'blocks/bob')));
    await assertFails(get(ref(anonymous(), 'friends/bob')));
  });

  it('refuses every client write to friendships, requests and blocks, even for the owner', async () => {
    await assertFails(set(ref(as('bob'), 'friends/bob/cat'), { since: 2 }));
    await assertFails(set(ref(as('cat'), 'friends/bob/cat'), { since: 2 }));
    await assertFails(set(ref(as('bob'), 'friends/bob/host'), null));
    await assertFails(set(ref(as('host'), 'friendRequests/bob/host'), { name: 'HOST', at: 2 }));
    await assertFails(set(ref(as('bob'), 'friendRequests/bob/cat'), null));
    await assertFails(set(ref(as('bob'), 'blocks/bob/host'), true));
    await assertFails(set(ref(as('bob'), 'blocks/bob/cat'), null));
  });

  it('refuses a friend request between a blocked pair (and every other client write)', async () => {
    await assertFails(set(ref(as('cat'), 'friendRequests/bob/cat'), { name: 'CAT', at: 2 }));
    await assertFails(set(ref(as('bob'), 'friendRequests/cat/bob'), { name: 'BOB', at: 2 }));
  });

  it('refuses a client-written friend request even between two members of the same match (only the callable may)', async () => {
    await seed({
      'userMatches/host/m1': { updated: 1, yourTurn: false, status: 'lobby' },
      'userMatches/cat/m1': { updated: 1, yourTurn: false, status: 'lobby' },
    });
    await assertFails(set(ref(as('host'), 'friendRequests/cat/host'), { name: 'HOST', at: 2 }));
    await assertFails(set(ref(as('host'), 'sentRequests/host/cat'), true));
    await assertFails(set(ref(as('cat'), 'friends/cat/host'), { since: 2 }));
  });

  it('does not let clients read or write friend codes, to stop enumeration', async () => {
    await assertFails(get(ref(as('bob'), 'friendCodes/BOBCODE22')));
    await assertFails(get(ref(as('bob'), 'friendCodes')));
    await assertFails(set(ref(as('cat'), 'friendCodes/NEWCODE22'), 'cat'));
    await assertFails(set(ref(as('bob'), 'friendCodes/BOBCODE22'), 'cat'));
  });
});

describe('rules: invites', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedAll({ members: ['host'] });
    await seed({
      'friends/host/bob': { since: 1 },
      'friends/bob/host': { since: 1 },
      'invites/bob/M1': { fromUid: 'host', fromName: 'HOST', at: 1 },
    });
  });

  it('lets the recipient read and dismiss an invite', async () => {
    await assertSucceeds(get(ref(as('bob'), 'invites/bob')));
    await assertSucceeds(set(ref(as('bob'), 'invites/bob/M1'), null));
  });

  it('refuses other users reading or dismissing it', async () => {
    await assertFails(get(ref(as('cat'), 'invites/bob')));
    await assertFails(get(ref(as('host'), 'invites/bob')));
    await assertFails(set(ref(as('host'), 'invites/bob/M1'), null));
    await assertFails(set(ref(as('cat'), 'invites/bob/M1'), null));
  });

  it('refuses client-created invites: only the invite function checks membership, friendship and blocks', async () => {
    await assertFails(set(ref(as('host'), 'invites/bob/M2'), { fromUid: 'host', fromName: 'HOST', at: 2 }));
    await assertFails(set(ref(as('bob'), 'invites/bob/M2'), { fromUid: 'bob', fromName: 'BOB', at: 2 }));
    await assertFails(set(ref(as('host'), 'invites/cat/M1'), { fromUid: 'host', fromName: 'HOST', at: 2 }));
    await seed({ 'blocks/bob/host': true });
    await assertFails(set(ref(as('host'), 'invites/bob/M3'), { fromUid: 'host', fromName: 'HOST', at: 2 }));
  });
});

describe('rules: reports and server bookkeeping', () => {
  useRulesEnv();
  beforeEach(async () => {
    await seedUsers();
    await seed({
      'reports/r1': { reporterUid: 'bob', targetUid: 'cat', reason: 'offensive_name', at: 1 },
      'nameReports/cat/bob': true,
      'matchCodes/ABC234': 'M1',
      'sweepQueue/M1': 5,
      'purchaseTokens/h': 'host',
      '_test/fcm/p1': { uid: 'bob' },
    });
  });

  it('keeps reports private: nobody reads or writes them, and a report cannot be forged or erased', async () => {
    for (const path of ['reports', 'reports/r1', 'nameReports', 'nameReports/cat', 'nameReports/cat/bob']) {
      await assertFails(get(ref(as('bob'), path)));
      await assertFails(get(ref(as('cat'), path)));
    }
    await assertFails(set(ref(as('bob'), 'reports/r2'), { reporterUid: 'bob', targetUid: 'cat', reason: 'x', at: 2 }));
    await assertFails(set(ref(as('bob'), 'nameReports/cat/bob'), null));
    await assertFails(set(ref(as('host'), 'nameReports/cat/host'), true));
    await assertFails(set(ref(as('cat'), 'nameReports/cat'), null));
    await assertFails(set(ref(as('cat'), 'users/cat/nameHidden'), false));
  });

  it('keeps match codes, the sweep queue, purchase records and test data closed to clients', async () => {
    for (const path of ['matchCodes', 'matchCodes/ABC234', 'sweepQueue', 'sweepQueue/M1', 'purchaseTokens', '_test/fcm', 'invitesSent', 'sentRequests']) {
      await assertFails(get(ref(as('host'), path)));
    }
    await assertFails(set(ref(as('host'), 'matchCodes/ZZZ999'), 'M1'));
    await assertFails(set(ref(as('host'), 'matchCodes/ABC234'), null));
    await assertFails(set(ref(as('host'), 'sweepQueue/M1'), 0));
    await assertFails(set(ref(as('host'), 'purchaseTokens/h'), 'bob'));
    await assertFails(set(ref(as('host'), '_test/fcm/p2'), { uid: 'bob' }));
    await assertFails(set(ref(as('host')), { users: null }));
  });
});
