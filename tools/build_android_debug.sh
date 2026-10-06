#!/usr/bin/env bash
# Builds a debug-signed Android APK with a Gradle export (Gradle is needed for the Google Play Billing plugin).
# Idempotent: every step is skipped when its result is already in place. Shared setup lives in tools/android/common.sh:
#
#   1. Godot 4.7.2 editor            (tools/setup_godot.sh)
#   2. Godot 4.7.2 Android templates (this repo's release `tools-godot-4.7.2`), including android_source.zip
#   3. Android SDK: platform-tools + build-tools (+ cmdline-tools, platform), licenses accepted
#   4. Godot editor settings: SDK path, JDK path, committed debug keystore
#   5. Gradle build template in game/android (generated, git-ignored), billing plugin checked against its pins,
#      Craterline Android plugins (android_plugins/: push, Google sign-in, share) built into game/addons/craterline_android/bin
#   6. godot --headless --export-debug "Android" -> build/craterline-debug.apk, then apksigner verify
#
# Prints the APK path and size on stdout's last lines; progress goes to stderr. The first run downloads Gradle, the
# Android Gradle Plugin and the Play Billing library (a few hundred MB, cached in ~/.gradle); later runs take about a minute.
# Env (all optional):
#   GODOT_BIN       use this Godot binary (see setup_godot.sh)
#   ANDROID_HOME    use this SDK if it already has what we need (or is writable); otherwise ~/.local/android-sdk
#   JAVA_HOME       JDK used by Godot/Gradle/apksigner (17 or newer); default: the `java` on PATH
#   GH_TOKEN / GITHUB_TOKEN  with the `gh` CLI present: download the templates through the GitHub API
#                   (needed if the repo is private); otherwise plain curl is used
set -euo pipefail

TOOL_NAME="build_android_debug"
PRESET="Android"
OUT_NAME="craterline-debug.apk"

# shellcheck source=android/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/android/common.sh"
OUT_APK="${BUILD_DIR}/${OUT_NAME}"

export_android debug "${PRESET}" "${OUT_NAME}"

log "verifying signature..."
VERIFY="$("${APKSIGNER}" verify --verbose --print-certs "${OUT_APK}" 2>&1)" || { echo "${VERIFY}" >&2; die "apksigner verify FAILED for ${OUT_APK}"; }
APK_SHA256="$(printf '%s\n' "${VERIFY}" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n1)"
KEY_SHA256="$(keytool -list -v -keystore "${KEYSTORE}" -storepass "${KEY_PASS}" -alias "${KEY_ALIAS}" 2>/dev/null \
  | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f')"
[[ -n "${APK_SHA256}" && "${APK_SHA256}" == "${KEY_SHA256}" ]] \
  || die "APK is not signed with the committed debug key (apk=${APK_SHA256:-none} key=${KEY_SHA256:-none})"
log "signature OK (debug key SHA-256 ${APK_SHA256})"

# The whole point of the Gradle build: the billing plugin and the Play Billing library must be inside the APK.
# Classes live in dex files (not visible as zip entries), so look for their descriptors there.
DEX_TMP="$(mktemp)"
CLEANUP_PATHS+=("${DEX_TMP}")
for dex in $(unzip -l "${OUT_APK}" | grep -o -E 'classes[0-9]*\.dex'); do unzip -p "${OUT_APK}" "${dex}" >>"${DEX_TMP}"; done
grep -a -q 'Lorg/godotengine/plugin/googleplaybilling/GodotGooglePlayBilling;' "${DEX_TMP}" || die "billing plugin classes are missing from the APK"
grep -a -q 'Lcom/android/billingclient/api/BillingClient;' "${DEX_TMP}" || die "Play Billing library classes are missing from the APK"
unzip -p "${OUT_APK}" AndroidManifest.xml | strings -e l | grep -q 'org.godotengine.plugin.v2.GodotGooglePlayBilling' \
  || die "billing plugin meta-data is missing from the APK manifest"
log "billing plugin and Play Billing library present in the APK"
unzip -l "${OUT_APK}" | grep -i billing | sed 's/^/  /' >&2 || true

# Craterline's own plugins (push, Google sign-in, share + deep links), see android_plugins/ and docs/FIREBASE_SETUP.md.
MANIFEST_TMP="$(mktemp)"
CLEANUP_PATHS+=("${MANIFEST_TMP}")
unzip -p "${OUT_APK}" AndroidManifest.xml | { strings -e l; strings; } >"${MANIFEST_TMP}"
verify_craterline_plugins "${DEX_TMP}" "${MANIFEST_TMP}" "${OUT_APK}" resources.arsc

SIZE_BYTES="$(stat -c %s "${OUT_APK}")"
echo "APK: ${OUT_APK}"
echo "Size: ${SIZE_BYTES} bytes ($(( (SIZE_BYTES + 524288) / 1048576 )) MiB)"
