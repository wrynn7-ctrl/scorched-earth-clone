#!/usr/bin/env bash
# Builds a release-style Android App Bundle (AAB) with a Gradle export, using Godot's release templates.
#
#   *** THE AAB THIS SCRIPT PRODUCES IS SIGNED WITH THE PUBLIC DEBUG KEY. IT IS NOT A GOOGLE PLAY UPLOAD KEY. ***
#   *** Play Console will reject it, and anyone could sign an app that replaces it. Real signing arrives in M8. ***
#
# It proves that the release pipeline works end to end (release templates, R8/resource shrinking, the billing plugin,
# the AAB format) before the real keystore exists. Shared setup lives in tools/android/common.sh.
#
# Output: build/craterline-release.aab. Checks: jarsigner verify + certificate = committed debug key, bundle layout
# (unzip), the billing plugin inside the base module, and, when it can be fetched, `bundletool validate`.
#
# When real signing is added (M8), pass the secrets through the environment, never through files in the repo:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD   (this script currently overrides them with the debug key)
# Env (all optional): GODOT_BIN, ANDROID_HOME, JAVA_HOME, GH_TOKEN / GITHUB_TOKEN, SKIP_BUNDLETOOL=1 (see build_android_debug.sh).
set -euo pipefail

TOOL_NAME="build_android_release"
PRESET="Android Release"
OUT_NAME="craterline-release.aab"

# shellcheck source=android/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/android/common.sh"
OUT_AAB="${BUILD_DIR}/${OUT_NAME}"

banner() {
  {
    echo
    echo "################################################################################"
    echo "#  WARNING: ${OUT_NAME} IS SIGNED WITH THE PUBLIC DEBUG KEY."
    echo "#  It is NOT a Google Play upload key. Do not upload it to Play Console."
    echo "#  The real upload key and Play App Signing are set up in milestone M8."
    echo "################################################################################"
    echo
  } >&2
}
banner

# The release key variables are read by Godot's Gradle export; until M8 they point to the committed debug key.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${KEYSTORE}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KEY_ALIAS}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${KEY_PASS}"

export_android release "${PRESET}" "${OUT_NAME}"

# ---- checks ---------------------------------------------------------------------------------------------------------
LIST="$(unzip -l "${OUT_AAB}")" || die "${OUT_AAB} is not a readable zip"
for entry in BundleConfig.pb base/manifest/AndroidManifest.xml base/dex/classes.dex base/lib/arm64-v8a/libgodot_android.so; do
  grep -q " ${entry}\$" <<<"${LIST}" || die "AAB layout check failed: ${entry} is missing"
done
log "AAB layout OK"

# jarsigner is the tool that signs and verifies bundles (apksigner only handles APKs).
VERIFY="$(jarsigner -verify -verbose -certs "${OUT_AAB}" 2>&1)" || { echo "${VERIFY}" >&2; die "jarsigner could not verify ${OUT_AAB}"; }
grep -q -E '^jar verified' <<<"${VERIFY}" || { echo "${VERIFY}" | tail -n 20 >&2; die "AAB signature did not verify"; }
AAB_SHA256="$(keytool -printcert -jarfile "${OUT_AAB}" 2>/dev/null | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f')"
KEY_SHA256="$(keytool -list -v -keystore "${KEYSTORE}" -storepass "${KEY_PASS}" -alias "${KEY_ALIAS}" 2>/dev/null \
  | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f')"
[[ -n "${AAB_SHA256}" && "${AAB_SHA256}" == "${KEY_SHA256}" ]] \
  || die "AAB is not signed with the committed debug key (aab=${AAB_SHA256:-none} key=${KEY_SHA256:-none})"
log "signature OK (debug key SHA-256 ${AAB_SHA256}); this is expected until M8"

# Billing: the plugin's Android metadata + classes must be in the base module.
BASE_DEX_TMP="$(mktemp -d)"
CLEANUP_PATHS+=("${BASE_DEX_TMP}")
for dex in $(grep -o -E 'base/dex/classes[0-9]*\.dex' <<<"${LIST}"); do unzip -p "${OUT_AAB}" "${dex}" >>"${BASE_DEX_TMP}/all.dex"; done
grep -a -q 'Lorg/godotengine/plugin/googleplaybilling/GodotGooglePlayBilling;' "${BASE_DEX_TMP}/all.dex" \
  || die "billing plugin classes are missing from the AAB"
grep -a -q 'Lcom/android/billingclient/api/BillingClient;' "${BASE_DEX_TMP}/all.dex" \
  || die "Play Billing library classes are missing from the AAB"
log "billing plugin and Play Billing library classes present in the AAB"

if [[ "${SKIP_BUNDLETOOL:-0}" != "1" ]]; then
  if BUNDLETOOL_CP="$("${ROOT}/tools/android/fetch_bundletool.sh")"; then
    log "bundletool validate..."
    BT_LOG="${BASE_DEX_TMP}/bundletool.log"
    if java -cp "${BUNDLETOOL_CP}" com.android.tools.build.bundletool.BundleToolMain validate --bundle="${OUT_AAB}" >"${BT_LOG}" 2>&1; then
      grep -v -E '^[[:space:]]*File:|^Picked up' "${BT_LOG}" >&2   # the full file list is hundreds of lines
    else
      grep -v -E '^[[:space:]]*File:|^Picked up' "${BT_LOG}" >&2
      die "bundletool validate FAILED for ${OUT_AAB}"
    fi
    log "bundletool validate OK"
  else
    log "bundletool not available; skipped (unzip + jarsigner checks passed)"
  fi
fi

banner
SIZE_BYTES="$(stat -c %s "${OUT_AAB}")"
echo "AAB: ${OUT_AAB}"
echo "Size: ${SIZE_BYTES} bytes ($(( (SIZE_BYTES + 524288) / 1048576 )) MiB)"
