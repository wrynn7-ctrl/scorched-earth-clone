// "Delete my online data" (ARCHITECTURE section 44): removes everything the player owns, hands their seats to CPU Normal so
// running matches can go on, then deletes the Auth user. Safe to call again if it stopped half way (the match list is
// removed last, and every step is idempotent).
import type { Deps } from './deps';
import { cleanupFinished, finishMatch, mutateMeta, seatsToCpu, syncMatch } from './matches';
import { read, readMeta, type Meta, type Seat, type UserRecord } from './rtdb';

type Updates = Record<string, null>;

export interface DeleteResult {
  deleted: true;
  matches: number;
}

export async function deleteMyData(deps: Deps, uid: string): Promise<DeleteResult> {
  const matchIds = Object.keys((await read<Record<string, unknown>>(deps.db, `userMatches/${uid}`)) ?? {});
  for (const matchId of matchIds) await detachFromMatch(deps, uid, matchId);

  const updates: Updates = {};
  await collectFriendRemovals(deps, uid, updates);
  await collectRequestRemovals(deps, uid, updates);
  await collectInviteRemovals(deps, uid, updates);
  await collectCooldownRemovals(deps, uid, updates);
  const user = await read<UserRecord>(deps.db, `users/${uid}`);
  if (user?.friendCode) updates[`friendCodes/${user.friendCode}`] = null;
  if (user?.purchase?.tokenHash) updates[`purchaseTokens/${user.purchase.tokenHash}`] = null;
  for (const matchId of matchIds) updates[`matches/${matchId}/presence/${uid}`] = null;
  updates[`blocks/${uid}`] = null;
  updates[`nameReports/${uid}`] = null;
  updates[`users/${uid}`] = null;
  updates[`userMatches/${uid}`] = null;
  await deps.db.ref().update(updates);

  try {
    await deps.auth().deleteUser(uid);
  } catch (error) {
    if ((error as { code?: string }).code !== 'auth/user-not-found') throw error;
  }
  return { deleted: true, matches: matchIds.length };
}

/** Frees, converts or anonymises the player's seats in one match, whatever its state. */
async function detachFromMatch(deps: Deps, uid: string, matchId: string): Promise<void> {
  const seen = await readMeta(deps.db, matchId);
  if (!seen) return;
  if (seen.status === 'lobby' && seen.hostUid === uid) {
    await finishMatch(deps, matchId, 'abandoned');
  } else if (seen.status === 'lobby') {
    await mutateMeta(deps, matchId, (meta): { meta: Meta; result: null } => {
      const seats = meta.seats.map((seat): Seat => (seat.uid === uid ? { kind: 'human' } : seat));
      return { meta: { ...meta, seats }, result: null };
    });
  } else if (seen.status === 'playing') {
    const after = await mutateMeta(deps, matchId, (meta): { meta: Meta; result: Meta } => {
      const next = meta.status === 'playing' ? seatsToCpu(meta, uid, true) : meta;
      return { meta: next, result: next };
    });
    if (after.status === 'abandoned') await cleanupFinished(deps, matchId, after);
  }
  // Whatever the state (finished matches too), no seat may keep pointing at a deleted account.
  const after = await mutateMeta(deps, matchId, (meta): { meta: Meta; result: Meta } => {
    const next = seatsToCpu({ ...meta, turn: undefined }, uid, true);
    const merged: Meta = { ...meta, seats: next.seats };
    return { meta: merged, result: merged };
  });
  if (after.status === 'playing' || after.status === 'lobby') await syncMatch(deps, matchId, after);
}

async function collectFriendRemovals(deps: Deps, uid: string, out: Updates): Promise<void> {
  const friends = (await read<Record<string, unknown>>(deps.db, `friends/${uid}`)) ?? {};
  for (const friendUid of Object.keys(friends)) out[`friends/${friendUid}/${uid}`] = null;
  out[`friends/${uid}`] = null;
}

async function collectRequestRemovals(deps: Deps, uid: string, out: Updates): Promise<void> {
  const incoming = (await read<Record<string, unknown>>(deps.db, `friendRequests/${uid}`)) ?? {};
  for (const from of Object.keys(incoming)) out[`sentRequests/${from}/${uid}`] = null;
  const outgoing = (await read<Record<string, unknown>>(deps.db, `sentRequests/${uid}`)) ?? {};
  for (const to of Object.keys(outgoing)) out[`friendRequests/${to}/${uid}`] = null;
  out[`friendRequests/${uid}`] = null;
  out[`sentRequests/${uid}`] = null;
}

async function collectInviteRemovals(deps: Deps, uid: string, out: Updates): Promise<void> {
  const received = (await read<Record<string, { fromUid?: string }>>(deps.db, `invites/${uid}`)) ?? {};
  for (const [matchId, invite] of Object.entries(received)) {
    if (invite.fromUid) out[`invitesSent/${invite.fromUid}/${matchId}/${uid}`] = null;
  }
  const sent = (await read<Record<string, Record<string, unknown>>>(deps.db, `invitesSent/${uid}`)) ?? {};
  for (const [matchId, recipients] of Object.entries(sent)) {
    for (const to of Object.keys(recipients)) out[`invites/${to}/${matchId}`] = null;
  }
  out[`invites/${uid}`] = null;
  out[`invitesSent/${uid}`] = null;
}

async function collectCooldownRemovals(deps: Deps, uid: string, out: Updates): Promise<void> {
  const asSender = (await read<Record<string, unknown>>(deps.db, `friendCooldowns/${uid}`)) ?? {};
  for (const decliner of Object.keys(asSender)) out[`friendCooldownsBy/${decliner}/${uid}`] = null;
  const asDecliner = (await read<Record<string, unknown>>(deps.db, `friendCooldownsBy/${uid}`)) ?? {};
  for (const sender of Object.keys(asDecliner)) out[`friendCooldowns/${sender}/${uid}`] = null;
  out[`friendCooldowns/${uid}`] = null;
  out[`friendCooldownsBy/${uid}`] = null;
}
