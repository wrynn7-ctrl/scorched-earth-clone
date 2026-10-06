// One place that creates the Admin SDK app. Inside Cloud Functions the config comes from FIREBASE_CONFIG. Outside (the
// emulator tests, which import this file) it is built from the emulator environment variables.
import { getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';
import { getDatabase, type Database } from 'firebase-admin/database';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';

export const DEFAULT_PROJECT = 'demo-craterline';

export function adminApp(): App {
  const existing = getApps()[0];
  if (existing) return existing;
  if (process.env.FIREBASE_CONFIG) return initializeApp();
  const projectId = process.env.GCLOUD_PROJECT ?? DEFAULT_PROJECT;
  const host = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  if (!host) throw new Error('No FIREBASE_CONFIG and no FIREBASE_DATABASE_EMULATOR_HOST: refusing to guess a database');
  return initializeApp({ projectId, databaseURL: `http://${host}?ns=${projectId}-default-rtdb` });
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
