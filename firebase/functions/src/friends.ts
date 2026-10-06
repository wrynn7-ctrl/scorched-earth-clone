// Friend requests, friendships, blocks and name reports (ARCHITECTURE section 44). Clients never write these paths:
// every change goes through a callable, which checks blocks in both directions.
import { FRIEND_CODE_LENGTH, MAX_PENDING_REQUESTS, REPORTS_TO_HIDE_NAME, REQUEST_COOLDOWN_MS } from './config';
import { normalizeCode } from './codes';
import type { Deps } from './deps';
import { asObject, fail, reqBool, reqId, optString } from './errors';
import { displayName, exists, isBlockedEither, read, type UserRecord } from './rtdb';

type Updates = Record<string, unknown>;

async function requireProfile(deps: Deps, uid: string): Promise<UserRecord> {
  const user = await read<UserRecord>(deps.db, `users/${uid}`);
  if (!user?.friendCode) return fail('failed-precondition', 'no_profile');
  return user;
}

/** Friendship in both directions. `by` is the player who completed it (accepted the request). */
function friendUpdates(a: string, b: string, by: string, at: number): Updates {
  return {
    [`friends/${a}/${b}`]: { since: at, by },
    [`friends/${b}/${a}`]: { since: at, by },
  };
}

/** Removes a request and its reverse index entry. */
function requestRemovals(from: string, to: string): Updates {
  return { [`friendRequests/${to}/${from}`]: null, [`sentRequests/${from}/${to}`]: null };
}

/** Clears the decline cooldowns between two players, both ways (they are friends now). */
function cooldownRemovals(a: string, b: string): Updates {
  return {
    [`friendCooldowns/${a}/${b}`]: null,
    [`friendCooldownsBy/${b}/${a}`]: null,
    [`friendCooldowns/${b}/${a}`]: null,
    [`friendCooldownsBy/${a}/${b}`]: null,
  };
}

export interface SendRequestResult {
  status: 'sent' | 'friends';
  friendUid?: string;
  name: string;
}

export async function sendFriendRequest(deps: Deps, uid: string, raw: unknown): Promise<SendRequestResult> {
  const data = asObject(raw);
  const me = await requireProfile(deps, uid);
  const code = normalizeCode(data.code, FRIEND_CODE_LENGTH);
  if (!code) return fail('invalid-argument', 'bad_code');
  const target = await read<string>(deps.db, `friendCodes/${code}`);
  if (!target) return fail('not-found', 'unknown_code');
  if (target === uid) return fail('failed-precondition', 'own_code');
  return requestBetween(deps, uid, me, target);
}

/**
 * Friend request to a player met in a shared match (the "Add friend" button on a name in a lobby or battle). Both players
 * must hold a seat in `matchId` (the server-written `userMatches` entries are the membership list). Everything else is the
 * same as a request by code, including the neutral `unknown_code` for a blocked pair; a target who is not in the match gets
 * it too, so this cannot be used to probe whether a uid exists.
 */
export async function sendFriendRequestToUid(deps: Deps, uid: string, raw: unknown): Promise<SendRequestResult> {
  const data = asObject(raw);
  const targetUid = reqId(data, 'targetUid');
  const matchId = reqId(data, 'matchId');
  const me = await requireProfile(deps, uid);
  if (targetUid === uid) return fail('failed-precondition', 'self');
  if (!(await exists(deps.db, `userMatches/${uid}/${matchId}`))) return fail('permission-denied', 'not_a_member');
  if (!(await exists(deps.db, `userMatches/${targetUid}/${matchId}`))) return fail('not-found', 'unknown_code');
  return requestBetween(deps, uid, me, targetUid);
}

/** Shared by both ways of asking: blocks, existing friendship, a crossing request, the pending cap, then the write. */
async function requestBetween(deps: Deps, uid: string, me: UserRecord, target: string): Promise<SendRequestResult> {
  // A blocked pair looks exactly like an unknown code, so a block never reveals itself.
  if (await isBlockedEither(deps.db, uid, target)) return fail('not-found', 'unknown_code');
  if (await exists(deps.db, `friends/${uid}/${target}`)) return fail('already-exists', 'already_friends');
  const targetUser = await read<UserRecord>(deps.db, `users/${target}`);
  if (!targetUser) return fail('not-found', 'unknown_code');
  const at = deps.now();
  // Declined once: wait a day before asking the same player again (checked after the "they asked us first" case below).
  const declinedAt = await read<number>(deps.db, `friendCooldowns/${uid}/${target}`);

  // They already asked us: asking back means yes.
  if (await exists(deps.db, `friendRequests/${uid}/${target}`)) {
    await deps.db.ref().update({
      ...friendUpdates(uid, target, uid, at),
      ...requestRemovals(target, uid),
      ...requestRemovals(uid, target),
      ...cooldownRemovals(uid, target),
    });
    return { status: 'friends', friendUid: target, name: displayName(targetUser) };
  }
  if (declinedAt !== null && at - declinedAt < REQUEST_COOLDOWN_MS) return fail('resource-exhausted', 'request_cooldown');
  const pending = await deps.db.ref(`friendRequests/${target}`).orderByKey().limitToFirst(MAX_PENDING_REQUESTS).get();
  if (pending.numChildren() >= MAX_PENDING_REQUESTS && !pending.hasChild(uid)) return fail('resource-exhausted', 'too_many_requests');
  await deps.db.ref().update({
    [`friendRequests/${target}/${uid}`]: { name: displayName(me), at },
    [`sentRequests/${uid}/${target}`]: true,
  });
  return { status: 'sent', name: displayName(targetUser) };
}

export async function respondFriendRequest(deps: Deps, uid: string, raw: unknown): Promise<{ status: 'accepted' | 'declined' }> {
  const data = asObject(raw);
  const fromUid = reqId(data, 'fromUid');
  const accept = reqBool(data, 'accept');
  await requireProfile(deps, uid);
  if (!(await exists(deps.db, `friendRequests/${uid}/${fromUid}`))) return fail('not-found', 'no_request');
  const cleanup: Updates = { ...requestRemovals(fromUid, uid), ...requestRemovals(uid, fromUid) };
  if (!accept) {
    // The decline starts a cooldown for this sender and this player only (`friendCooldowns/{sender}/{decliner}`, with the
    // reverse index `friendCooldownsBy/{decliner}/{sender}` so deleting an account can find them).
    const at = deps.now();
    await deps.db.ref().update({ ...cleanup, [`friendCooldowns/${fromUid}/${uid}`]: at, [`friendCooldownsBy/${uid}/${fromUid}`]: at });
    return { status: 'declined' };
  }
  if (await isBlockedEither(deps.db, uid, fromUid)) {
    await deps.db.ref().update(cleanup);
    return fail('not-found', 'no_request');
  }
  await deps.db.ref().update({ ...cleanup, ...cooldownRemovals(fromUid, uid), ...friendUpdates(uid, fromUid, uid, deps.now()) });
  return { status: 'accepted' };
}

export async function removeFriend(deps: Deps, uid: string, raw: unknown): Promise<{ removed: true }> {
  const friendUid = reqId(asObject(raw), 'friendUid');
  await deps.db.ref().update({ [`friends/${uid}/${friendUid}`]: null, [`friends/${friendUid}/${uid}`]: null });
  return { removed: true };
}

/** Deletes the invites `from` sent to `to` (and the reverse index entries). */
async function invitePurge(deps: Deps, from: string, to: string): Promise<Updates> {
  const out: Updates = {};
  const sent = await read<Record<string, Record<string, boolean>>>(deps.db, `invitesSent/${from}`);
  for (const [matchId, recipients] of Object.entries(sent ?? {})) {
    if (recipients[to]) {
      out[`invites/${to}/${matchId}`] = null;
      out[`invitesSent/${from}/${matchId}/${to}`] = null;
    }
  }
  return out;
}

/**
 * Blocks a player: records the block and removes the friendship, pending requests and invites between the two,
 * in both directions.
 */
export async function blockUser(deps: Deps, uid: string, raw: unknown): Promise<{ blocked: true }> {
  const target = reqId(asObject(raw), 'targetUid');
  if (target === uid) return fail('failed-precondition', 'self');
  await requireProfile(deps, uid);
  // Only a real account can be blocked, so the block list cannot be filled with made-up ids.
  if (!(await exists(deps.db, `users/${target}`))) return fail('not-found', 'unknown_user');
  const updates: Updates = {
    [`blocks/${uid}/${target}`]: true,
    [`friends/${uid}/${target}`]: null,
    [`friends/${target}/${uid}`]: null,
    ...requestRemovals(uid, target),
    ...requestRemovals(target, uid),
    ...(await invitePurge(deps, uid, target)),
    ...(await invitePurge(deps, target, uid)),
  };
  await deps.db.ref().update(updates);
  return { blocked: true };
}

export async function unblockUser(deps: Deps, uid: string, raw: unknown): Promise<{ unblocked: true }> {
  const target = reqId(asObject(raw), 'targetUid');
  await deps.db.ref(`blocks/${uid}/${target}`).remove();
  return { unblocked: true };
}

const REASONS = /^[a-z][a-z_]{0,31}$/;

/** True when the two players are friends, or both have (or had, until deleted) the same match in their list. */
async function knowsPlayer(deps: Deps, uid: string, other: string): Promise<boolean> {
  if (await exists(deps.db, `friends/${uid}/${other}`)) return true;
  const [mine, theirs] = await Promise.all([
    read<Record<string, unknown>>(deps.db, `userMatches/${uid}`),
    read<Record<string, unknown>>(deps.db, `userMatches/${other}`),
  ]);
  if (!mine || !theirs) return false;
  return Object.keys(mine).some((matchId) => Object.prototype.hasOwnProperty.call(theirs, matchId));
}

export interface ReportResult {
  /** True once this name is hidden (3 distinct reporters). */
  hidden: boolean;
  /** True when this player had already reported that name; nothing new was recorded. */
  duplicate: boolean;
}

/** Records a name report; hides the name from the third distinct reporter on. */
export async function reportName(deps: Deps, uid: string, raw: unknown): Promise<ReportResult> {
  const data = asObject(raw);
  const target = reqId(data, 'targetUid');
  const reason = optString(data, 'reason', 32) ?? 'offensive_name';
  if (!REASONS.test(reason)) return fail('invalid-argument', 'bad_reason');
  if (target === uid) return fail('failed-precondition', 'self');
  await requireProfile(deps, uid);
  const user = await read<UserRecord>(deps.db, `users/${target}`);
  // Only people who know the player can report the name: friends, or players who share (or shared) a match. The answer is the
  // same as for a made-up uid, so this cannot be used to probe which uids exist.
  if (!user || !(await knowsPlayer(deps, uid, target))) return fail('not-found', 'unknown_user');
  if (await exists(deps.db, `nameReports/${target}/${uid}`)) return { hidden: user.nameHidden === true, duplicate: true };
  const reportId = deps.db.ref('reports').push().key;
  if (!reportId) return fail('internal', 'no_report_id');
  await deps.db.ref().update({
    [`nameReports/${target}/${uid}`]: true,
    // The name at report time is kept so the owner can review what was actually reported.
    [`reports/${reportId}`]: { reporterUid: uid, targetUid: target, reason, name: user.name ?? '', at: deps.now() },
  });
  const reporters = (await deps.db.ref(`nameReports/${target}`).get()).numChildren();
  const hidden = user.nameHidden === true || reporters >= REPORTS_TO_HIDE_NAME;
  if (hidden && user.nameHidden !== true) await deps.db.ref(`users/${target}/nameHidden`).set(true);
  return { hidden, duplicate: false };
}
