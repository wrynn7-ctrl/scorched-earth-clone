// Profiles: friend code, name and protocol (ARCHITECTURE section 44).
import { allocateCode } from './codes';
import { FRIEND_CODE_LENGTH, PROTOCOL_MAX } from './config';
import type { Deps } from './deps';
import { asObject, fail, optInt, type Fields } from './errors';
import { checkName, FALLBACK_NAME } from './name_filter';
import { read, type UserRecord } from './rtdb';

export interface ProfileResult {
  friendCode: string;
  name: string;
  nameHidden: boolean;
  full: boolean;
  protocol: number;
  /** Server time in ms, so a client can estimate its clock offset (deadlines are checked against server time). */
  serverTime: number;
}

function toResult(user: UserRecord, serverTime: number): ProfileResult {
  return {
    friendCode: user.friendCode ?? '',
    name: user.name ?? FALLBACK_NAME,
    nameHidden: user.nameHidden === true,
    full: user.full === true,
    protocol: user.protocol ?? 0,
    serverTime,
  };
}

/**
 * Creates the profile on first call (friend code, name "PLAYER", full = false) and stores the client's protocol version.
 * Safe to call on every start: an existing profile keeps its code and name.
 */
export async function ensureProfile(deps: Deps, uid: string, raw: unknown): Promise<ProfileResult> {
  const data: Fields = asObject(raw);
  const protocol = optInt(data, 'protocol', 0, PROTOCOL_MAX);
  const path = `users/${uid}`;
  const existing = await read<UserRecord>(deps.db, path);
  if (existing?.friendCode) {
    if (protocol !== undefined && existing.protocol !== protocol) {
      await deps.db.ref(`${path}/protocol`).set(protocol);
      existing.protocol = protocol;
    }
    return toResult(existing, deps.now());
  }
  const code = await allocateCode(deps.db, 'friendCodes', FRIEND_CODE_LENGTH, uid, deps.rand);
  if (!code) return fail('resource-exhausted', 'no_free_code');
  const fresh: UserRecord = {
    name: FALLBACK_NAME,
    nameHidden: false,
    friendCode: code,
    created: deps.now(),
    protocol: protocol ?? 0,
    full: false,
  };
  // Keep whatever a racing first call already wrote; if that happened, give our code back.
  const result = await deps.db.ref(path).transaction((current: UserRecord | null) => (current?.friendCode ? undefined : { ...current, ...fresh }));
  if (!result.committed) {
    await deps.db.ref(`friendCodes/${code}`).remove();
    const winner = await read<UserRecord>(deps.db, path);
    return toResult(winner ?? fresh, deps.now());
  }
  return toResult(result.snapshot.val() as UserRecord, deps.now());
}

/** Re-checks a name the client wrote (users/{uid}/name) with the shared blocklist; fixes it in place when needed. */
export async function recheckName(deps: Deps, uid: string, written: unknown): Promise<'ok' | 'fixed' | 'removed'> {
  if (written === null || written === undefined) return 'removed';
  const verdict = checkName(written);
  if (verdict.accepted) return 'ok';
  await deps.db.ref(`users/${uid}/name`).set(verdict.name);
  return 'fixed';
}
