// Full-version purchase verification (PLAN section 7.3, ARCHITECTURE section 45): the client sends the Google Play purchase
// token, the server asks Google whether it is a real, completed purchase of the full unlock, and only then sets
// users/{uid}/full = true. Nothing a client can write grants hosting.
//
// The Play call sits behind PurchaseVerifier. The emulator uses a stub that accepts the single token "test-full".
import { createHash } from 'node:crypto';
import { GoogleAuth } from 'google-auth-library';
import { DEFAULT_PLAY_PACKAGE, DEFAULT_PLAY_PRODUCT, isEmulator, TEST_PURCHASE_TOKEN } from './config';
import type { Deps } from './deps';
import { asObject, fail, reqString } from './errors';
import { read, type UserRecord } from './rtdb';

export interface PurchaseResult {
  valid: boolean;
  orderId?: string;
  reason?: string;
}

export interface PurchaseVerifier {
  verify(purchaseToken: string): Promise<PurchaseResult>;
}

/** Emulator only: no network, accepts exactly "test-full". */
export class StubVerifier implements PurchaseVerifier {
  verify(purchaseToken: string): Promise<PurchaseResult> {
    return Promise.resolve(purchaseToken === TEST_PURCHASE_TOKEN ? { valid: true, orderId: 'test-order' } : { valid: false, reason: 'unknown_token' });
  }
}

export interface PlayConfig {
  packageName: string;
  productId: string;
  /**
   * Optional service-account key JSON. Normally empty: the function then calls Google as its own runtime service account
   * (Application Default Credentials), which the owner invites in Play Console (docs/FIREBASE_SETUP.md section 8), so no key
   * file exists anywhere. Setting the PLAY_SERVICE_ACCOUNT_JSON environment variable overrides that (for example from a
   * Secret Manager secret mapped to an environment variable); it is never read from the repository.
   */
  serviceAccountJson?: string;
}

interface PlayProduct {
  purchaseState?: number; // 0 purchased, 1 canceled, 2 pending
  acknowledgementState?: number; // 0 not yet, 1 acknowledged
  orderId?: string;
}

/** The part of google-auth-library's client this file uses (a seam for tests). */
export interface PlayHttp {
  getClient(): Promise<{ request<T>(options: { url: string; method?: 'GET' | 'POST'; data?: unknown }): Promise<{ data: T }> }>;
}

const PLAY_BASE = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const PLAY_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';

/** Google Play Developer API (androidpublisher v3) `purchases.products`. */
export class PlayVerifier implements PurchaseVerifier {
  private readonly http: PlayHttp;

  constructor(
    private readonly config: PlayConfig,
    http?: PlayHttp,
  ) {
    const key = (config.serviceAccountJson ?? '').trim();
    this.http = http ?? new GoogleAuth({ scopes: [PLAY_SCOPE], ...(key === '' ? {} : { credentials: JSON.parse(key) as Record<string, unknown> }) });
  }

  async verify(purchaseToken: string): Promise<PurchaseResult> {
    const client = await this.http.getClient();
    const base = `${PLAY_BASE}/${encodeURIComponent(this.config.packageName)}/purchases/products/${encodeURIComponent(this.config.productId)}/tokens/${encodeURIComponent(purchaseToken)}`;
    let product: PlayProduct;
    try {
      product = (await client.request<PlayProduct>({ url: base })).data;
    } catch (error) {
      const status = (error as { response?: { status?: number } }).response?.status;
      // Google answers 400/404/410 for a token it does not know or that was refunded: that is "not valid", not a server fault.
      if (status === 400 || status === 404 || status === 410) return { valid: false, reason: 'unknown_token' };
      throw error;
    }
    if (product.purchaseState !== 0) return { valid: false, reason: product.purchaseState === 2 ? 'pending' : 'not_purchased' };
    if (product.acknowledgementState === 0) {
      // Unacknowledged purchases are refunded after 3 days; the billing plugin normally acknowledges, this is the safety net.
      await client.request({ url: `${base}:acknowledge`, method: 'POST', data: {} }).catch(() => undefined);
    }
    return { valid: true, orderId: product.orderId };
  }
}

/** SHA-256 of a purchase token: the key under purchaseTokens/, so raw tokens are never stored. */
export function tokenHash(purchaseToken: string): string {
  return createHash('sha256').update(purchaseToken).digest('hex');
}

export interface VerifyResult {
  full: true;
}

/**
 * Verifies the token and grants `full`. One token can unlock one account at a time (purchaseTokens/{hash} -> uid), so a
 * token cannot be handed around. Calling again with the same token on the same account is fine.
 */
export async function verifyPurchase(deps: Deps, uid: string, raw: unknown, verifier: PurchaseVerifier): Promise<VerifyResult> {
  const token = reqString(asObject(raw), 'purchaseToken', 4096);
  const user = await read<UserRecord>(deps.db, `users/${uid}`);
  if (!user?.friendCode) return fail('failed-precondition', 'no_profile');
  const hash = tokenHash(token);
  const claim = await deps.db.ref(`purchaseTokens/${hash}`).transaction((current: string | null) => (current === null || current === uid ? uid : undefined));
  if (!claim.committed) return fail('already-exists', 'token_used');
  const verdict = await verifier.verify(token);
  if (!verdict.valid) {
    // Give the claim back, so a pending purchase that completes later can still be verified.
    await deps.db.ref(`purchaseTokens/${hash}`).remove();
    return fail('permission-denied', verdict.reason ?? 'not_purchased');
  }
  await deps.db.ref().update({
    [`users/${uid}/full`]: true,
    [`users/${uid}/purchase`]: { at: deps.now(), tokenHash: hash, ...(verdict.orderId ? { orderId: verdict.orderId } : {}) },
  });
  return { full: true };
}

/** The verifier for this environment: the stub in the emulator, Google Play otherwise. */
export function chooseVerifier(config: () => PlayConfig): PurchaseVerifier {
  return isEmulator() ? new StubVerifier() : new PlayVerifier(config());
}

export const PLAY_DEFAULTS = { packageName: DEFAULT_PLAY_PACKAGE, productId: DEFAULT_PLAY_PRODUCT };
