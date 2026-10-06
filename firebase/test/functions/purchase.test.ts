// verifyPurchase, the emulator-only testSetFull, and what "full" unlocks (hosting).
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { PlayVerifier, StubVerifier, tokenHash, verifyPurchase, type PlayHttp, type PurchaseVerifier } from '../../functions/src/purchase';
import { callWith, type CallError, db, directDeps, newUser, signUp, value } from './harness';

describe('functions: verifyPurchase', () => {
  // The stub accepts one fixed token, so every test starts with it unclaimed.
  beforeEach(async () => {
    await db.ref('purchaseTokens').remove();
  });

  it('accepts the emulator test token and sets full, recording a hashed token', async () => {
    const user = await newUser();
    assert.equal((await user.profile()).full, false);
    const result = await user.call<{ full: boolean }>('verifyPurchase', { purchaseToken: 'test-full' });
    assert.equal(result.full, true);
    const profile = await user.profile();
    assert.equal(profile.full, true);
    const purchase = profile.purchase as { tokenHash: string; orderId: string };
    assert.equal(purchase.tokenHash, createHash('sha256').update('test-full').digest('hex'));
    assert.equal(await value(`purchaseTokens/${purchase.tokenHash}`), user.uid);
  });

  it('is repeatable by the same account, but a token cannot unlock a second account', async () => {
    const owner = await newUser();
    await owner.call('verifyPurchase', { purchaseToken: 'test-full' });
    await owner.call('verifyPurchase', { purchaseToken: 'test-full' });
    const other = await newUser();
    await assert.rejects(other.call('verifyPurchase', { purchaseToken: 'test-full' }), (e: CallError) => e.status === 'ALREADY_EXISTS' && e.reason === 'token_used');
    assert.equal((await other.profile()).full, false);
  });

  it('refuses any other token and leaves the account free', async () => {
    const user = await newUser();
    await assert.rejects(user.call('verifyPurchase', { purchaseToken: 'made-up' }), (e: CallError) => e.status === 'PERMISSION_DENIED');
    assert.equal((await user.profile()).full, false);
    assert.equal(await value(`purchaseTokens/${createHash('sha256').update('made-up').digest('hex')}`), null);
  });

  it('refuses bad arguments, signed-out callers and users without a profile', async () => {
    const user = await newUser();
    await assert.rejects(user.call('verifyPurchase', {}), (e: CallError) => e.status === 'INVALID_ARGUMENT');
    await assert.rejects(user.call('verifyPurchase', { purchaseToken: 5 }), (e: CallError) => e.status === 'INVALID_ARGUMENT');
    await assert.rejects(callWith('verifyPurchase', { purchaseToken: 'test-full' }, null), (e: CallError) => e.status === 'UNAUTHENTICATED');
    const bare = await signUp();
    await assert.rejects(bare.call('verifyPurchase', { purchaseToken: 'test-full' }), (e: CallError) => e.status === 'FAILED_PRECONDITION');
  });
});

describe('functions: testSetFull (emulator only)', () => {
  it('marks a user full in the emulator', async () => {
    const user = await newUser();
    await user.call('testSetFull', { uid: user.uid });
    assert.equal((await user.profile()).full, true);
  });

  it('refuses a malformed uid, so it can never address another path', async () => {
    const user = await newUser();
    await assert.rejects(user.call('testSetFull', { uid: '../x' }), (e: CallError) => e.status === 'INVALID_ARGUMENT');
  });
});

describe('purchase verification logic (fake Google, direct)', () => {
  const clock = { now: 1_000_000 };
  const verifierSaying = (result: { valid: boolean; orderId?: string; reason?: string }): PurchaseVerifier => ({ verify: () => Promise.resolve(result) });
  const reasonOf = (e: unknown): string => `${(e as { code: string }).code}:${(e as { message: string }).message}`;

  it('grants full with the order id when the verifier approves', async () => {
    const user = await newUser();
    const token = `real-token-${user.uid}`;
    await verifyPurchase(directDeps(clock), user.uid, { purchaseToken: token }, verifierSaying({ valid: true, orderId: 'GPA.1234' }));
    const profile = await user.profile();
    assert.equal(profile.full, true);
    assert.deepEqual(profile.purchase, { at: 1_000_000, tokenHash: tokenHash(token), orderId: 'GPA.1234' });
  });

  it('gives the token back when Google says no, so a pending purchase can be retried', async () => {
    const user = await newUser();
    const token = `pending-${user.uid}`;
    await assert.rejects(verifyPurchase(directDeps(clock), user.uid, { purchaseToken: token }, verifierSaying({ valid: false, reason: 'pending' })), (e) => reasonOf(e) === 'permission-denied:pending');
    assert.equal(await value(`purchaseTokens/${tokenHash(token)}`), null);
    assert.equal((await user.profile()).full, false);
    await verifyPurchase(directDeps(clock), user.uid, { purchaseToken: token }, verifierSaying({ valid: true }));
    assert.equal((await user.profile()).full, true);
  });

  it('does not unlock an account when Google could not be asked (an outage is not a purchase)', async () => {
    const user = await newUser();
    const failing: PurchaseVerifier = { verify: () => Promise.reject(new Error('503 from Google')) };
    await assert.rejects(verifyPurchase(directDeps(clock), user.uid, { purchaseToken: `outage-${user.uid}` }, failing), /503/);
    assert.equal((await user.profile()).full, false);
  });

  it('keeps one token on one account', async () => {
    const [first, second] = [await newUser(), await newUser()];
    const token = `shared-${first.uid}`;
    await verifyPurchase(directDeps(clock), first.uid, { purchaseToken: token }, verifierSaying({ valid: true }));
    await assert.rejects(verifyPurchase(directDeps(clock), second.uid, { purchaseToken: token }, verifierSaying({ valid: true })), (e) => reasonOf(e) === 'already-exists:token_used');
  });

  it('the stub accepts only "test-full"', async () => {
    assert.equal((await new StubVerifier().verify('test-full')).valid, true);
    assert.equal((await new StubVerifier().verify('test-full ')).valid, false);
    assert.equal((await new StubVerifier().verify('')).valid, false);
  });
});

describe('PlayVerifier (fake Google Play API)', () => {
  interface Call {
    url: string;
    method?: string;
  }
  const fakeGoogle = (answer: () => unknown, calls: Call[]): PlayHttp => ({
    getClient: () =>
      Promise.resolve({
        request: <T>(options: { url: string; method?: 'GET' | 'POST' }): Promise<{ data: T }> => {
          calls.push({ url: options.url, method: options.method });
          if (options.method === 'POST') return Promise.resolve({ data: {} as T });
          const result = answer();
          return result instanceof Error ? Promise.reject(result) : Promise.resolve({ data: result as T });
        },
      }),
  });
  const config = { packageName: 'com.example.game', productId: 'full_unlock' };
  const httpError = (status: number): Error => Object.assign(new Error(`status ${status}`), { response: { status } });

  it('asks the androidpublisher v3 products endpoint for this package, product and token', async () => {
    const calls: Call[] = [];
    const verifier = new PlayVerifier(config, fakeGoogle(() => ({ purchaseState: 0, acknowledgementState: 1, orderId: 'GPA.9' }), calls));
    assert.deepEqual(await verifier.verify('tok/en+1'), { valid: true, orderId: 'GPA.9' });
    assert.equal(calls.length, 1, 'already acknowledged: no acknowledge call');
    assert.equal(calls[0]?.url, 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.example.game/purchases/products/full_unlock/tokens/tok%2Fen%2B1');
  });

  it('acknowledges a purchase nobody acknowledged yet', async () => {
    const calls: Call[] = [];
    await new PlayVerifier(config, fakeGoogle(() => ({ purchaseState: 0, acknowledgementState: 0 }), calls)).verify('t');
    assert.deepEqual(calls.map((c) => c.method ?? 'GET'), ['GET', 'POST']);
    assert.ok(calls[1]?.url.endsWith('/tokens/t:acknowledge'));
  });

  it('says not valid for cancelled and pending purchases', async () => {
    assert.deepEqual(await new PlayVerifier(config, fakeGoogle(() => ({ purchaseState: 1 }), [])).verify('t'), { valid: false, reason: 'not_purchased' });
    assert.deepEqual(await new PlayVerifier(config, fakeGoogle(() => ({ purchaseState: 2 }), [])).verify('t'), { valid: false, reason: 'pending' });
  });

  it('says not valid for a token Google does not know (400, 404, 410) but raises on a server fault', async () => {
    for (const status of [400, 404, 410]) {
      assert.deepEqual(await new PlayVerifier(config, fakeGoogle(() => httpError(status), [])).verify('t'), { valid: false, reason: 'unknown_token' });
    }
    await assert.rejects(new PlayVerifier(config, fakeGoogle(() => httpError(500), [])).verify('t'), /status 500/);
    await assert.rejects(new PlayVerifier(config, fakeGoogle(() => httpError(403), [])).verify('t'), /status 403/);
  });
});
