# tools/android

`debug.keystore` is a **public, debug-only** signing key (alias `androiddebugkey`, store and key password `android`,
`CN=Android Debug`). It is committed on purpose so every test build is signed with the same key, which lets new test
builds install over old ones without uninstalling. **Never use it for a release or a Play Store upload.** The release key
is a separate secret and lives only in GitHub Actions secrets, never in this repo.

`common.sh` is the shared setup (Godot, templates, SDK, editor settings, Gradle build template, billing plugin check, build of
the Craterline plugins in `android_plugins/` via `tools/plugins/build_plugins.sh`, and `verify_craterline_plugins` that checks the
finished APK/AAB) that
`tools/build_android_debug.sh` and `tools/build_android_release.sh` source. `fetch_bundletool.sh` downloads Google's
`bundletool` (pinned, checksum-verified) into `~/.cache/craterline` to validate the AAB. See `docs/BUILD.md`.
