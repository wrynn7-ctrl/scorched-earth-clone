// "Delete my online data" (ARCHITECTURE section 44).
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { getAuthAdmin } from '../../functions/src/admin';
import { befriend, db, eventually, hostLobby, newUser, settle, value } from './harness';

const HOUR = 3600 * 1000;

interface Seat {
  kind: string;
  uid?: string;
  name?: string;
  level?: number;
}

describe('functions: deleteMyData', () => {
  it('removes the account and everything it owns, and leaves other players\' matches playable', async () => {
    // Ann is the player who deletes; Ben, Cy and Dee are others.
    const ann = await newUser({ full: true, name: 'Ann' });
    const [ben, cy, dee] = [await newUser({ name: 'Ben' }), await newUser({ name: 'Cy' }), await newUser({ name: 'Dee' })];
    await ann.call('verifyPurchase', { purchaseToken: 'test-full' }).catch(() => ann.call('testSetFull', { uid: ann.uid }));
    const annProfile = await ann.profile();
    const annCode = annProfile.friendCode as string;
    await befriend(ann, ben);
    await befriend(dee, ann);
    await cy.call('sendFriendRequest', { code: annCode }); // pending request to Ann
    await ann.call('sendFriendRequest', { code: (await dee.profile()).friendCode }).catch(() => undefined);
    const eve = await newUser();
    await ann.call('sendFriendRequest', { code: (await eve.profile()).friendCode }); // pending request from Ann

    // M1: Ann hosts, Ben joins, running, and it is Ann's turn.
    const m1 = await hostLobby(ann, [{ kind: 'human', mine: true }, { kind: 'human' }]);
    await ben.call('joinMatch', { code: m1.code });
    await ann.call('startMatch', { matchId: m1.matchId });
    await db.ref(`matches/${m1.matchId}/meta/turn`).set({ tank: 0, uid: ann.uid, deadline: Date.now() + HOUR, index: 1 });
    await ann.setPresence(m1.matchId, 1000);
    // M2: Ben hosts a lobby that Ann joined.
    const benHost = await newUser({ full: true });
    await befriend(benHost, ann);
    const m2 = await hostLobby(benHost, [{ kind: 'human', mine: true }, { kind: 'human' }, { kind: 'human' }]);
    await ann.call('joinMatch', { code: m2.code });
    // M3: Ann's own lobby, with an invite out to Ben.
    const m3 = await hostLobby(ann);
    await ann.call('invite', { friendUid: ben.uid, matchId: m3.matchId });
    // M4: a finished match Ann played in.
    const m4 = await hostLobby(ann, [{ kind: 'human', mine: true }, { kind: 'cpu' }]);
    await ann.call('startMatch', { matchId: m4.matchId });
    await db.ref(`matches/${m4.matchId}/meta/status`).set('over');
    // An invite Dee sent to Ann.
    const m5 = await hostLobby(dee.uid === ann.uid ? ann : await (async () => { await dee.call('testSetFull', { uid: dee.uid }); return dee; })());
    await dee.call('invite', { friendUid: ann.uid, matchId: m5.matchId });
    // Reports: Ann was reported, and reported someone.
    await ben.call('reportName', { targetUid: ann.uid });
    await ann.call('reportName', { targetUid: ben.uid }); // Ben shares a match with Ann
    await ann.call('block', { targetUid: eve.uid });
    await settle(1500);

    const result = await ann.call<{ deleted: boolean; matches: number }>('deleteMyData');
    assert.equal(result.deleted, true);
    assert.equal(result.matches, 4);

    // The account and its profile data.
    assert.equal(await value(`users/${ann.uid}`), null);
    assert.equal(await value(`friendCodes/${annCode}`), null);
    assert.equal(await value(`blocks/${ann.uid}`), null);
    assert.equal(await value(`nameReports/${ann.uid}`), null);
    assert.equal(await value(`userMatches/${ann.uid}`), null);
    assert.equal(await value(`purchaseTokens/${createHash('sha256').update('test-full').digest('hex')}`), null);
    await assert.rejects(getAuthAdmin().getUser(ann.uid), (e: { code?: string }) => e.code === 'auth/user-not-found');

    // Friends, requests, invites: gone on both sides.
    assert.equal(await value(`friends/${ann.uid}`), null);
    assert.equal(await value(`friends/${ben.uid}/${ann.uid}`), null);
    assert.equal(await value(`friends/${dee.uid}/${ann.uid}`), null);
    assert.equal(await value(`friends/${benHost.uid}/${ann.uid}`), null);
    assert.equal(await value(`friendRequests/${ann.uid}`), null);
    assert.equal(await value(`sentRequests/${cy.uid}/${ann.uid}`), null);
    assert.equal(await value(`friendRequests/${eve.uid}/${ann.uid}`), null);
    assert.equal(await value(`sentRequests/${ann.uid}`), null);
    assert.equal(await value(`invites/${ann.uid}`), null);
    assert.equal(await value(`invitesSent/${dee.uid}/${m5.matchId}/${ann.uid}`), null);
    assert.equal(await value(`invites/${ben.uid}/${m3.matchId}`), null);
    assert.equal(await value(`invitesSent/${ann.uid}`), null);

    // M1 keeps running: Ann's seat is CPU Normal, with no name, and the turn needs a client to carry on.
    const m1meta = (await value<{ seats: Seat[]; status: string; turn: unknown }>(`matches/${m1.matchId}/meta`))!;
    assert.deepEqual(m1meta.seats[0], { kind: 'cpu', level: 2, name: 'PLAYER' });
    assert.equal(m1meta.seats[1]?.uid, ben.uid);
    assert.equal(m1meta.status, 'playing');
    assert.deepEqual(m1meta.turn, { tank: -1, uid: 'any', deadline: 0, index: 2 });
    assert.equal(await value(`matches/${m1.matchId}/presence/${ann.uid}`), null);
    assert.ok(await value(`userMatches/${ben.uid}/${m1.matchId}`), 'Ben still has the match');

    // M2: the lobby seat is free again for someone else.
    const m2seats = (await value<Seat[]>(`matches/${m2.matchId}/meta/seats`))!;
    assert.deepEqual(m2seats[2], { kind: 'human' });
    // M3: Ann's own lobby is closed and its code released.
    assert.equal(await value(`matches/${m3.matchId}/meta/status`), 'abandoned');
    assert.equal(await value(`matchCodes/${m3.code}`), null);
    // M4: a finished match no longer points at the deleted account.
    const m4seats = (await value<Seat[]>(`matches/${m4.matchId}/meta/seats`))!;
    assert.deepEqual(m4seats[0], { kind: 'cpu', level: 2, name: 'PLAYER' });

    // Nothing recreated Ann's list entries afterwards (late trigger work).
    await settle(1500);
    assert.equal(await value(`userMatches/${ann.uid}`), null);
    // Other players' data is untouched.
    assert.equal((await ben.profile()).name, 'Ben');
    assert.ok(await value(`users/${eve.uid}`));
  });

  it('works for a player with nothing but a profile, and a second call is harmless', async () => {
    const user = await newUser();
    const code = (await user.profile()).friendCode as string;
    assert.deepEqual(await user.call('deleteMyData'), { deleted: true, matches: 0 });
    assert.equal(await value(`users/${user.uid}`), null);
    assert.equal(await value(`friendCodes/${code}`), null);
    await eventually(async () => getAuthAdmin().getUser(user.uid).then(() => false, () => true), 'auth user gone');
  });

  it('removes the friend-request cooldowns it is part of, as the sender and as the decliner', async () => {
    const [ann, ben, cy] = [await newUser(), await newUser(), await newUser()];
    await ann.call('sendFriendRequest', { code: (await ben.profile()).friendCode });
    await ben.call('respondFriendRequest', { fromUid: ann.uid, accept: false });
    await cy.call('sendFriendRequest', { code: (await ann.profile()).friendCode });
    await ann.call('respondFriendRequest', { fromUid: cy.uid, accept: false });
    assert.ok(await value(`friendCooldowns/${ann.uid}/${ben.uid}`));
    assert.ok(await value(`friendCooldowns/${cy.uid}/${ann.uid}`));
    await ann.call('deleteMyData');
    for (const path of [`friendCooldowns/${ann.uid}`, `friendCooldownsBy/${ann.uid}`, `friendCooldownsBy/${ben.uid}`, `friendCooldowns/${cy.uid}`]) {
      assert.equal(await value(path), null, path);
    }
  });
});
