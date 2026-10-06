// What a real deployment would contain, checked without the emulator: the same discovery step `firebase deploy` runs, with
// FUNCTIONS_EMULATOR unset. Guards the things that must never slip into production (the test-only function) and the things
// that must always be there (every callable, every trigger in one region, the schedule, the purchase settings).
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';

interface Endpoint {
  region: string[];
  callableTrigger?: unknown;
  eventTrigger?: { eventType: string };
  scheduleTrigger?: { schedule: string };
}
interface Manifest {
  endpoints: Record<string, Endpoint>;
  params: { name: string; type: string }[];
}

const functionsDir = join(__dirname, '..', '..', 'functions');
const manifestPath = join(functionsDir, 'lib', 'manifest.test-output.json');

function discover(): Manifest {
  const env: NodeJS.ProcessEnv = { ...process.env, FUNCTIONS_MANIFEST_OUTPUT_PATH: manifestPath, GCLOUD_PROJECT: 'craterline-prod-check' };
  delete env.FUNCTIONS_EMULATOR;
  delete env.FIREBASE_DATABASE_EMULATOR_HOST;
  execFileSync(join(functionsDir, 'node_modules', '.bin', 'firebase-functions'), ['.'], { cwd: functionsDir, env, stdio: 'pipe', timeout: 60000 });
  try {
    return JSON.parse(readFileSync(manifestPath, 'utf8')) as Manifest;
  } finally {
    if (existsSync(manifestPath)) rmSync(manifestPath);
  }
}

describe('deployment manifest', () => {
  const manifest = discover();
  const names = Object.keys(manifest.endpoints);

  it('never contains the emulator-only function', () => {
    assert.ok(!names.some((n) => /^_?test/i.test(n)), `unexpected test function in ${names.join(', ')}`);
  });

  it('has every callable the client uses', () => {
    const callables = names.filter((n) => manifest.endpoints[n]?.callableTrigger);
    assert.deepEqual(callables.sort(), [
      'block', 'createMatch', 'deleteMyData', 'ensureProfile', 'invite', 'joinMatch', 'leaveMatch', 'removeFriend',
      'reportName', 'respondFriendRequest', 'sendFriendRequest', 'sendFriendRequestToUid', 'startMatch', 'unblock', 'updateLobby', 'verifyPurchase',
    ].sort());
  });

  it('has the database triggers and the 15-minute sweep', () => {
    for (const trigger of ['onFriendAccepted', 'onInvite', 'onMatchOver', 'onNameWrite', 'onTurnChange']) {
      assert.match(manifest.endpoints[trigger]?.eventTrigger?.eventType ?? '', /google\.firebase\.database\.ref\.v1\./, trigger);
    }
    assert.equal(manifest.endpoints.timeoutSweep?.scheduleTrigger?.schedule, 'every 15 minutes');
  });

  it('deploys everything to one region, so the database can sit next to it', () => {
    const regions = new Set(names.flatMap((n) => manifest.endpoints[n]?.region ?? []));
    assert.deepEqual([...regions], ['europe-west1']);
  });

  it('declares the Play purchase settings, and needs no secret to deploy (the function uses its own service account)', () => {
    const byName = Object.fromEntries(manifest.params.map((p) => [p.name, p.type]));
    assert.equal(byName.PLAY_PACKAGE_NAME, 'string');
    assert.equal(byName.PLAY_PRODUCT_ID, 'string');
    assert.ok(!manifest.params.some((p) => p.type === 'secret'), 'a secret param would make every deploy ask for a value');
  });
});
