// Friend requests, friendships, blocks and name reports (ARCHITECTURE section 44), including blocks in both directions.
import assert from 'node:assert/strict';
import { befriend, CallError, db, eventually, fcmFor, hostLobby, newUser, settle, signUp, value, type TestUser } from './harness';

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
  it('hides a name after reports from 3 different players, and not before', async () => {
    const target = await newUser({ name: 'Rude' });
    const [r1, r2, r3] = [await newUser(), await newUser(), await newUser()];
    assert.deepEqual(await r1.call('reportName', { targetUid: target.uid, reason: 'offensive_name' }), { hidden: false, duplicate: false });
    assert.deepEqual(await r2.call('reportName', { targetUid: target.uid }), { hidden: false, duplicate: false });
    assert.equal((await target.profile()).nameHidden, false);
    assert.deepEqual(await r3.call('reportName', { targetUid: target.uid }), { hidden: true, duplicate: false });
    assert.equal((await target.profile()).nameHidden, true);
    assert.equal(Object.keys((await value<Record<string, boolean>>(`nameReports/${target.uid}`)) ?? {}).length, 3);
  });

  it('counts one player once, however often they report', async () => {
    const target = await newUser();
    const [r1, r2] = [await newUser(), await newUser()];
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
    const reporter = await newUser();
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
    await assert.rejects(ann.call('reportName', { targetUid: ann.uid }), reason('FAILED_PRECONDITION', 'self'));
    await assert.rejects(ann.call('reportName', { targetUid: 'nobody123' }), reason('NOT_FOUND', 'unknown_user'));
    await assert.rejects(ann.call('reportName', { targetUid: ben.uid, reason: 'Bad Reason!' }), reason('INVALID_ARGUMENT', 'bad_reason'));
    await assert.rejects(ann.call('reportName', {}), status('INVALID_ARGUMENT'));
  });

  it('shows a hidden name as PLAYER plus a short id to the players who join their matches', async () => {
    const [host, target] = [await newUser({ full: true }), await newUser({ name: 'Rude' })];
    const reporters = [await newUser(), await newUser(), await newUser()];
    for (const r of reporters) await r.call('reportName', { targetUid: target.uid });
    const { code: matchCode, matchId } = await hostLobby(host);
    await target.call('joinMatch', { code: matchCode });
    const seats = (await value<{ name?: string }[]>(`matches/${matchId}/meta/seats`)) ?? [];
    assert.match(seats[1]?.name ?? '', /^PLAYER [A-Z2-9]{4}$/);
  });
});
