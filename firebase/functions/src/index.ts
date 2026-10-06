// Entry point: every deployed function is exported from here. Handlers live in the other files and take a `Deps`.
// See firebase/README.md for the list of callables, their arguments and the paths a client reads and writes.
import { defineString } from 'firebase-functions/params';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { deleteMyData as deleteMyDataHandler } from './account';
import { isEmulator, MAX_INSTANCES, REGION } from './config';
import { defaultDeps, type Deps } from './deps';
import { asObject, reqId } from './errors';
import {
  blockUser,
  removeFriend as removeFriendHandler,
  reportName as reportNameHandler,
  respondFriendRequest as respondFriendRequestHandler,
  sendFriendRequest as sendFriendRequestHandler,
  sendFriendRequestToUid as sendFriendRequestToUidHandler,
  unblockUser,
} from './friends';
import {
  createMatch as createMatchHandler,
  invite as inviteHandler,
  joinMatch as joinMatchHandler,
  leaveMatch as leaveMatchHandler,
  startMatch as startMatchHandler,
  updateLobby as updateLobbyHandler,
} from './matches';
import { ensureProfile as ensureProfileHandler } from './profile';
import { chooseVerifier, PLAY_DEFAULTS, verifyPurchase as verifyPurchaseHandler } from './purchase';

// --- Callable functions -------------------------------------------------------------------------------------------

const callOptions = { region: REGION, maxInstances: MAX_INSTANCES };

/** Wraps a handler as a callable that requires a signed-in (anonymous is fine) caller. */
function authed<T>(handler: (deps: Deps, uid: string, data: unknown) => Promise<T>) {
  return onCall(callOptions, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'sign_in_required');
    return handler(defaultDeps(), uid, request.data);
  });
}

export const ensureProfile = authed(ensureProfileHandler);
export const sendFriendRequest = authed(sendFriendRequestHandler);
export const sendFriendRequestToUid = authed(sendFriendRequestToUidHandler);
export const respondFriendRequest = authed(respondFriendRequestHandler);
export const removeFriend = authed(removeFriendHandler);
export const block = authed(blockUser);
export const unblock = authed(unblockUser);
export const reportName = authed(reportNameHandler);

export const createMatch = authed(createMatchHandler);
export const updateLobby = authed(updateLobbyHandler);
export const joinMatch = authed(joinMatchHandler);
export const leaveMatch = authed(leaveMatchHandler);
export const startMatch = authed(startMatchHandler);
export const invite = authed(inviteHandler);

export const deleteMyData = authed((deps, uid) => deleteMyDataHandler(deps, uid));

// Purchase verification. The Play settings are deploy-time parameters (defaults in config.ts). The function calls Google Play
// as its own runtime service account, so there is no key and no secret to deploy; see PlayConfig in purchase.ts.
const playPackage = defineString('PLAY_PACKAGE_NAME', { default: PLAY_DEFAULTS.packageName });
const playProduct = defineString('PLAY_PRODUCT_ID', { default: PLAY_DEFAULTS.productId });

export const verifyPurchase = onCall(callOptions, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'sign_in_required');
  const verifier = chooseVerifier(() => ({
    packageName: playPackage.value(),
    productId: playProduct.value(),
    serviceAccountJson: process.env.PLAY_SERVICE_ACCOUNT_JSON ?? '',
  }));
  return verifyPurchaseHandler(defaultDeps(), uid, request.data, verifier);
});

/**
 * Emulator only: marks a user as a full owner so tests can host without a purchase. It is not even exported (so never
 * deployed) outside the emulator, and refuses to run there too if the guard is somehow bypassed.
 */
export const testSetFull = isEmulator()
  ? onCall(callOptions, async (request) => {
      if (!isEmulator()) throw new HttpsError('permission-denied', 'emulator_only');
      const uid = reqId(asObject(request.data), 'uid');
      await defaultDeps().db.ref(`users/${uid}/full`).set(true);
      return { full: true };
    })
  : undefined;

// --- Triggers and the schedule ------------------------------------------------------------------------------------

export { onFriendAccepted, onInvite, onMatchOver, onNameWrite, onPushTokenAdded, onTurnChange } from './triggers';
export { timeoutSweep } from './sweep';
