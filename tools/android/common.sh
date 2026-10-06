#!/usr/bin/env bash
# Shared setup for tools/build_android_debug.sh and tools/build_android_release.sh. Source it, do not run it.
# The caller sets TOOL_NAME (used in messages) before sourcing. It sets everything up idempotently:
#   Godot editor, export templates, Android SDK (+ NDK for Gradle), editor settings, committed debug keystore,
#   verified Google Play Billing plugin, imported project. Then it provides `export_android` (see the bottom).
# Exported to the caller: ROOT GAME BUILD_DIR GODOT SDK APKSIGNER KEYSTORE KEY_ALIAS KEY_PASS JAVA_HOME.
# Env (all optional): GODOT_BIN, ANDROID_HOME, JAVA_HOME, GH_TOKEN / GITHUB_TOKEN (see build_android_debug.sh).

: "${TOOL_NAME:?TOOL_NAME must be set before sourcing tools/android/common.sh}"
set -euo pipefail

# ---- pins ---------------------------------------------------------------------------------------------------------
GODOT_VERSION="4.7.2"
TEMPLATES_DIRNAME="${GODOT_VERSION}.stable"
TEMPLATES_ASSET="godot-${GODOT_VERSION}-android-templates.zip"
TEMPLATES_SHA256="53db48b9230cfe332212c363815df473bc29f12c9bf2190130ad9abd1f95d824"
REPO="wrynn7-ctrl/scorched-earth-clone"
RELEASE_TAG="tools-godot-${GODOT_VERSION}"

BILLING_PLUGIN_DIRNAME="GodotGooglePlayBilling"
NDK_VERSION="29.0.14206865"           # ndkVersion in Godot 4.7.2's config.gradle; AGP needs it to strip native libraries
BUILD_TOOLS_VERSION="36.1.0"          # matches buildTools in Godot 4.7.2's android_source.zip (config.gradle)
ANDROID_PLATFORM="android-36"         # targetSdk of Godot 4.7.2's templates
CMDLINE_TOOLS_BUILD="13114758"        # cmdline-tools 19.0
CMDLINE_TOOLS_SHA256="7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip"

KEY_ALIAS="androiddebugkey"
KEY_PASS="android"
# -------------------------------------------------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GAME="${ROOT}/game"
BUILD_DIR="${ROOT}/build"
KEYSTORE="${ROOT}/tools/android/debug.keystore"
DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
TEMPLATES_DIR="${DATA_HOME}/godot/export_templates/${TEMPLATES_DIRNAME}"
SETTINGS_FILE="${CONFIG_HOME}/godot/editor_settings-4.7.tres"   # Godot names it editor_settings-<major>.<minor>.tres

log() { echo "${TOOL_NAME}: $*" >&2; }
die() { echo "${TOOL_NAME}: ERROR: $*" >&2; exit 1; }

for tool in curl unzip sha256sum awk; do
  command -v "${tool}" >/dev/null || die "'${tool}' is required but not installed"
done
[[ -f "${KEYSTORE}" ]] || die "debug keystore missing: ${KEYSTORE}"
[[ -f "${GAME}/export_presets.cfg" ]] || die "missing ${GAME}/export_presets.cfg"

# ---- JDK ----------------------------------------------------------------------------------------------------------
if [[ -z "${JAVA_HOME:-}" ]]; then
  command -v java >/dev/null || die "no JDK found: install Java 17+ or set JAVA_HOME"
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
[[ -x "${JAVA_HOME}/bin/java" ]] || die "JAVA_HOME='${JAVA_HOME}' has no bin/java"
export JAVA_HOME
export PATH="${JAVA_HOME}/bin:${PATH}"
log "JDK: ${JAVA_HOME}"

# ---- 1. Godot editor ----------------------------------------------------------------------------------------------
GODOT="$("${ROOT}/tools/setup_godot.sh")"
log "Godot: ${GODOT} ($("${GODOT}" --version 2>/dev/null | head -n1))"

# ---- 2. Export templates ------------------------------------------------------------------------------------------
templates_ok() {
  [[ "$(cat "${TEMPLATES_DIR}/version.txt" 2>/dev/null || true)" == "${TEMPLATES_DIRNAME}" ]] \
    && [[ -f "${TEMPLATES_DIR}/android_debug.apk" && -f "${TEMPLATES_DIR}/android_release.apk" && -f "${TEMPLATES_DIR}/android_source.zip" ]]
}
if templates_ok; then
  log "export templates already installed: ${TEMPLATES_DIR}"
else
  log "installing export templates ${TEMPLATES_DIRNAME} into ${TEMPLATES_DIR}"
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  ZIP="${TMP}/${TEMPLATES_ASSET}"
  got=0
  if command -v gh >/dev/null && [[ -n "${GH_TOKEN:-${GITHUB_TOKEN:-}}" ]]; then
    if GH_TOKEN="${GH_TOKEN:-${GITHUB_TOKEN}}" gh release download "${RELEASE_TAG}" --repo "${REPO}" \
        --pattern "${TEMPLATES_ASSET}" --dir "${TMP}" >&2 2>&1; then
      got=1
    else
      log "gh release download failed; falling back to curl"
    fi
  fi
  if (( got == 0 )); then
    curl -fL --retry 3 -sS -o "${ZIP}" "https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${TEMPLATES_ASSET}" \
      || die "download failed (if the repo is private, set GH_TOKEN and install gh): ${TEMPLATES_ASSET}"
  fi
  echo "${TEMPLATES_SHA256}  ${ZIP}" | sha256sum -c --quiet - || die "checksum mismatch for ${TEMPLATES_ASSET}"
  mkdir -p "${TEMPLATES_DIR}"
  unzip -o -q "${ZIP}" -d "${TEMPLATES_DIR}"
  templates_ok || die "templates incomplete after unzip (expected version.txt = ${TEMPLATES_DIRNAME}, android_*.apk, android_source.zip)"
  rm -rf "${TMP}"; trap - EXIT
fi

# ---- 3. Android SDK -----------------------------------------------------------------------------------------------
sdk_has_needed() {  # $1 = sdk root
  [[ -x "$1/build-tools/${BUILD_TOOLS_VERSION}/apksigner" && -x "$1/platform-tools/adb" ]]
}
if [[ -n "${ANDROID_HOME:-}" ]] && { sdk_has_needed "${ANDROID_HOME}" || [[ -w "${ANDROID_HOME}" ]]; }; then
  SDK="${ANDROID_HOME}"
elif [[ -n "${ANDROID_HOME:-}" ]]; then
  log "ANDROID_HOME=${ANDROID_HOME} lacks build-tools ${BUILD_TOOLS_VERSION} and is not writable; using ~/.local/android-sdk"
  SDK="${HOME}/.local/android-sdk"
else
  SDK="${HOME}/.local/android-sdk"
fi

if ! sdk_has_needed "${SDK}" || [[ ! -d "${SDK}/platforms/${ANDROID_PLATFORM}" ]]; then
  SDKMANAGER="${SDK}/cmdline-tools/latest/bin/sdkmanager"
  if [[ ! -x "${SDKMANAGER}" ]]; then
    log "installing Android command-line tools ${CMDLINE_TOOLS_BUILD} into ${SDK}"
    mkdir -p "${SDK}/cmdline-tools"
    TMP="$(mktemp -d)"
    trap 'rm -rf "${TMP}"' EXIT
    curl -fL --retry 3 -sS -o "${TMP}/cmdline-tools.zip" "${CMDLINE_TOOLS_URL}" || die "download failed: ${CMDLINE_TOOLS_URL}"
    echo "${CMDLINE_TOOLS_SHA256}  ${TMP}/cmdline-tools.zip" | sha256sum -c --quiet - || die "checksum mismatch for command-line tools"
    unzip -q "${TMP}/cmdline-tools.zip" -d "${TMP}/x"
    rm -rf "${SDK}/cmdline-tools/latest"
    mv "${TMP}/x/cmdline-tools" "${SDK}/cmdline-tools/latest"
    rm -rf "${TMP}"; trap - EXIT
    [[ -x "${SDKMANAGER}" ]] || die "sdkmanager missing after unzip"
  fi
  log "accepting SDK licenses and installing platform-tools, build-tools ${BUILD_TOOLS_VERSION}, ${ANDROID_PLATFORM}"
  # `yes` dies with SIGPIPE when sdkmanager stops reading, so judge success by the installed files, not the pipe status.
  (set +o pipefail; yes 2>/dev/null | "${SDKMANAGER}" --sdk_root="${SDK}" --licenses >/dev/null 2>&1) || true
  (set +o pipefail; yes 2>/dev/null | "${SDKMANAGER}" --sdk_root="${SDK}" \
      "platform-tools" "build-tools;${BUILD_TOOLS_VERSION}" "platforms;${ANDROID_PLATFORM}" >/dev/null) || true
  sdk_has_needed "${SDK}" || die "Android SDK install failed: ${SDK}/build-tools/${BUILD_TOOLS_VERSION}/apksigner or platform-tools/adb missing"
else
  log "Android SDK already complete: ${SDK}"
fi
export ANDROID_HOME="${SDK}"
export ANDROID_SDK_ROOT="${SDK}"
APKSIGNER="${SDK}/build-tools/${BUILD_TOOLS_VERSION}/apksigner"

# ---- 4. Godot editor settings -------------------------------------------------------------------------------------
# Sets `key = value` inside [resource]: replaces an existing line, otherwise inserts one. Other settings are untouched.
set_setting() {  # $1 = key, $2 = value (written as a quoted string)
  local tmp="${SETTINGS_FILE}.tmp.$$"
  if grep -q -F "${1} = " "${SETTINGS_FILE}"; then
    KEY="$1" VAL="$2" awk 'index($0, ENVIRON["KEY"] " = ") == 1 { print ENVIRON["KEY"] " = \"" ENVIRON["VAL"] "\""; next } { print }' \
      "${SETTINGS_FILE}" >"${tmp}"
  else
    KEY="$1" VAL="$2" awk '{ print } /^\[resource\]/ { print ENVIRON["KEY"] " = \"" ENVIRON["VAL"] "\"" }' "${SETTINGS_FILE}" >"${tmp}"
  fi
  mv "${tmp}" "${SETTINGS_FILE}"
}
mkdir -p "$(dirname "${SETTINGS_FILE}")"
if [[ ! -f "${SETTINGS_FILE}" ]]; then
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n' >"${SETTINGS_FILE}"
fi
set_setting "export/android/android_sdk_path" "${SDK}"
set_setting "export/android/java_sdk_path" "${JAVA_HOME}"
set_setting "export/android/debug_keystore" "${KEYSTORE}"
set_setting "export/android/debug_keystore_user" "${KEY_ALIAS}"
set_setting "export/android/debug_keystore_pass" "${KEY_PASS}"
log "editor settings written: ${SETTINGS_FILE}"
# Belt and braces: Godot lets these environment variables override the debug keystore of the preset/editor settings.
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="${KEYSTORE}"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${KEY_ALIAS}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${KEY_PASS}"


# ---- 5. Gradle build template -------------------------------------------------------------------------------------
# Gradle builds compile an Android project that Godot normally unpacks from the editor ("Install Android Build Template").
# game/android/ is generated and git-ignored. Godot's own `--install-android-build-template` flag (used together with an
# export) unpacks android_source.zip into game/android/build and writes game/android/.build_version; we only decide
# whether it is needed. The template must match the engine version exactly, or Godot refuses to export.
TEMPLATE_VERSION_FILE="${GAME}/android/.build_version"
template_installed() {
  [[ -f "${GAME}/android/build/build.gradle" && "$(cat "${TEMPLATE_VERSION_FILE}" 2>/dev/null || true)" == "${TEMPLATES_DIRNAME}" ]]
}
INSTALL_FLAG=()
if template_installed; then
  log "Gradle build template already installed (${TEMPLATES_DIRNAME})"
else
  log "Gradle build template missing or stale: it will be (re)installed from android_source.zip"
  rm -rf "${GAME}/android"
  INSTALL_FLAG=(--install-android-build-template)
fi

# ---- 6. Billing plugin, Craterline plugins + project import -------------------------------------------------------
"${ROOT}/tools/setup_billing_plugin.sh" >&2 || die "Google Play Billing plugin check failed (see above)"
# Push (FCM), Google sign-in, share + deep links: built from android_plugins/ with Gradle, AARs go to game/addons/craterline_android/bin.
"${ROOT}/tools/plugins/build_plugins.sh" >&2 || die "Craterline Android plugins build failed (see above)"

mkdir -p "${BUILD_DIR}"
LOG="$(mktemp)"
CLEANUP_PATHS=("${LOG}")   # callers may append; removed on exit
trap 'rm -rf "${CLEANUP_PATHS[@]}"' EXIT
log "importing project (registers scripts and assets)..."
if ! "${GODOT}" --headless --path "${GAME}" --import >"${LOG}" 2>&1; then
  cat "${LOG}" >&2
  die "project import failed"
fi

# export_android <debug|release> <preset> <file name in build/>
# Runs the Godot export. Gradle downloads from Google Maven and Maven Central now and then answer 429/5xx, so a failed
# export is retried (twice) before giving up; the Gradle cache keeps the retry cheap.
export_android() {
  local mode="$1" preset="$2" out="$3" attempt
  rm -f "${BUILD_DIR}/${out}"
  for attempt in 1 2 3; do
    log "exporting preset '${preset}' (${mode}) -> ${BUILD_DIR}/${out} (attempt ${attempt}/3; the first Gradle build downloads a lot)"
    if "${GODOT}" --headless --path "${GAME}" "${INSTALL_FLAG[@]}" "--export-${mode}" "${preset}" "../build/${out}" >"${LOG}" 2>&1 \
        && [[ -s "${BUILD_DIR}/${out}" ]]; then
      # Keep the log readable: drop per-file "ADDING:" lines, progress bars and the JVM proxy banner.
      sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "${LOG}" | grep -v -E '^(ADDING:|\[ *[0-9]+%|Picked up JAVA_TOOL_OPTIONS)' >&2 || true
      return 0
    fi
    sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "${LOG}" | grep -v -E '^(ADDING:|\[ *[0-9]+%|Picked up JAVA_TOOL_OPTIONS)' | tail -n 60 >&2 || true
    INSTALL_FLAG=()   # the template (if it was needed) is installed after the first attempt
    sleep $(( attempt * 15 ))
  done
  die "godot export failed after 3 attempts (see log above)"
}

# verify_craterline_plugins <dex file> <manifest text file> <archive> <resources entry in the archive>
# Shared by both build scripts: proves the Craterline plugins really are inside the finished package.
#   dex file       all classes*.dex of the package, concatenated (class descriptors are plain text in there)
#   manifest text  the package's AndroidManifest.xml (binary or protobuf) run through `strings`
# FCM expectations follow what the plugin build recorded in plugins.cfg: with google-services.json the Firebase
# classes and the generated Firebase resources must be present; without it NO Firebase class may be (the stub).
verify_craterline_plugins() {
  local dex="$1" manifest="$2" archive="$3" res_entry="$4" cls fcm
  fcm="$(sed -n 's/^fcm=//p' "${GAME}/addons/craterline_android/bin/plugins.cfg" | head -n1)"
  [[ "${fcm}" == "true" || "${fcm}" == "false" ]] || die "game/addons/craterline_android/bin/plugins.cfg is missing or broken (run tools/plugins/build_plugins.sh)"
  for cls in com/wrynn7/craterline/plugin/push/CraterlinePush com/wrynn7/craterline/plugin/signin/CraterlineGoogleSignIn \
             com/wrynn7/craterline/plugin/share/CraterlineShare \
             androidx/credentials/CredentialManager com/google/android/libraries/identity/googleid/GoogleIdTokenCredential; do
    grep -a -q "L${cls};" "${dex}" || die "class ${cls} is missing from the package"
  done
  for cls in CraterlinePush CraterlineGoogleSignIn CraterlineShare; do
    grep -a -q "org.godotengine.plugin.v2.${cls}" "${manifest}" || die "plugin meta-data for ${cls} is missing from the manifest"
  done
  # The craterline://join/CODE link: an exported alias with a VIEW filter for scheme craterline, host join.
  grep -a -q 'CraterlineDeepLink' "${manifest}" || die "deep-link activity-alias is missing from the manifest"
  # (protobuf strings can have one stray printable byte after them, so match the start of the line only)
  grep -a -q '^craterline' "${manifest}" && grep -a -q '^join' "${manifest}" || die "craterline://join intent filter is missing from the manifest"
  if [[ "${fcm}" == "true" ]]; then
    grep -a -q 'Lcom/google/firebase/messaging/FirebaseMessaging;' "${dex}" || die "Firebase Messaging classes are missing (push was built with google-services.json)"
    grep -a -q 'Lcom/wrynn7/craterline/plugin/push/CraterlinePushService;' "${dex}" || die "CraterlinePushService is missing"
    # (no `grep -q` after `unzip -p`: grep would exit early and pipefail would report unzip's SIGPIPE as a failure)
    unzip -p "${archive}" "${res_entry}" | grep -a 'google_app_id' >/dev/null || die "generated Firebase resources (google_app_id) are missing"
    log "Craterline plugins present: push (Firebase Messaging BUILT IN), Google sign-in, share + deep links"
  else
    # (firebase-encoders and FirebaseException ride along with Play services for sign-in; FirebaseApp and Messaging must not.)
    ! grep -a -q -E 'Lcom/google/firebase/(FirebaseApp|messaging/FirebaseMessaging);' "${dex}" || die "Firebase Messaging classes found although the push plugin was built as a stub"
    log "Craterline plugins present: push (stub, no Firebase code), Google sign-in, share + deep links"
  fi
}
