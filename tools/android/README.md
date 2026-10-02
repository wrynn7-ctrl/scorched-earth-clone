# tools/android

`debug.keystore` is a **public, debug-only** signing key (alias `androiddebugkey`, store and key password `android`,
`CN=Android Debug`). It is committed on purpose so every test build is signed with the same key, which lets new test
builds install over old ones without uninstalling. **Never use it for a release or a Play Store upload.** The release key
is a separate secret and lives only in GitHub Actions secrets, never in this repo.
