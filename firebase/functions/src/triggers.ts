// Database triggers: name re-check, turn changes (bookkeeping + push), invites, accepted friend requests, match over
// (ARCHITECTURE sections 44, 45 and 47). Each handler is a plain async function of (deps, ...) so it can be called directly.
import { onValueCreated, onValueWritten } from 'firebase-functions/v2/database';
import { MAX_INSTANCES, MAX_PUSH_TOKENS, PRESENCE_FRESH_MS, TRIGGER_REGION } from './config';
import { defaultDeps, type Deps } from './deps';
import { cleanupFinished, syncMatch } from './matches';
import { notifyUser } from './push';
import { recheckName } from './profile';
import { displayName, read, readMeta, type Turn, type UserRecord } from './rtdb';

const options = { region: TRIGGER_REGION, maxInstances: MAX_INSTANCES };

/** True when the player has no fresh presence heartbeat in this match (they are not looking at it). */
export async function isAway(deps: Deps, matchId: string, uid: string): Promise<boolean> {
  const beat = await read<number>(deps.db, `matches/${matchId}/presence/${uid}`);
  return beat === null || deps.now() - beat > PRESENCE_FRESH_MS;
}

/**
 * A turn was set. Keeps every member's "Your matches" entry and the sweep queue current, and pushes "Your turn" to the
 * player who now holds it if they are not online. `before` is the previous turn (null for the first one).
 */
export async function handleTurnChange(deps: Deps, matchId: string, before: Turn | null, after: Turn): Promise<{ pushed: boolean }> {
  const meta = await readMeta(deps.db, matchId);
  if (!meta) return { pushed: false };
  await syncMatch(deps, matchId, meta);
  const holder = after.uid;
  const humanTurn = meta.status === 'playing' && after.tank >= 0 && holder !== 'cpu' && holder !== 'any';
  if (!humanTurn || (before !== null && before.index === after.index)) return { pushed: false };
  if (!(await isAway(deps, matchId, holder))) return { pushed: false };
  const hostName = meta.seats.find((s) => s.uid === meta.hostUid)?.name ?? 'PLAYER';
  const pushed = await notifyUser(deps.db, deps.sender, holder, {
    title: 'Craterline',
    body: `Your turn in ${hostName}'s match`,
    data: { type: 'turn', matchId },
    collapseKey: `turn_${matchId}`,
  });
  return { pushed };
}

export async function handleInvite(deps: Deps, toUid: string, matchId: string, invite: { fromName?: string } | null): Promise<boolean> {
  if (!invite) return false;
  return notifyUser(deps.db, deps.sender, toUid, {
    title: 'Craterline',
    body: `${invite.fromName ?? 'A friend'} invited you to a match`,
    data: { type: 'invite', matchId },
    collapseKey: `invite_${matchId}`,
  });
}

/** `friends/{uid}/{friendUid}` was created. `by` is who completed the friendship; the other player hears about it. */
export async function handleFriendAdded(deps: Deps, uid: string, friendUid: string, entry: { by?: string } | null): Promise<boolean> {
  if (!entry || entry.by !== friendUid) return false;
  const friend = await read<UserRecord>(deps.db, `users/${friendUid}`);
  return notifyUser(deps.db, deps.sender, uid, {
    title: 'Craterline',
    body: `${displayName(friend)} accepted your friend request`,
    data: { type: 'friend', friendUid },
    collapseKey: `friend_${friendUid}`,
  });
}

/** meta/status became over or abandoned (written by a client or by a function): clean up, and tell absent players. */
export async function handleStatusChange(deps: Deps, matchId: string, before: string | null, after: string | null): Promise<number> {
  if ((after !== 'over' && after !== 'abandoned') || before === after) return 0;
  const meta = await readMeta(deps.db, matchId);
  if (!meta) return 0;
  await cleanupFinished(deps, matchId, meta);
  if (after !== 'over') return 0;
  let sent = 0;
  const seen = new Set<string>();
  for (const seat of meta.seats) {
    if (seat.kind !== 'human' || !seat.uid || seen.has(seat.uid)) continue;
    seen.add(seat.uid);
    if (!(await isAway(deps, matchId, seat.uid))) continue;
    const pushed = await notifyUser(deps.db, deps.sender, seat.uid, {
      title: 'Craterline',
      body: `The match in ${meta.seats.find((s) => s.uid === meta.hostUid)?.name ?? 'PLAYER'}'s game is over`,
      data: { type: 'over', matchId },
      collapseKey: `over_${matchId}`,
    });
    if (pushed) sent += 1;
  }
  return sent;
}

/**
 * A push token was stored (users/{uid}/fcm/{tokenHash}). A player keeps at most MAX_PUSH_TOKENS: when there are more, the
 * oldest-looking ones go (the new token is always kept; among the others the order of their keys decides, because tokens carry
 * no date). The database rules cannot count children, so this is where the cap is enforced; an update that writes many tokens
 * at once is trimmed to the cap within moments. Returns how many were removed.
 */
export async function pruneTokens(deps: Deps, uid: string, keep: string): Promise<number> {
  let removed = 0;
  await deps.db.ref(`users/${uid}/fcm`).transaction((current: Record<string, string> | null) => {
    removed = 0;
    if (current === null) return null; // first pass has no data; the SDK retries with the real value
    const keys = Object.keys(current);
    if (keys.length <= MAX_PUSH_TOKENS) return current;
    const others = keys.filter((key) => key !== keep).sort();
    const drop = others.slice(0, keys.length - MAX_PUSH_TOKENS);
    const next: Record<string, string> = { ...current };
    for (const key of drop) delete next[key];
    removed = drop.length;
    return next;
  });
  return removed;
}

export const onNameWrite = onValueWritten({ ...options, ref: '/users/{uid}/name' }, async (event) => {
  await recheckName(defaultDeps(), event.params.uid, event.data.after.val());
});

export const onTurnChange = onValueWritten({ ...options, ref: '/matches/{matchId}/meta/turn' }, async (event) => {
  const after = event.data.after.val() as Turn | null;
  if (!after) return;
  await handleTurnChange(defaultDeps(), event.params.matchId, event.data.before.val() as Turn | null, after);
});

export const onInvite = onValueCreated({ ...options, ref: '/invites/{toUid}/{matchId}' }, async (event) => {
  await handleInvite(defaultDeps(), event.params.toUid, event.params.matchId, event.data?.val() as { fromName?: string } | null);
});

export const onFriendAccepted = onValueCreated({ ...options, ref: '/friends/{uid}/{friendUid}' }, async (event) => {
  await handleFriendAdded(defaultDeps(), event.params.uid, event.params.friendUid, event.data?.val() as { by?: string } | null);
});

export const onMatchOver = onValueWritten({ ...options, ref: '/matches/{matchId}/meta/status' }, async (event) => {
  await handleStatusChange(
    defaultDeps(),
    event.params.matchId,
    event.data.before.val() as string | null,
    event.data.after.val() as string | null,
  );
});

export const onPushTokenAdded = onValueCreated({ ...options, ref: '/users/{uid}/fcm/{tokenHash}' }, async (event) => {
  await pruneTokens(defaultDeps(), event.params.uid, event.params.tokenHash);
});
