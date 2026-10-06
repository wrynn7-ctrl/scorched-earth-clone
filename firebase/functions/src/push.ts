// Push notifications behind an interface, so the emulator never talks to FCM. In the emulator every "send" is recorded
// at _test/fcm/{pushId}; the tests read it back. In production FcmSender sends through Firebase Cloud Messaging.
import type { Database } from 'firebase-admin/database';
import { getFcm } from './admin';
import { isEmulator, PUSH_CHANNEL_ID } from './config';
import { read } from './rtdb';

export interface PushMessage {
  title: string;
  body: string;
  /** FCM data values must be strings. Always carries `type` and, for match events, `matchId`. */
  data: Record<string, string>;
  /** Same key = the phone shows only the latest (retries and quick successive turns do not stack). */
  collapseKey?: string;
}

export interface PushSender {
  /** `tokens` maps tokenHash -> FCM token (users/{uid}/fcm), so a sender can report dead tokens by hash. */
  send(uid: string, tokens: Record<string, string>, message: PushMessage): Promise<void>;
}

/** Emulator stand-in: records what would have been sent. */
export class RecordingSender implements PushSender {
  constructor(
    private readonly db: Database,
    private readonly now: () => number,
  ) {}

  async send(uid: string, tokens: Record<string, string>, message: PushMessage): Promise<void> {
    await this.db.ref('_test/fcm').push({
      uid,
      tokenCount: Object.keys(tokens).length,
      title: message.title,
      body: message.body,
      data: message.data,
      collapseKey: message.collapseKey ?? null,
      channelId: PUSH_CHANNEL_ID,
      at: this.now(),
    });
  }
}

const DEAD_TOKEN_CODES = new Set(['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']);

/** Production sender: FCM multicast, removing tokens FCM says no longer exist. */
export class FcmSender implements PushSender {
  constructor(private readonly db: Database) {}

  async send(uid: string, tokens: Record<string, string>, message: PushMessage): Promise<void> {
    const hashes = Object.keys(tokens);
    const list = hashes.map((hash) => tokens[hash] ?? '');
    const result = await getFcm().sendEachForMulticast({
      tokens: list,
      notification: { title: message.title, body: message.body },
      data: message.data,
      android: {
        priority: 'high',
        collapseKey: message.collapseKey,
        ttl: 24 * 3600 * 1000,
        // The "Turns" channel the game creates; `tag` makes a newer notification for the same match replace the older one.
        notification: { channelId: PUSH_CHANNEL_ID, ...(message.collapseKey ? { tag: message.collapseKey } : {}) },
      },
    });
    const removals: Record<string, null> = {};
    result.responses.forEach((response, index) => {
      const hash = hashes[index];
      if (!response.success && hash && response.error && DEAD_TOKEN_CODES.has(response.error.code)) {
        removals[`users/${uid}/fcm/${hash}`] = null;
      }
    });
    if (Object.keys(removals).length > 0) await this.db.ref().update(removals);
  }
}

export function defaultSender(db: Database, now: () => number): PushSender {
  return isEmulator() ? new RecordingSender(db, now) : new FcmSender(db);
}

/** Sends to every token the user registered. Returns false (and sends nothing) when the user has none. */
export async function notifyUser(db: Database, sender: PushSender, uid: string, message: PushMessage): Promise<boolean> {
  const tokens = await read<Record<string, string>>(db, `users/${uid}/fcm`);
  if (!tokens || Object.keys(tokens).length === 0) return false;
  await sender.send(uid, tokens, message);
  return true;
}
