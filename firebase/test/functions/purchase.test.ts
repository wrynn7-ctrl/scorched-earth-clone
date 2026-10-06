// verifyPurchase, the emulator-only testSetFull, and what "full" unlocks (hosting).
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { callWith, CallError, db, newUser, signUp, value } from './harness';

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
