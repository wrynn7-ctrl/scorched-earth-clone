// Constants shared by every function. Numbers that also appear in database.rules.json (firebase/rules/build_rules.mjs)
// are marked; change both together.

/**
 * Where functions run. Realtime Database triggers must run in the same region as the database, so create the database
 * in this region too (Belgium). See firebase/README.md.
 */
export const REGION = 'europe-west1';

/**
 * Region for the Realtime Database triggers. The database emulator only delivers events to triggers registered in
 * us-central1, so tests run them there; everywhere else they share REGION (and so must the database).
 */
export const TRIGGER_REGION = process.env.FUNCTIONS_EMULATOR === 'true' ? 'us-central1' : REGION;

export const MAX_INSTANCES = 10;

/** True inside the Firebase emulator suite (the CLI sets FUNCTIONS_EMULATOR for the functions emulator). */
export function isEmulator(): boolean {
  return process.env.FUNCTIONS_EMULATOR === 'true';
}

// Codes: 32 characters with no 0/O/1/I (ARCHITECTURE sections 44 and 45).
export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export const FRIEND_CODE_LENGTH = 8;
export const MATCH_CODE_LENGTH = 6;

export const REPORTS_TO_HIDE_NAME = 3;
export const MAX_PENDING_REQUESTS = 50;
export const MAX_USER_MATCHES = 40;

export const SECOND = 1000;
export const HOUR = 3600 * SECOND;
export const DAY = 24 * HOUR;

/** A lobby nobody started is abandoned after this long. */
export const LOBBY_TTL_MS = DAY;
/** A running match whose turn is not waiting on a human deadline (needs resolve, shop) is abandoned after this idle time. */
export const IDLE_TTL_MS = 14 * DAY;
/** Finished (over / abandoned) matches are deleted this long after they end, to keep storage small. */
export const RETENTION_MS = 30 * DAY;

/** "Online" means a heartbeat younger than this (ARCHITECTURE section 45, same as the rules). */
export const PRESENCE_FRESH_MS = 75 * SECOND;

// Turn markers in meta/turn.tank (ARCHITECTURE section 46).
export const TURN_NEEDS_RESOLVE = -1;
export const TURN_SHOP = -2;

export const MIN_TANKS = 2;
export const MAX_TANKS = 8;
export const MAX_ROUNDS = 20;
export const MAX_WIND = 100;
export const LOVE_WIND_MAX = 30;
export const MAX_START_MONEY = 1_000_000;
export const MAX_TEAMS = 4;
export const CPU_LEVEL_MIN = 1;
export const CPU_LEVEL_MAX = 4;
/** The level an auto-played seat gets when its player leaves or deletes their data (CPU Normal). */
export const CPU_LEVEL_NORMAL = 2;
export const MODE_LOVE = 1;
export const PROTOCOL_MAX = 1_000_000;

// Purchase verification. Both are Firebase parameters, so they are set at deploy time, not in the code.
export const DEFAULT_PLAY_PACKAGE = 'com.wrynn7.craterline'; // game/export_presets.cfg package/unique_name
export const DEFAULT_PLAY_PRODUCT = 'full_unlock'; // Entitlement.PRODUCT_ID
/** The one purchase token the emulator accepts (the real Play API is never called there). */
export const TEST_PURCHASE_TOKEN = 'test-full';
