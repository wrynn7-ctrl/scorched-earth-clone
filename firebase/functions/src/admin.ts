// One place that creates the Admin SDK app. In production (Cloud Functions) the config comes from FIREBASE_CONFIG. Under the
// emulators, and in the tests that import this file, it is built from the emulator environment variables.
import { getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';
import { getDatabase, type Database } from 'firebase-admin/database';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';

export const DEFAULT_PROJECT = 'demo-craterline';

const EMULATOR_APP = 'craterline-emulator';

export function adminApp(): App {
  const emulatorHost = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  if (emulatorHost) {
    const existing = getApps().find((app) => app.name === EMULATOR_APP);
    if (existing) return existing;
    // The default database of a real project is "<project>-default-rtdb". Pin the emulator to the same name (the
    // emulator's own FIREBASE_CONFIG would use a different namespace), so database.rules.json and its indexes apply.
    // A named app, because the functions emulator may already have created the default app with its own namespace.
    const projectId = process.env.GCLOUD_PROJECT ?? process.env.GOOGLE_CLOUD_PROJECT ?? DEFAULT_PROJECT;
    return initializeApp({ projectId, databaseURL: `http://${emulatorHost}?ns=${projectId}-default-rtdb` }, EMULATOR_APP);
  }
  if (!process.env.FIREBASE_CONFIG) throw new Error('No FIREBASE_CONFIG and no FIREBASE_DATABASE_EMULATOR_HOST: refusing to guess a database');
  return getApps()[0] ?? initializeApp();
}

export function getDb(): Database {
  return getDatabase(adminApp());
}

export function getAuthAdmin(): Auth {
  return getAuth(adminApp());
}

export function getFcm(): Messaging {
  return getMessaging(adminApp());
}
