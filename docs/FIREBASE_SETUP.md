# Setting up Firebase for online play

This is the checklist for turning on online play (friends, invites, matches, push notifications, "Sign in with Google").
The game and the backend code are written to work **without** any of this: they run against the Firebase emulator on a
computer, and an Android build without the Firebase file simply says "online unavailable" and "push unavailable". Nothing
in the repository needs a secret. Everything below is about the real, hosted Firebase project.

Who does what:

- **[Owner]** you, in a web browser (Firebase console, Google Cloud console, Play Console, GitHub settings).
- **[Lead]** Claude or the lead agent, in the repository. You only need to send the lead the values asked for.
- **[CI]** GitHub Actions does it by itself once the secret exists.

Do the steps in order. Total time: about 45 minutes, plus waiting for Google in one place (marked "wait").

## 0. Before you start: the Android package id is final

**[Owner, nothing to decide]** The app's package id is `com.wrynn7.charredhorizons` (`package/unique_name` in
`game/export_presets.cfg`). The owner chose it and it is **final**: Google Play and Firebase both tie the app to this id and
it **can never change** after the first Play upload. The file `google-services.json` you download in step 4 only works for
this exact package id, and the build checks that.

You need: a Google account, a credit or debit card (Firebase's pay-as-you-go plan, see step 1), and, for step 8, a Google
Play Console developer account.

## 1. Create the Firebase project and set a budget alert

1. **[Owner]** Open <https://console.firebase.google.com/>, **Create a project**, name it "Charred Horizons". The project id
   (for example `charredhorizons-4f2a1`) is shown under the name; **write it down**, the lead needs it. Google Analytics: you can
   switch it off, the game does not use it.
2. **[Owner]** Bottom left, click **Spark plan** (the free plan), then **Upgrade** and choose **Blaze** (pay as you go).
   Cloud Functions, which the game needs, are only available on Blaze. Blaze has the same free allowances as Spark; you
   only pay for usage above them (see "Cost" at the end).
3. **[Owner]** Set a **budget alert at $10** right away:
   1. Open <https://console.cloud.google.com/billing> and pick the billing account that Firebase just created.
   2. Left menu **Budgets & alerts**, **Create budget**.
   3. Name "Charred Horizons $10", scope "All projects" (or just this project), amount **$10**, keep the default alert
      thresholds (50%, 90%, 100%), and make sure **email alerts to billing admins** is ticked. **Create**.
   4. Good to know: a budget alert **warns, it does not stop spending**. If you ever get one, tell the lead; the first
      things to check are Realtime Database downloads and Function invocations (Firebase console, Usage tab).

## 2. Add the Android app to the project

**[Owner]** Firebase console, the gear icon next to "Project Overview", **Project settings**, tab **General**, section
**Your apps**, **Add app**, the Android icon:

- **Android package name:** `com.wrynn7.charredhorizons` (exactly; copy it from the line above).
- **App nickname:** Charred Horizons (optional).
- **Debug signing certificate SHA-1:** paste this one. It is the public debug key from `tools/android/debug.keystore`;
  every test build from CI is signed with it, and "Sign in with Google" only works for builds whose SHA-1 is registered:

  ```
  F9:34:C5:E3:A9:C4:9C:15:CA:46:AC:D1:22:AC:64:A9:9E:3D:CA:56
  ```

Click **Register app**. Skip the rest of the wizard (it asks you to add Gradle plugins and to download the file; the
repository does the Gradle part differently, and you download the file in step 4 after sign-in is switched on).

Later, when the game is on Google Play (milestone M8), add two more SHA-1 fingerprints the same way (Project settings,
your Android app, **Add fingerprint**). **[Owner]** Both are in the Play Console, your app, **Test and release**, **App
integrity**, **Play app signing**:

- the **App signing key certificate** SHA-1 (what players' phones see: Sign in with Google needs this one in production),
- the **Upload key certificate** SHA-1 (used for builds you install straight from CI or a file).

## 3. Turn on sign-in methods and find the web client id

1. **[Owner]** Firebase console, left menu **Build**, **Authentication**, **Get started**, tab **Sign-in method**.
2. Click **Anonymous**, switch **Enable** on, **Save**. (The game signs every player in anonymously; no form to fill in.)
3. Click **Add new provider**, **Google**, switch **Enable** on, choose a **public-facing name** ("Charred Horizons") and your
   **support email**, **Save**. Because the Android app and its SHA-1 already exist (step 2), Firebase now also creates the
   matching "Android client" for Google sign-in by itself.
4. **[Owner]** Open the Google provider again: the box **Web SDK configuration** shows the **Web client ID**. It looks like
   `1234567890-abcdefg.apps.googleusercontent.com`. **Send it to the lead.** It is not secret. You can also find it in the
   Google Cloud console, **APIs & Services**, **Credentials**, under "OAuth 2.0 Client IDs" as "Web client (auto created by
   Google Service)". Do **not** use the "Android client" entry.
5. **[Lead]** Puts the web client id into the game configuration (`game/net/net_config.gd`, next to the Firebase web
   config) and passes it to `GoogleSignIn.sign_in(web_client_id)`.
6. **[Owner, before the public launch]** Google Cloud console, **APIs & Services**, **OAuth consent screen**: if it says
   "Testing", only the test users you list can sign in with Google. Click **Publish app** before release. The game only
   asks for the basic profile and email, which needs no Google review.

"Sign in with Google" in the game only **links** the anonymous account, so online matches survive a phone change. Players
who never tap it stay anonymous and that is fine.

## 4. Download google-services.json and give it to CI

`google-services.json` is Firebase's config for the Android app (project id, app id, an API key). It is not a password, but
we keep it out of git anyway, so a stranger cannot point their own copy of the game at your project.

1. **[Owner]** Project settings, tab **General**, **Your apps**, your Android app, **google-services.json**: download it.
   Download it **again** whenever you add a SHA-1 fingerprint or change sign-in providers.
2. **[Owner]** Create the GitHub secret:
   1. Open the repository on GitHub, **Settings**, **Secrets and variables**, **Actions**, **New repository secret**.
   2. Name: **`GOOGLE_SERVICES_JSON`** (exactly, capitals and underscores).
   3. Secret: open the downloaded file in a text editor, select all, copy, paste the **whole file contents**.
   4. **Add secret**.
3. **[Lead, once]** Adds this step to the Android jobs in `.github/workflows/ci.yml` (before "Build debug APK" and
   "Build release AAB"):

   ```yaml
   - name: Firebase config (optional)
     env:
       GOOGLE_SERVICES_JSON: ${{ secrets.GOOGLE_SERVICES_JSON }}
     run: |
       if [ -n "$GOOGLE_SERVICES_JSON" ]; then
         printf '%s' "$GOOGLE_SERVICES_JSON" > android_plugins/google-services.json
         echo "Firebase config written: push notifications are built in"
       else
         echo "No GOOGLE_SERVICES_JSON secret: push is built as a stub (available = false)"
       fi
   ```

   Pull requests from forks never receive secrets, so they automatically get the stub build.
4. **[CI]** `tools/build_android_debug.sh` sees `android_plugins/google-services.json` and builds the real push plugin
   (Firebase Cloud Messaging plus the generated Firebase settings). The build checks that the file contains an app for
   `com.wrynn7.charredhorizons` and fails with a clear message if not, and afterwards checks that the Firebase classes are
   inside the APK. Without the file the same script builds a stub: the game then shows no push features and the app
   contains no Firebase code at all. The file is git-ignored (`android_plugins/.gitignore`); never commit it.

To try it on your own computer instead: save the file as `android_plugins/google-services.json` (or set
`CRATERLINE_GOOGLE_SERVICES_JSON=/path/to/google-services.json`), then run `tools/build_android_debug.sh`.

## 5. Create the Realtime Database

1. **[Owner]** Console, **Build**, **Realtime Database**, **Create database**.
2. **Location:** this **cannot be changed later**. Pick the one closest to most of your players: **Belgium
   (`europe-west1`)** for Europe, **United States (`us-central1`)** for the Americas, **Singapore
   (`asia-southeast1`)** for Asia. Tell the lead which one you chose (the Cloud Functions should run in the matching
   region, and the database URL differs by region).
3. Security rules: choose **Locked mode**. The real rules are deployed in step 6.
4. **[Owner]** Send the lead the **database URL** shown at the top of the Data tab, for example
   `https://charredhorizons-4f2a1-default-rtdb.europe-west1.firebasedatabase.app`.

## 6. Deploy the rules and the functions

**[Lead]** runs these from the repository (later this can become a CI job with a service-account secret). **[Owner]**
sends the lead the project id from step 1 and is available once to log in:

```bash
cd firebase
npm ci                                   # installs the pinned firebase-tools and the function dependencies
npx firebase login                       # opens a browser; log in as the Google account that owns the project
npx firebase use <project-id>            # for example: npx firebase use charredhorizons-4f2a1
npx firebase deploy --only database,functions
```

The first deploy of functions asks to enable a few Google Cloud APIs (Cloud Build, Artifact Registry, Cloud Functions,
Eventarc); say yes. It can take several minutes. The database rules and the functions both come from the repository
(`firebase/database.rules.json`, `firebase/functions`), so a re-deploy after any change is the same command.

Check it worked: Console, Realtime Database, tab **Rules** shows the repository's rules; **Functions** lists the
functions (friend codes, friend requests, blocks, reports, timeouts, push, purchase check, delete-my-data).

Push notifications need nothing more: the functions send them with the Firebase Admin SDK, which uses the project's own
identity (no server key, no extra secret). The notification channel on the phone is called "Turns".

## 7. Test push and sign-in on a phone

1. **[CI]** The dev branch build (the `dev-latest` download page) now contains push and sign-in.
2. **[Owner]** Install it (`docs/INSTALL_ON_PHONE.md`) on a phone with a Google account and Google Play services.
3. Tapping "Sign in with Google" in Settings should show the Google account sheet. If it says "configuration error", the web
   client id is wrong, or the SHA-1 of the build is not registered in step 2 (the dev-latest builds use the debug SHA-1).
4. Push: with the app closed, a turn in a match should show a "Turns" notification, and tapping it opens that match. Android
   13 and newer asks "Allow notifications?" the first time the game wants to (when you create or join a match).

## 8. Purchase verification: a service account for Google Play

The function that unlocks hosting asks Google Play "did this account really buy `full_unlock`?". Google must allow the
function to ask. This uses the function's own service account, so **no key file or secret is created or stored**.

1. **[Lead]** Tells you the **service account email** the purchase function runs as. It is either the default
   `<project-number>-compute@developer.gserviceaccount.com`, or a dedicated `purchase-verifier@<project-id>.iam.gserviceaccount.com`
   (created in Google Cloud console, **IAM & Admin**, **Service accounts**, **Create service account**, no roles needed).
2. **[Owner]** Google Cloud console (the Firebase project), **APIs & Services**, **Library**, search **Google Play Android
   Developer API**, **Enable**.
3. **[Owner]** Play Console (<https://play.google.com/console>), left menu **Users and permissions** (on the developer
   account home, not inside one app), **Invite new users**:
   - Email: the service account email from step 1.
   - Under **App permissions**, **Add app**, choose Charred Horizons.
   - Account permissions for the app: tick **View app information and download bulk reports (read-only)**, **View financial
     data, orders, and cancellation survey responses**, and **Manage orders and subscriptions**.
   - **Invite user**.
4. **Wait:** Google says it can take up to 24 to 48 hours before the permission works. The Play app and the in-app product
   `full_unlock` must exist first (see `docs/PLAY_BILLING_SETUP.md`).
5. **[Lead]** Tests it with a license-tester purchase once the internal-testing build is on Play.

## 9. Reviewing reported names

Players can report a name; after 3 reports from 3 different players the name is hidden automatically (shown as
"PLAYER" plus a short id) until you look at it.

**[Owner]** Console, **Realtime Database**, tab **Data**:

1. Open **`nameReports`**. Each child is the **uid of a reported player**; inside it are the uids of the reporters.
   Children with 3 or more reporters are the hidden ones.
2. Open **`users`**, then that uid: you see `name` (the name that was reported) and `nameHidden` (`true` if it is hidden).
3. Decide:
   - **The name is fine:** change `nameHidden` to `false`, then delete that uid under `nameReports` (otherwise the next
     report hides it again at once).
   - **The name is bad:** change `name` to something neutral (for example `PLAYER`), then set `nameHidden` to `false`. The
     player can pick a new name in Settings.
   - **A player keeps abusing it:** Console, **Authentication**, **Users**, find the uid, **Delete account**.
4. The reasons sent with a report are under **`reports`** (`reason`, `reporterUid`, `targetUid`).

Edits in the console bypass the game's rules, so change only the fields named above. There is no email notification in the
first release: look at `nameReports` now and then (the lead can add a daily summary later).

## 10. Cost expectations

Rough numbers, from PLAN section 7.6. Firebase prices and free allowances change; the live numbers are on
<https://firebase.google.com/pricing> and on your **Usage and billing** page in the console.

| Usage | Monthly cost |
|---|---|
| Development and a small launch (friends and family) | **$0** (inside the free allowances) |
| A few thousand active players | about **$0 to $10** |
| A hit (tens of thousands of daily players) | about **$25 to $100** |

What costs money, in order of likelihood: Realtime Database **downloads** (the game streams match updates; a match action
is a few hundred bytes, so this stays small), Cloud Functions invocations (each match action triggers one small function),
and stored data (finished matches are removed by a function). Push notifications (FCM), anonymous sign-in and Google sign-in
are free. A card is required for Blaze; the $10 alert from step 1 is your early warning.

## Quick reference: what the lead needs from you

| Value | Where it comes from | Used for |
|---|---|---|
| Firebase project id | step 1 | `.firebaserc`, deploy |
| Web client id | step 3 | `GoogleSignIn.sign_in(web_client_id)` |
| `GOOGLE_SERVICES_JSON` GitHub secret | step 4 | push notifications in CI builds |
| Realtime Database URL and region | step 5 | `game/net/net_config.gd`, function region |
| Service account invited in Play Console | step 8 | purchase verification |
