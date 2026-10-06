// Friend requests, friendships, blocks and name reports (ARCHITECTURE section 44). Clients never write these paths:
// every change goes through a callable, which checks blocks in both directions.
import { FRIEND_CODE_LENGTH, MAX_PENDING_REQUESTS, REPORTS_TO_HIDE_NAME } from './config';
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
  // A blocked pair looks exactly like an unknown code, so a block never reveals itself.
  if (await isBlockedEither(deps.db, uid, target)) return fail('not-found', 'unknown_code');
  if (await exists(deps.db, `friends/${uid}/${target}`)) return fail('already-exists', 'already_friends');
  const targetUser = await read<UserRecord>(deps.db, `users/${target}`);
  if (!targetUser) return fail('not-found', 'unknown_code');
  const at = deps.now();

  // They already asked us: asking back means yes.
  if (await exists(deps.db, `friendRequests/${uid}/${target}`)) {
    await deps.db.ref().update({
      ...friendUpdates(uid, target, uid, at),
      ...requestRemovals(target, uid),
      ...requestRemovals(uid, target),
    });
    return { status: 'friends', friendUid: target, name: displayName(targetUser) };
  }
  const pending = await deps.db.ref(`friendRequests/${target}`).orderByKey().limitToFirst(MAX_PENDING_REQUESTS + 1).get();
  if (pending.numChildren() > MAX_PENDING_REQUESTS && !pending.hasChild(uid)) return fail('resource-exhausted', 'too_many_requests');
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
    await deps.db.ref().update(cleanup);
    return { status: 'declined' };
  }
  if (await isBlockedEither(deps.db, uid, fromUid)) {
    await deps.db.ref().update(cleanup);
    return fail('not-found', 'no_request');
  }
  await deps.db.ref().update({ ...cleanup, ...friendUpdates(uid, fromUid, uid, deps.now()) });
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
  if (!user) return fail('not-found', 'unknown_user');
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
