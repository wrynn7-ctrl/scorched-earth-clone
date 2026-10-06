# android_plugins

Craterline's own Godot Android plugins (Kotlin, one Gradle project, three modules). Overview and how they reach the game:
`docs/BUILD.md` ("The Craterline Android plugins"). Firebase and Google setup: `docs/FIREBASE_SETUP.md`.

| Module | Godot singleton | Source |
|---|---|---|
| `push/` | `CraterlinePush` | `src/main` (plugin, shared), `src/fcm` (real Firebase code, used when `google-services.json` exists), `src/nofcm` (stub) |
| `signin/` | `CraterlineGoogleSignIn` | `src/main` |
| `share/` | `CraterlineShare` (share sheet, `craterline://` links) | `src/main` |

Build: `tools/plugins/build_plugins.sh` (also run by `tools/build_android_debug.sh` and `_release.sh`). Versions:
`tools/plugins/pin.env`. Gradle wrapper (Gradle 8.11.1, checksum pinned): `./gradlew`.

Rules of the road:

- Plugin methods are `snake_case` and marked `@UsedByGodot`; signals are declared with `SignalInfo`. The GDScript fakes
  (`game/platform/*_fake.gd`) must have the same names and signal argument counts. `game/tests/ui/test_platform_plugin_contract.gd`
  reads these files and fails when they drift apart, or when a wrapper calls something the plugin does not have.
- Nothing here may need a secret to compile. `google-services.json` is read at build time only if it exists, is git-ignored
  (`.gitignore` here) and must never be committed. The same goes for keystores and service-account JSON.
- Only the `fcm` source set may reference Firebase classes, so a build without `google-services.json` contains no Firebase code.
