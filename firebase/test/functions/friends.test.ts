// Friend requests, friendships, blocks and name reports (ARCHITECTURE section 44), including blocks in both directions.
import assert from 'node:assert/strict';
import { befriend, type CallError, db, eventually, fcmFor, hostLobby, newUser, settle, signUp, value, type TestUser } from './harness';

const code = async (user: TestUser): Promise<string> => (await user.profile()).friendCode as string;
const status = (s: string) => (e: CallError) => e.status === s;
const reason = (s: string, r: string) => (e: CallError) => e.status === s && e.reason === r;

describe('functions: friend requests', () => {
  it('sends a request by code (any case, extra spaces), which the other player can accept', async () => {
    const [ann, ben] = [await newUser({ name: 'Ann' }), await newUser({ name: 'Ben' })];
    const sent = await ann.call<{ status: string; name: string }>('sendFriendRequest', { code: ` ${(await code(ben)).toLowerCase()} ` });
    assert.deepEqual(sent, { status: 'sent', name: 'Ben' });
    const pending = (await value<Record<string, { name: string; at: number }>>(`friendRequests/${ben.uid}`)) ?? {};
    assert.equal(pending[ann.uid]?.name, 'Ann');
    assert.equal(await value(`sentRequests/${ann.uid}/${ben.uid}`), true);

    assert.deepEqual(await ben.call('respondFriendRequest', { fromUid: ann.uid, accept: true }), { status: 'accepted' });
    const ab = await value<{ since: number; by: string }>(`friends/${ann.uid}/${ben.uid}`);
    const ba = await value<{ since: number; by: string }>(`friends/${ben.uid}/${ann.uid}`);
    assert.equal(ab?.by, ben.uid);
    assert.equal(ba?.by, ben.uid);
    assert.equal(typeof ab?.since, 'number');
    assert.equal(await value(`friendRequests/${ben.uid}/${ann.uid}`), null);
    assert.equal(await value(`sentRequests/${ann.uid}/${ben.uid}`), null);
  });

  it('declining removes the request and makes no friendship', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await ann.call('sendFriendRequest', { code: await code(ben) });
    assert.deepEqual(await ben.call('respondFriendRequest', { fromUid: ann.uid, accept: false }), { status: 'declined' });
    assert.equal(await value(`friends/${ann.uid}/${ben.uid}`), null);
    assert.equal(await value(`friendRequests/${ben.uid}/${ann.uid}`), null);
    assert.equal(await value(`sentRequests/${ann.uid}/${ben.uid}`), null);
  });

  it('after a decline the sender may not ask the same player again for 24 hours, but may ask anyone else', async () => {
    const [ann, ben, cy] = [await newUser(), await newUser(), await newUser()];
    await ann.call('sendFriendRequest', { code: await code(ben) });
    await ben.call('respondFriendRequest', { fromUid: ann.uid, accept: false });
    await assert.rejects(ann.call('sendFriendRequest', { code: await code(ben) }), reason('RESOURCE_EXHAUSTED', 'request_cooldown'));
    assert.equal(await value(`friendRequests/${ben.uid}/${ann.uid}`), null, 'nothing was written');
    await ann.call('sendFriendRequest', { code: await code(cy) }); // per pair
    // a day later it works again
    await db.ref(`friendCooldowns/${ann.uid}/${ben.uid}`).set(Date.now() - 25 * 3600 * 1000);
    assert.equal((await ann.call<{ status: string }>('sendFriendRequest', { code: await code(ben) })).status, 'sent');
  });

  it('a request the decliner sends back becomes a friendship once accepted, which ends the cooldown', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await ann.call('sendFriendRequest', { code: await code(ben) });
    await ben.call('respondFriendRequest', { fromUid: ann.uid, accept: false });
    assert.ok(await value(`friendCooldowns/${ann.uid}/${ben.uid}`));
    assert.ok(await value(`friendCooldownsBy/${ben.uid}/${ann.uid}`));
    await ben.call('sendFriendRequest', { code: await code(ann) });
    await ann.call('respondFriendRequest', { fromUid: ben.uid, accept: true });
    assert.equal(await value(`friends/${ann.uid}/${ben.uid}`) !== null, true);
    assert.equal(await value(`friendCooldowns/${ann.uid}/${ben.uid}`), null, 'being friends ends the cooldown');
    assert.equal(await value(`friendCooldownsBy/${ben.uid}/${ann.uid}`), null);
  });

  it('turns two requests that cross into a friendship', async () => {
    const [ann, ben] = [await newUser({ name: 'Ann' }), await newUser({ name: 'Ben' })];
    await ann.call('sendFriendRequest', { code: await code(ben) });
    const answer = await ben.call<{ status: string; friendUid: string }>('sendFriendRequest', { code: await code(ann) });
    assert.equal(answer.status, 'friends');
    assert.equal(answer.friendUid, ann.uid);
    assert.ok(await value(`friends/${ann.uid}/${ben.uid}`));
    assert.ok(await value(`friends/${ben.uid}/${ann.uid}`));
    assert.equal(await value(`friendRequests/${ben.uid}/${ann.uid}`), null);
    assert.equal(await value(`friendRequests/${ann.uid}/${ben.uid}`), null);
  });

  it('refuses unknown, malformed and own codes, and repeating a friendship', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await assert.rejects(ann.call('sendFriendRequest', { code: 'ZZZZZZZZ' }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ann.call('sendFriendRequest', { code: 'SHORT' }), status('INVALID_ARGUMENT'));
    await assert.rejects(ann.call('sendFriendRequest', { code: 'OOOO1111' }), status('INVALID_ARGUMENT')); // letters/digits outside the alphabet
    await assert.rejects(ann.call('sendFriendRequest', {}), status('INVALID_ARGUMENT'));
    await assert.rejects(ann.call('sendFriendRequest', { code: await code(ann) }), reason('FAILED_PRECONDITION', 'own_code'));
    await befriend(ann, ben);
    await assert.rejects(ann.call('sendFriendRequest', { code: await code(ben) }), reason('ALREADY_EXISTS', 'already_friends'));
  });

  it('refuses a response with no request, and signed-out or profile-less callers', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await assert.rejects(ben.call('respondFriendRequest', { fromUid: ann.uid, accept: true }), reason('NOT_FOUND', 'no_request'));
    await assert.rejects(ben.call('respondFriendRequest', { fromUid: ann.uid }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('respondFriendRequest', { fromUid: '../x', accept: true }), status('INVALID_ARGUMENT'));
    const bare = await signUp();
    await assert.rejects(bare.call('sendFriendRequest', { code: await code(ann) }), reason('FAILED_PRECONDITION', 'no_profile'));
  });

  it('limits how many requests one player can have waiting', async () => {
    const [ann, target] = [await newUser(), await newUser()];
    const seeded: Record<string, unknown> = {};
    for (let i = 0; i < 50; i += 1) seeded[`friendRequests/${target.uid}/fake${i}`] = { name: `F${i}`, at: 1 };
    await db.ref().update(seeded);
    await assert.rejects(ann.call('sendFriendRequest', { code: await code(target) }), reason('RESOURCE_EXHAUSTED', 'too_many_requests'));
  });

  it('removeFriend ends the friendship on both sides, and is harmless to repeat', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await befriend(ann, ben);
    await ann.call('removeFriend', { friendUid: ben.uid });
    assert.equal(await value(`friends/${ann.uid}/${ben.uid}`), null);
    assert.equal(await value(`friends/${ben.uid}/${ann.uid}`), null);
    await ann.call('removeFriend', { friendUid: ben.uid });
    await assert.rejects(ann.call('removeFriend', { friendUid: 'a/b' }), status('INVALID_ARGUMENT'));
  });

  it('tells the requester (and only the requester) when their request is accepted', async () => {
    const [ann, ben] = [await newUser({ name: 'Ann' }), await newUser({ name: 'Ben' })];
    await ann.registerPushToken();
    await ben.registerPushToken();
    await befriend(ann, ben);
    await eventually(async () => (await fcmFor(ann.uid)).length === 1, 'push to the requester');
    const [push] = await fcmFor(ann.uid);
    assert.equal(push?.body, 'Ben accepted your friend request');
    assert.equal(push?.data.type, 'friend');
    await settle();
    assert.equal((await fcmFor(ben.uid)).length, 0, 'the player who accepted gets nothing');
  });

  it('sends nothing for a friendship when the requester has no push token', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await befriend(ann, ben);
    await settle();
    assert.equal((await fcmFor(ann.uid)).length, 0);
  });
});

describe('functions: friend request by uid (shared match)', () => {
  /** Host plus a joiner in one lobby. */
  async function sharedMatch(host: TestUser, guest: TestUser): Promise<string> {
    const { matchId, code: matchCode } = await hostLobby(host);
    await guest.call('joinMatch', { code: matchCode });
    return matchId;
  }

  it('sends a request between two members, same result shape as by code, and the target can accept', async () => {
    const [ann, ben] = [await newUser({ name: 'Ann', full: true }), await newUser({ name: 'Ben' })];
    const matchId = await sharedMatch(ann, ben);
    const sent = await ben.call<{ status: string; name: string }>('sendFriendRequestToUid', { targetUid: ann.uid, matchId });
    assert.deepEqual(sent, { status: 'sent', name: 'Ann' });
    const pending = (await value<Record<string, { name: string }>>(`friendRequests/${ann.uid}`)) ?? {};
    assert.equal(pending[ben.uid]?.name, 'Ben');
    assert.equal(await value(`sentRequests/${ben.uid}/${ann.uid}`), true);
    assert.deepEqual(await ann.call('respondFriendRequest', { fromUid: ben.uid, accept: true }), { status: 'accepted' });
    assert.ok(await value(`friends/${ann.uid}/${ben.uid}`));
  });

  it('turns a crossing request into a friendship, and repeating a friendship is refused', async () => {
    const [ann, ben] = [await newUser({ name: 'Ann', full: true }), await newUser({ name: 'Ben' })];
    const matchId = await sharedMatch(ann, ben);
    await ann.call('sendFriendRequest', { code: await code(ben) });
    const answer = await ben.call<{ status: string; friendUid: string }>('sendFriendRequestToUid', { targetUid: ann.uid, matchId });
    assert.equal(answer.status, 'friends');
    assert.equal(answer.friendUid, ann.uid);
    assert.ok(await value(`friends/${ben.uid}/${ann.uid}`));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('ALREADY_EXISTS', 'already_friends'));
  });

  it('refuses when the caller is not in the match, or the target is not (neutral unknown_code)', async () => {
    const [ann, ben, cy] = [await newUser({ full: true }), await newUser(), await newUser()];
    const matchId = await sharedMatch(ann, ben);
    await assert.rejects(cy.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('PERMISSION_DENIED', 'not_a_member'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: cy.uid, matchId }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: 'nobody123', matchId }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId: 'nomatch123' }), reason('PERMISSION_DENIED', 'not_a_member'));
    assert.equal(await value(`friendRequests/${cy.uid}/${ben.uid}`), null);
  });

  it('refuses a player who left the match', async () => {
    const [ann, ben] = [await newUser({ full: true }), await newUser()];
    const matchId = await sharedMatch(ann, ben);
    await ben.call('leaveMatch', { matchId });
    await assert.rejects(ann.call('sendFriendRequestToUid', { targetUid: ben.uid, matchId }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('PERMISSION_DENIED', 'not_a_member'));
  });

  it('gives a blocked pair (either direction) the same neutral error as an unknown code, and writes nothing', async () => {
    const [ann, ben] = [await newUser({ full: true }), await newUser()];
    const matchId = await sharedMatch(ann, ben);
    await ann.call('block', { targetUid: ben.uid });
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('NOT_FOUND', 'unknown_code'));
    await assert.rejects(ann.call('sendFriendRequestToUid', { targetUid: ben.uid, matchId }), reason('NOT_FOUND', 'unknown_code'));
    assert.equal(await value(`friendRequests/${ann.uid}/${ben.uid}`), null);
    assert.equal(await value(`friendRequests/${ben.uid}/${ann.uid}`), null);
  });

  it('refuses malformed arguments, own uid and profile-less callers', async () => {
    const [ann, ben] = [await newUser({ full: true }), await newUser()];
    const matchId = await sharedMatch(ann, ben);
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ben.uid, matchId }), reason('FAILED_PRECONDITION', 'self'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { matchId }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: '../x', matchId }), status('INVALID_ARGUMENT'));
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId: 'a/b' }), status('INVALID_ARGUMENT'));
    const bare = await signUp();
    await assert.rejects(bare.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('FAILED_PRECONDITION', 'no_profile'));
  });

  it('respects the pending-request cap', async () => {
    const [ann, ben] = [await newUser({ full: true }), await newUser()];
    const matchId = await sharedMatch(ann, ben);
    const seeded: Record<string, unknown> = {};
    for (let i = 0; i < 50; i += 1) seeded[`friendRequests/${ann.uid}/fake${i}`] = { name: `F${i}`, at: 1 };
    await db.ref().update(seeded);
    await assert.rejects(ben.call('sendFriendRequestToUid', { targetUid: ann.uid, matchId }), reason('RESOURCE_EXHAUSTED', 'too_many_requests'));
  });
});

describe('functions: blocks', () => {
  it('records a block, and unblocking removes it', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await ann.call('block', { targetUid: ben.uid });
    assert.equal(await value(`blocks/${ann.uid}/${ben.uid}`), true);
    await ann.call('unblock', { targetUid: ben.uid });
    assert.equal(await value(`blocks/${ann.uid}/${ben.uid}`), null);
  });

  it('removes the friendship and every pending request, both ways', async () => {
    const [ann, ben, cy] = [await newUser(), await newUser(), await newUser()];
    await befriend(ann, ben);
    await ann.call('sendFriendRequest', { code: await code(cy) }); // ann -> cy pending
    await cy.call('block', { targetUid: ann.uid }); // cy blocks ann: request from ann disappears
    assert.equal(await value(`friendRequests/${cy.uid}/${ann.uid}`), null);
    assert.equal(await value(`sentRequests/${ann.uid}/${cy.uid}`), null);

    await cy.call('sendFriendRequest', { code: await code(ben) }); // cy -> ben pending
    await ben.call('block', { targetUid: cy.uid }); // ben blocks cy
    assert.equal(await value(`friendRequests/${ben.uid}/${cy.uid}`), null);

    await ann.call('block', { targetUid: ben.uid }); // ann blocks the friend ben
    assert.equal(await value(`friends/${ann.uid}/${ben.uid}`), null);
    assert.equal(await value(`friends/${ben.uid}/${ann.uid}`), null);
  });

  it('removes invites in both directions', async () => {
    const [host, ben] = [await newUser({ full: true }), await newUser()];
    await befriend(host, ben);
    const { matchId } = await hostLobby(host);
    await host.call('invite', { friendUid: ben.uid, matchId });
    assert.ok(await value(`invites/${ben.uid}/${matchId}`));
    await ben.call('block', { targetUid: host.uid });
    assert.equal(await value(`invites/${ben.uid}/${matchId}`), null);
    assert.equal(await value(`invitesSent/${host.uid}/${matchId}/${ben.uid}`), null);
  });

  it('removes an invite the blocker sent, too', async () => {
    const [host, ben] = [await newUser({ full: true }), await newUser()];
    await befriend(host, ben);
    const { matchId } = await hostLobby(host);
    await host.call('invite', { friendUid: ben.uid, matchId });
    await host.call('block', { targetUid: ben.uid });
    assert.equal(await value(`invites/${ben.uid}/${matchId}`), null);
  });

  it('hides a blocked pair from each other: a friend request looks like an unknown code, in both directions', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await ann.call('block', { targetUid: ben.uid });
    await assert.rejects(ben.call('sendFriendRequest', { code: await code(ann) }), reason('NOT_FOUND', 'unknown_code')); // the blocked player
    await assert.rejects(ann.call('sendFriendRequest', { code: await code(ben) }), reason('NOT_FOUND', 'unknown_code')); // the blocker
    await ann.call('unblock', { targetUid: ben.uid });
    assert.equal((await ben.call<{ status: string }>('sendFriendRequest', { code: await code(ann) })).status, 'sent');
  });

  it('cannot be dodged by accepting an old request after the block', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await ann.call('sendFriendRequest', { code: await code(ben) });
    // A request that somehow survived (written by hand) still cannot become a friendship.
    await ben.call('block', { targetUid: ann.uid });
    await db.ref(`friendRequests/${ben.uid}/${ann.uid}`).set({ name: 'x', at: 1 });
    await assert.rejects(ben.call('respondFriendRequest', { fromUid: ann.uid, accept: true }), reason('NOT_FOUND', 'no_request'));
    assert.equal(await value(`friends/${ann.uid}/${ben.uid}`), null);
  });

  it('refuses to block yourself and bad ids', async () => {
    const ann = await newUser();
    await assert.rejects(ann.call('block', { targetUid: ann.uid }), reason('FAILED_PRECONDITION', 'self'));
    await assert.rejects(ann.call('block', {}), status('INVALID_ARGUMENT'));
    await assert.rejects(ann.call('block', { targetUid: 'a.b' }), status('INVALID_ARGUMENT'));
  });
});

describe('functions: reportName', () => {
  /** A fresh player who knows `target` (a friend), as a reporter must. */
  const friendOf = async (target: Awaited<ReturnType<typeof newUser>>): Promise<Awaited<ReturnType<typeof newUser>>> => {
    const reporter = await newUser();
    await befriend(reporter, target);
    return reporter;
  };

  it('hides a name after reports from 3 different players, and not before', async () => {
    const target = await newUser({ name: 'Rude' });
    const [r1, r2, r3] = [await friendOf(target), await friendOf(target), await friendOf(target)];
    assert.deepEqual(await r1.call('reportName', { targetUid: target.uid, reason: 'offensive_name' }), { hidden: false, duplicate: false });
    assert.deepEqual(await r2.call('reportName', { targetUid: target.uid }), { hidden: false, duplicate: false });
    assert.equal((await target.profile()).nameHidden, false);
    assert.deepEqual(await r3.call('reportName', { targetUid: target.uid }), { hidden: true, duplicate: false });
    assert.equal((await target.profile()).nameHidden, true);
    assert.equal(Object.keys((await value<Record<string, boolean>>(`nameReports/${target.uid}`)) ?? {}).length, 3);
  });

  it('counts one player once, however often they report', async () => {
    const target = await newUser();
    const [r1, r2] = [await friendOf(target), await friendOf(target)];
    await r1.call('reportName', { targetUid: target.uid });
    const again = await r1.call<{ duplicate: boolean; hidden: boolean }>('reportName', { targetUid: target.uid });
    assert.deepEqual(again, { hidden: false, duplicate: true });
    await r1.call('reportName', { targetUid: target.uid });
    await r2.call('reportName', { targetUid: target.uid });
    assert.equal((await target.profile()).nameHidden, false, 'two distinct reporters are not enough');
    const reports = await db.ref('reports').orderByChild('targetUid').equalTo(target.uid).get();
    assert.equal(reports.numChildren(), 2, 'a repeat is not recorded again');
  });

  it('stores what the reviewer needs: reporter, target, reason, the reported name, time', async () => {
    const target = await newUser({ name: 'Rudeman' });
    const reporter = await friendOf(target);
    await reporter.call('reportName', { targetUid: target.uid, reason: 'offensive_name' });
    const reports = await db.ref('reports').orderByChild('targetUid').equalTo(target.uid).get();
    const [report] = Object.values(reports.val() as Record<string, Record<string, unknown>>);
    assert.equal(report?.reporterUid, reporter.uid);
    assert.equal(report?.targetUid, target.uid);
    assert.equal(report?.reason, 'offensive_name');
    assert.equal(report?.name, 'Rudeman');
    assert.equal(typeof report?.at, 'number');
  });

  it('refuses self-reports, unknown players and a bad reason', async () => {
    const [ann, ben] = [await newUser(), await newUser()];
    await befriend(ann, ben);
    await assert.rejects(ann.call('reportName', { targetUid: ann.uid }), reason('FAILED_PRECONDITION', 'self'));
    await assert.rejects(ann.call('reportName', { targetUid: 'nobody123' }), reason('NOT_FOUND', 'unknown_user'));
    await assert.rejects(ann.call('reportName', { targetUid: ben.uid, reason: 'Bad Reason!' }), reason('INVALID_ARGUMENT', 'bad_reason'));
    await assert.rejects(ann.call('reportName', {}), status('INVALID_ARGUMENT'));
  });

  it('accepts a report from a friend or from a player who shares a match with the target, and refuses a stranger', async () => {
    const [host, target] = [await newUser({ full: true, name: 'Hostess' }), await newUser({ name: 'Rude' })];
    const stranger = await newUser();
    const mate = await newUser();
    const lobby = await hostLobby(host, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    await target.call('joinMatch', { code: lobby.code });
    await mate.call('joinMatch', { code: lobby.code });
    await assert.rejects(stranger.call('reportName', { targetUid: target.uid }), reason('NOT_FOUND', 'unknown_user'));
    assert.deepEqual(await mate.call('reportName', { targetUid: target.uid }), { hidden: false, duplicate: false }); // same match
    const friend = await friendOf(target);
    assert.deepEqual(await friend.call('reportName', { targetUid: target.uid }), { hidden: false, duplicate: false });
    // the stranger learns nothing: the answer is the one a made-up uid gets
    await assert.rejects(stranger.call('reportName', { targetUid: 'nobody12345' }), reason('NOT_FOUND', 'unknown_user'));
    assert.equal(Object.keys((await value<Record<string, boolean>>(`nameReports/${target.uid}`)) ?? {}).length, 2);
  });

  it('shows a hidden name as PLAYER plus a short id to the players who join their matches', async () => {
    const [host, target] = [await newUser({ full: true }), await newUser({ name: 'Rude' })];
    const reporters = [await friendOf(target), await friendOf(target), await friendOf(target)];
    for (const r of reporters) await r.call('reportName', { targetUid: target.uid });
    const { code: matchCode, matchId } = await hostLobby(host);
    await target.call('joinMatch', { code: matchCode });
    const seats = (await value<{ name?: string }[]>(`matches/${matchId}/meta/seats`)) ?? [];
    assert.match(seats[1]?.name ?? '', /^PLAYER [A-Z2-9]{4}$/);
  });
});
