# Setting up the "Full game" purchase in Google Play

This is the owner's checklist for making the **Unlock the full game** button work. The game code is finished: it asks
Google Play for one in-app product called `full_unlock`. Until you create that product in the Play Console, the button
shows "Store unavailable" on a phone (that is correct and safe). Nothing here needs a secret in the repo.

## What the game expects

| Thing | Value |
|---|---|
| Product ID | `full_unlock` (exactly this, lower case; it is `Entitlement.PRODUCT_ID` in `game/platform/entitlement.gd`) |
| Product type | One-time product (Play calls it "in-app product"), **non-consumable**: bought once, owned forever |
| Suggested price | $3.99 (you can change it any time; the game shows whatever Play says, in the player's currency) |
| Package name | `com.wrynn7.charredhorizons` (final, it can never change after the first upload, see `docs/BUILD.md`) |

What the player gets is listed in `docs/ARCHITECTURE.md` section 32 and on the Unlock screen.

## 1. Create the in-app product

You need a Play Console developer account and the app created (with the package name above). Play only lets you create
in-app products after an app bundle has been uploaded at least once (step 3 below), so do steps 1 and 3 together.

1. Play Console, choose the app, left menu **Monetize with Play** then **Products** then **In-app products**.
2. **Create product**.
3. Product ID: `full_unlock`. This can never be changed afterwards.
4. Name: "Full game". Description: "Unlock all weapons, tanks, themes and computer opponents."
5. Under **Purchase option** (or "Pricing") add a **Buy** option, set the price (for example $3.99) and adjust other
   countries if you like. Make the product **Active**.
6. Do not create a subscription, a trial or an offer. The game is one purchase, no ads.

## 2. Add license testers (so you can buy without paying)

1. Play Console home (not inside one app), **Settings** then **License testing**.
2. Add the Gmail addresses of the Google accounts on the test phones (yours, friends').
3. Set **License response** to `RESPOND_NORMALLY`.

Testers see the normal purchase sheet, but the card is not charged. Test purchases can be refunded or reset in the
Play Store app (Payments and subscriptions, Budget and history) so you can test again.

## 3. Upload to the internal testing track (required before purchases work)

Purchases only work for builds that Play knows about, signed with the real upload key, installed from Play (not from a
`.apk` you copied over).

1. Real release signing is set up in milestone M8. Until then the AAB from `tools/build_android_release.sh` is signed
   with a public debug key, and Play will reject it.
2. When M8 is done: Play Console, **Testing** then **Internal testing**, **Create new release**, upload the `.aab`.
3. **Testers** tab: create an email list that contains the same accounts as in step 2 and share the opt-in link.
4. Each tester opens the opt-in link on the phone and installs the game **from Play**. Wait a few minutes (sometimes
   an hour) after the first upload.

## 4. How to test a purchase

1. Install the internal-testing build from the Play link, signed in with a license-tester account.
2. Title screen: tap **UNLOCK FULL GAME**. The button should show the price from Play (for example "UNLOCK $3.99").
3. Tap it, confirm in the Play sheet. The test card says "Test card, always approves".
4. You should hear the purchase sound, feel a short vibration, see "FULL GAME UNLOCKED!", and the locks (Hard/Expert
   CPUs, themes, long matches, all weapons, more than 4 players) disappear at once.
5. Close the game completely and open it without internet (airplane mode): it should still be unlocked (the answer is
   cached on the phone and re-checked whenever the game is online).
6. Test **Restore purchase** (Settings, or the Unlock screen) on a second phone with the same account, or after
   clearing the game's data.
7. Test a pending purchase: in License testing you can choose a test card that is slow or declined ("Slow test card,
   approves after a few minutes"). The game shows "Purchase pending" and must stay locked until Play confirms.

### Testing both modes without Play (debug builds only)

Before the Play listing exists, use a debug build (`tools/build_android_debug.sh`):

1. Settings, tap the **version number five times** to open the diagnostics screen.
2. Press **Debug: full version OFF/ON**. The game flips between free and full immediately. This button does not exist in
   release builds, and the override is ignored there.

On a PC (running the project in the editor) a purchase "succeeds" after about half a second without Google; in a release
build with no store the button says "Store unavailable".

## 5. Google Play Pass

Play Pass is a subscription that Google offers players; **you apply, and Google decides** whether to accept the game
(see `PLAN.md` section 4). Nothing in the code depends on it:

- Play reports one-time products of a Play Pass title as already owned for subscribers. The game asks Play what is
  owned at every start and every time it comes back to the foreground, so a subscriber is unlocked automatically and
  the Unlock screen never shows for them.
- If someone leaves Play Pass, the next check no longer reports the purchase and the game goes back to free (their saved
  match stays on the phone; the title screen explains that it needs the full game and offers the unlock).
- To enrol: Play Console, **Monetize with Play**, **Play Pass** (the entry appears only for eligible developers), then
  follow the application. The game already meets the usual rules: no ads and nothing extra to pay for inside the game.
  Being accepted is not guaranteed, and the game works the same without it.

## What happens in odd situations

| Situation | What the player sees |
|---|---|
| Play Store missing or too old | "Store unavailable"; the game stays free and playable |
| No internet | "Can't reach the store"; a cached unlock keeps working |
| Player closes the Play sheet | "Purchase cancelled. You were not charged." |
| Payment is pending (cash, bank, parental approval) | "Purchase pending"; unlocks when Play confirms (at the next start or return to the game) |
| Purchase succeeded but the game was closed before it noticed | Unlocked at the next start (the game acknowledges the purchase then; Play refunds unacknowledged purchases after 3 days) |
| Refund | The next check finds nothing owned and the game goes back to free |
| A saved match made with the full game on a phone that is free now | The title explains "This match uses full-game features" and offers the unlock; the save is kept |

## Troubleshooting

- **"Store unavailable" on a phone with the Play build installed:** the product `full_unlock` is not **Active**, the
  app was not installed from the testing track, or the tester account is not in both lists.
- **The price never appears:** the same causes, or Play's cache; wait a few minutes and reopen the Unlock screen.
- **Buying works but nothing unlocks:** this should not happen. Open the diagnostics screen (version number five times)
  and send a screenshot: it lists "full game", which store is used (`android` or `fake`) and the debug override.
