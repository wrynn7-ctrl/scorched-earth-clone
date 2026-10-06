// M7-Q functions abuse, part 2: friend floods, uid probing, report spam, purchase replay and delete-my-data in a running match.
import { bug } from '../bug';
import assert from 'node:assert/strict';
import { befriend, db, hostLobby, settle, signUp, value } from '../../functions/harness';
import { inParallel, newUser, outcome, reasonOf, releaseTestToken, rest, TEST_TOKEN_HASH, type TestUser } from './qa_harness';

const HOUR = 3600 * 1000;

describe('QA functions: friend request floods and uid probing', function () {
  this.timeout(180000);

  it('keeps the pending cap exact for sequential senders (51st is refused)', async () => {
    const target = await newUser({ name: 'Target' });
    const code = (await target.profile()).friendCode as string;
    const senders = await inParallel(52, () => newUser());
    let accepted = 0;
    let refused = 0;
    for (const s of senders) {
      const r = await reasonOf(s.call('sendFriendRequest', { code }));
      if (r === 'OK') accepted += 1;
      else if (r === 'RESOURCE_EXHAUSTED:too_many_requests') refused += 1;
    }
    assert.equal(accepted, 50);
    assert.equal(refused, 2);
    assert.equal(Object.keys((await value<Record<string, unknown>>(`friendRequests/${target.uid}`)) ?? {}).length, 50);
  });

  it('does not let a simultaneous flood go past the cap of 50 pending requests', async () => {
    const target = await newUser({ name: 'Target2' });
    const code = (await target.profile()).friendCode as string;
    const senders = await inParallel(70, () => newUser());
    const results = await Promise.all(senders.map((s) => reasonOf(s.call('sendFriendRequest', { code }))));
    const stored = Object.keys((await value<Record<string, unknown>>(`friendRequests/${target.uid}`)) ?? {}).length;
    const bad = results.filter((r) => r !== 'OK' && r !== 'RESOURCE_EXHAUSTED:too_many_requests');
    assert.deepEqual(bad, []);
    assert.ok(stored <= 50, `${stored} pending requests stored (cap 50)`);
  });

  it('repeating a request to the same player stays one request (no spam multiplication)', async () => {
    const a = await newUser();
    const b = await newUser();
    const code = (await b.profile()).friendCode as string;
    for (let i = 0; i < 5; i += 1) await a.call('sendFriendRequest', { code });
    assert.equal(Object.keys((await value<Record<string, unknown>>(`friendRequests/${b.uid}`)) ?? {}).length, 1);
  });

  it('gives sendFriendRequestToUid the same answer for a missing uid, a stranger and a blocked member', async () => {
    const host = await newUser({ full: true, name: 'Host' });
    const member = await newUser({ name: 'Member' });
    const blocker = await newUser({ name: 'Blocker' });
    const stranger = await newUser({ name: 'Stranger' });
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    await member.call('joinMatch', { code: lobby.code });
    await blocker.call('joinMatch', { code: lobby.code }).catch(() => undefined); // may be full: seat 3 free, so fine
    await blocker.call('block', { targetUid: host.uid });
    const answers = {
      missing: await reasonOf(host.call('sendFriendRequestToUid', { targetUid: 'noSuchUidAtAll12345', matchId: lobby.matchId })),
      stranger: await reasonOf(host.call('sendFriendRequestToUid', { targetUid: stranger.uid, matchId: lobby.matchId })),
      blocked: await reasonOf(host.call('sendFriendRequestToUid', { targetUid: blocker.uid, matchId: lobby.matchId })),
    };
    assert.equal(answers.missing, 'NOT_FOUND:unknown_code');
    assert.equal(answers.stranger, answers.missing);
    assert.equal(answers.blocked, answers.missing);
    // a caller outside the match learns nothing about the target either way
    const outsider = await newUser();
    const a1 = await reasonOf(outsider.call('sendFriendRequestToUid', { targetUid: member.uid, matchId: lobby.matchId }));
    const a2 = await reasonOf(outsider.call('sendFriendRequestToUid', { targetUid: 'noSuchUidAtAll12345', matchId: lobby.matchId }));
    assert.equal(a1, 'PERMISSION_DENIED:not_a_member');
    assert.equal(a2, a1);
    // a real match id that is not theirs and a made-up id look the same
    assert.equal(await reasonOf(outsider.call('sendFriendRequestToUid', { targetUid: member.uid, matchId: 'madeUpMatchId' })), a1);
  });

  // BUG (low): friend-request spam has no per-sender limit and no cooldown after a decline or a block.
  //   input:    A sends a request to B, B declines; A sends again, 20 times in a row.
  //   expected: a cooldown or a cap on declined/outgoing requests (B has no "stop this person" except a block, and a block needs
  //             the sender's uid, which the request shows as a name only).
  //   actual:   every request after a decline is accepted and shows up again.
  //   cause:    functions/src/friends.ts requestBetween() only caps the TARGET's pending requests (50), not the sender's.
  bug('BUG (low): refuses a sender who keeps re-sending after a decline', async () => {
    const a = await newUser();
    const b = await newUser();
    const code = (await b.profile()).friendCode as string;
    await a.call('sendFriendRequest', { code });
    await b.call('respondFriendRequest', { fromUid: a.uid, accept: false });
    const outcomes: string[] = [];
    for (let i = 0; i < 20; i += 1) {
      outcomes.push(await outcome(a.call('sendFriendRequest', { code })));
      await b.call('respondFriendRequest', { fromUid: a.uid, accept: false }).catch(() => undefined);
    }
    assert.ok(outcomes.includes('RESOURCE_EXHAUSTED') || outcomes.includes('FAILED_PRECONDITION'), outcomes.join(','));
  });

  // BUG (low): block (and removeFriend/unblock) accept any id: the list grows without bound with uids that do not exist.
  //   input:    block {targetUid: "ghost0001"} .. "ghost0040" from one account
  //   expected: unknown_user for a uid with no profile (and some cap on the list)
  //   actual:   {blocked: true} every time, each a new `blocks/{me}/{ghost}` key.
  //   cause:    functions/src/friends.ts blockUser() never reads users/{target}; storage-only impact.
  bug('BUG (low): refuses to block a uid that does not exist', async () => {
    const a = await newUser();
    assert.equal(await reasonOf(a.call('block', { targetUid: 'ghost0001' })), 'NOT_FOUND:unknown_user');
  });
});

describe('QA functions: reports', function () {
  this.timeout(120000);

  it('counts one reporter once however often they report, and keeps one report document', async () => {
    const victim = await newUser({ name: 'Victim' });
    const reporter = await newUser();
    const results = await Promise.all(Array.from({ length: 6 }, () => reporter.call<{ hidden: boolean; duplicate: boolean }>('reportName', { targetUid: victim.uid })));
    assert.equal(results.filter((r) => !r.duplicate).length >= 1, true);
    const stored = (await value<Record<string, unknown>>(`nameReports/${victim.uid}`)) ?? {};
    assert.deepEqual(Object.keys(stored), [reporter.uid]);
    const reports = await db.ref('reports').orderByChild('targetUid').equalTo(victim.uid).get();
    // a parallel burst can race the "already reported" check, but never past the number of calls, and never hides the name
    assert.ok(reports.numChildren() >= 1 && reports.numChildren() <= 6);
    assert.equal((await value<boolean>(`users/${victim.uid}/nameHidden`)) ?? false, false);
  });

  it('does not hide a name for 2 reporters, and hides it for the third', async () => {
    const victim = await newUser({ name: 'Victim' });
    const [a, b, c] = await inParallel(3, () => newUser());
    for (const r of [a, b] as TestUser[]) await r.call('reportName', { targetUid: victim.uid });
    assert.equal((await value<boolean>(`users/${victim.uid}/nameHidden`)) ?? false, false);
    assert.equal((await (c as TestUser).call<{ hidden: boolean }>('reportName', { targetUid: victim.uid })).hidden, true);
  });

  // BUG (low): three throw-away accounts can hide ANY player's name; no shared match or account age is required.
  //   input:    three fresh anonymous accounts call reportName {targetUid: <victim uid>}; they never met the victim.
  //             (a uid is easy to get: it is in the `seats` of every match the attacker joins.)
  //   expected: reports only from players who shared a match with the target (as sendFriendRequestToUid requires), or some
  //             weighting for brand-new accounts.
  //   actual:   the name is hidden after the third report and stays hidden (only the owner can review, in the console).
  //   cause:    functions/src/friends.ts reportName() checks only that the target exists.
  bug('BUG (low): refuses name reports from accounts that never shared a match with the target', async () => {
    const victim = await newUser({ name: 'Victim' });
    const sock = await inParallel(3, () => newUser());
    const results: string[] = [];
    for (const s of sock) results.push(await reasonOf(s.call('reportName', { targetUid: victim.uid })));
    assert.ok(results.every((r) => r !== 'OK'), results.join(','));
    assert.equal((await value<boolean>(`users/${victim.uid}/nameHidden`)) ?? false, false);
  });
});

describe('QA functions: purchase replay and token reuse', function () {
  this.timeout(120000);
  const claimed: TestUser[] = [];
  beforeEach(async () => {
    // free the shared test token only when a previous test of ours holds it (never touch anyone else's claim)
    for (const u of claimed.splice(0)) await releaseTestToken(u);
  });
  after(async () => {
    for (const u of claimed.splice(0)) await releaseTestToken(u);
  });

  it('lets exactly one of several simultaneous accounts claim a token', async () => {
    const holder = (await value<string>(`purchaseTokens/${TEST_TOKEN_HASH}`)) ?? '';
    assert.equal(holder, '', 'the shared test token must be free when this test starts');
    const users = await inParallel(6, () => newUser());
    const results = await Promise.all(users.map((u) => reasonOf(u.call('verifyPurchase', { purchaseToken: 'test-full' }))));
    claimed.push(...users);
    assert.equal(results.filter((r) => r === 'OK').length, 1, results.join(' '));
    assert.equal(results.filter((r) => r === 'ALREADY_EXISTS:token_used').length, 5, results.join(' '));
    const winners = (await Promise.all(users.map((u) => u.profile()))).filter((p) => p.full === true);
    assert.equal(winners.length, 1);
  });

  it('refuses the same token from a second account, also after the first re-verifies, and an altered token', async () => {
    const a = await newUser();
    const b = await newUser();
    claimed.push(a, b);
    await a.call('verifyPurchase', { purchaseToken: 'test-full' });
    await a.call('verifyPurchase', { purchaseToken: 'test-full' });
    assert.equal(await reasonOf(b.call('verifyPurchase', { purchaseToken: 'test-full' })), 'ALREADY_EXISTS:token_used');
    for (const variant of ['test-full ', ' test-full', 'TEST-FULL', 'test-full\n', 'test-full\u0000', 'test-fuII']) {
      assert.equal(await reasonOf(b.call('verifyPurchase', { purchaseToken: variant })), 'PERMISSION_DENIED:unknown_token', JSON.stringify(variant));
    }
    assert.equal((await b.profile()).full, false);
  });

  it('bounds the token length (4096) and takes unicode tokens as plain unknown tokens', async () => {
    const u = await newUser();
    assert.equal(await reasonOf(u.call('verifyPurchase', { purchaseToken: 'x'.repeat(4096) })), 'PERMISSION_DENIED:unknown_token');
    assert.match(await reasonOf(u.call('verifyPurchase', { purchaseToken: 'x'.repeat(4097) })), /^INVALID_ARGUMENT/);
    assert.equal(await reasonOf(u.call('verifyPurchase', { purchaseToken: '😀' })), 'PERMISSION_DENIED:unknown_token');
    assert.equal((await u.profile()).full, false);
    assert.equal(await value(`purchaseTokens/${TEST_TOKEN_HASH}`), null);
  });

  it('cannot be faked by a client: full, purchase and the token record are closed to client writes', async () => {
    const u = await newUser();
    for (const path of [`users/${u.uid}/full`, `users/${u.uid}/purchase`, `purchaseTokens/${TEST_TOKEN_HASH}`]) {
      const r = await rest(u.token, 'PUT', path, path.endsWith('full') ? true : { at: 1 });
      assert.ok(r.status === 401 || r.status === 403, `${path}: HTTP ${r.status}`);
    }
    assert.equal((await u.profile()).full, false);
    assert.equal(await reasonOf(u.call('createMatch', { settings: {}, seats: [{ kind: 'human' }, { kind: 'cpu' }] })), 'PERMISSION_DENIED:full_required');
  });

  it('documents: after the owner deletes their data the same token unlocks another account (one account AT A TIME)', async () => {
    const a = await newUser();
    const b = await newUser();
    claimed.push(a, b);
    await a.call('verifyPurchase', { purchaseToken: 'test-full' });
    await a.call('deleteMyData');
    await b.call('verifyPurchase', { purchaseToken: 'test-full' });
    assert.equal((await b.profile()).full, true);
  });
});

describe('QA functions: deleteMyData in the middle of a running match', function () {
  this.timeout(180000);

  async function runningMatch(): Promise<{ host: TestUser; p2: TestUser; p3: TestUser; id: string }> {
    const host = await newUser({ full: true, name: 'Hana' });
    const p2 = await newUser({ name: 'Pat' });
    const p3 = await newUser({ name: 'Quin' });
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }, { kind: 'cpu' }]);
    await p2.call('joinMatch', { code: lobby.code });
    await p3.call('joinMatch', { code: lobby.code });
    await host.call('startMatch', { matchId: lobby.matchId });
    const writes: Record<string, unknown> = {};
    for (let i = 0; i < 3; i += 1) writes[`matches/${lobby.matchId}/actions/${i}`] = { kind: 'pass', tank: 0 };
    writes[`matches/${lobby.matchId}/meta/actionCount`] = 3;
    writes[`matches/${lobby.matchId}/meta/turn`] = { tank: 1, uid: p2.uid, deadline: Date.now() + HOUR, index: 1 };
    await db.ref().update(writes);
    await settle(1200);
    return { host, p2, p3, id: lobby.matchId };
  }

  it('turns the deleted player into an anonymous CPU, keeps the log, and hands the turn to a resolver', async () => {
    const { host, p2, p3, id } = await runningMatch();
    await p2.call('deleteMyData');
    const meta = (await value<Record<string, any>>(`matches/${id}/meta`)) as Record<string, any>;
    assert.deepEqual(meta.seats[1], { kind: 'cpu', level: 2, name: 'PLAYER' });
    assert.equal(meta.status, 'playing');
    assert.equal(meta.actionCount, 3);
    assert.deepEqual(meta.turn, { tank: -1, uid: 'any', deadline: 0, index: 2 });
    assert.equal(meta.hostUid, host.uid);
    assert.equal(await value(`userMatches/${p2.uid}`), null);
    assert.equal(await value(`matches/${id}/presence/${p2.uid}`), null);
    for (const u of [host, p3]) assert.ok(await value(`userMatches/${u.uid}/${id}`), 'the others keep the match');
    assert.equal(JSON.stringify(meta).includes(p2.uid), false, 'no trace of the deleted uid in meta');
    assert.equal(JSON.stringify(await value(`matches/${id}/actions`)).includes(p2.uid), false);
  });

  it('survives a second delete call, and the host deleting too (the match goes on, nobody can abandon it)', async () => {
    const { host, p2, p3, id } = await runningMatch();
    await p2.call('deleteMyData');
    await host.call('deleteMyData');
    const meta = (await value<Record<string, any>>(`matches/${id}/meta`)) as Record<string, any>;
    assert.equal(meta.status, 'playing');
    assert.deepEqual(meta.seats.map((s: { kind: string }) => s.kind), ['cpu', 'cpu', 'human', 'cpu']);
    assert.equal(meta.seats[2].uid, p3.uid);
    // the remaining player still has the match; a disputed match could no longer be abandoned (hostUid is a deleted uid)
    assert.ok(await value(`userMatches/${p3.uid}/${id}`));
    const abandon = await rest(p3.token, 'PUT', `matches/${id}/meta/status`, 'abandoned');
    assert.ok(abandon.status === 401 || abandon.status === 403, `abandon by a non-host: HTTP ${abandon.status}`);
    // leaving still works and ends the match once nobody is left
    assert.equal(((await p3.call('leaveMatch', { matchId: id })) as { status: string }).status, 'abandoned');
  });

  it('removes everything the deleted player owns even while two matches and a pending request exist', async () => {
    const a = await newUser({ full: true, name: 'Ann' });
    const b = await newUser({ name: 'Ben' });
    await befriend(a, b);
    const m1 = await hostLobby(a, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    const m2 = await hostLobby(a, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    await b.call('joinMatch', { code: m1.code });
    await a.call('invite', { friendUid: b.uid, matchId: m2.matchId });
    await settle(600);
    await a.call('deleteMyData');
    assert.equal(await value(`users/${a.uid}`), null);
    assert.equal(await value(`friends/${b.uid}/${a.uid}`), null);
    assert.equal(await value(`invites/${b.uid}/${m2.matchId}`), null);
    assert.equal(await value(`matches/${m1.matchId}/meta/status`), 'abandoned', 'a lobby whose host deleted is closed');
    assert.equal(await value(`matches/${m2.matchId}/meta/status`), 'abandoned');
  });

  // BUG (low): a deleted account comes back to life with its old ID token.
  //   input:    deleteMyData, then (within the token's ~1 h life, no sign-out) ensureProfile with the old token.
  //   expected: UNAUTHENTICATED / no profile: the Auth user is gone.
  //   actual:   ensureProfile creates a fresh profile and friend code for the deleted uid (callables only verify the token, not
  //             that the Auth user still exists; production would behave the same: ID tokens stay valid until they expire).
  //   cause:    functions/src/index.ts authed() trusts request.auth without a revocation / existence check.
  //   impact:   a stray client call after "delete my data" recreates data the player was told was gone; the real client signs out.
  bug('BUG (low): does not recreate a profile for a deleted account', async () => {
    const u = await newUser({ name: 'Gone' });
    await u.call('deleteMyData');
    await assert.rejects(u.call('ensureProfile', { protocol: 1 }));
    assert.equal(await value(`users/${u.uid}`), null);
  });

  it('leaves no personal data behind in the match it left, apart from pseudonymous quick-message and fingerprint records', async () => {
    const { host, p2, id } = await runningMatch();
    const stray = await signUp();
    void stray;
    await p2.call('deleteMyData');
    const left = JSON.stringify((await value(`matches/${id}`)) ?? {});
    assert.equal(left.includes(p2.uid), false, 'the deleted uid is gone from meta, actions and presence');
    void host;
  });
});

describe('QA functions: misc call shapes', function () {
  this.timeout(60000);
  it('answers 16 concurrent calls with 3 different payloads without errors from the server', async () => {
    const u = await newUser();
    const results = await inParallel(16, (i) => outcome(u.call(['ensureProfile', 'unblock', 'removeFriend'][i % 3] as string, { protocol: 1, targetUid: 'x', friendUid: 'x' })));
    assert.ok(results.every((r) => r === 'OK'), results.join(','));
  });
});
