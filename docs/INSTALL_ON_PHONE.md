# Installing Charred Horizons test builds on your Samsung phone

Test builds are not on Google Play yet, so you install them by hand from a file (an "APK"). It takes about two minutes
the first time and about thirty seconds for every update after that. It works on Android 8 or newer.

The download page, always the same address:
<https://github.com/wrynn7-ctrl/scorched-earth-clone/releases/tag/dev-latest>

Tip: open that page on the phone and add it to your browser bookmarks or Home screen.

## First install

> **Renamed game.** The game used to be called "Craterline". The new build is **Charred Horizons** and installs as a
> separate app (new package id `com.wrynn7.charredhorizons`), so it does not replace the old one. You can uninstall the
> old "Craterline" test app. Its saved data does not carry over.

1. **Open the page** above in the browser on your phone (Chrome or Samsung Internet).
   - When I checked, the repository was public, so no login is needed. If it is ever made private, log in to GitHub in
     that same browser first, otherwise the page shows "404 Not Found".
2. Scroll to **Assets** and tap **charredhorizons-debug.apk**. If the browser says "This type of file can harm your device",
   tap **Download anyway** (or **OK**). Wait until the download finishes.
3. Tap **Open** in the download notification (or open the **My Files** app, then **Downloads**, then tap the file).
4. The first time, the phone says it is not allowed to install apps from this source:
   - Tap **Settings** in that message.
   - Switch on **Allow from this source**, then press the back arrow.
   - Or go there by hand: **Settings > Apps > Special access > Install unknown apps**, pick your browser
     (Chrome or Samsung Internet), switch on **Allow from this source**.
5. Tap **Install**.
6. If a **Google Play Protect** box appears (see below), choose **Install anyway**.
7. Tap **Open** and play.

### If Samsung "Auto Blocker" stops the install
Newer Samsung phones (One UI 6 and later) may show "Blocked by Auto Blocker". Open **Settings > Security and privacy >
Auto Blocker** and switch it off, install the app, and switch it back on afterwards if you like.

### Google Play Protect warning
Google may say **"App blocked to protect your device"** or **"Unknown developer"** because the app is not from Google
Play. That is expected for test builds. Tap **More details**, then **Install anyway**. If it offers **Scan app**, you can
tap that first; it only checks the file and is safe to do. You can also open the Play Store, tap your profile picture,
then **Play Protect > Settings (the gear) > Scan apps with Play Protect** and switch it off, but you do not need to.

## Installing an update (keeps your data)

1. Open the same page again and download **charredhorizons-debug.apk** again. The file always has the same name, and it
   always holds the newest build (the page lists the build time and commit).
2. Open it and tap **Update** (or **Install**). **Do not uninstall the old version first.** Every test build is signed with
   the same key, so the new one installs right on top and keeps your saved data.
3. If Android ever says **"App not installed as package conflicts with an existing package"**, the old copy was made
   with a different key (for example, one built on someone else's computer). Uninstall Charred Horizons once, then install
   again. Saved test data is lost in that case, which does not matter for test builds.

## Good to know
- These are **debug** builds for testing: they are a bit slower and bigger than the final game will be (the file is about 160 MB;
  the download takes a minute on Wi-Fi). Since milestone M5 they are made with a Gradle build so that in-app purchases can work
  later; installing them works exactly as before. See `docs/BUILD.md`.
- The app is called **Charred Horizons** and has a placeholder icon for now.
- Deleting the downloaded APK file after installing is fine; the app stays.
