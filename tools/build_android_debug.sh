#!/usr/bin/env bash
# Builds a debug-signed Android APK (non-Gradle export with the prebuilt Godot templates).
# Idempotent: every step is skipped when its result is already in place.
#
#   1. Godot 4.7.2 editor            (tools/setup_godot.sh)
#   2. Godot 4.7.2 Android templates (this repo's release `tools-godot-4.7.2`)
#   3. Android SDK: platform-tools + build-tools (+ cmdline-tools, platform), licenses accepted
#   4. Godot editor settings: SDK path, JDK path, committed debug keystore
#   5. godot --headless --export-debug "Android" -> build/craterline-debug.apk, then apksigner verify
#
# Prints the APK path and size on stdout's last lines; progress goes to stderr.
# Env (all optional):
#   GODOT_BIN       use this Godot binary (see setup_godot.sh)
#   ANDROID_HOME    use this SDK if it already has what we need (or is writable); otherwise ~/.local/android-sdk
#   JAVA_HOME       JDK used by Godot/apksigner (17 or newer); default: the `java` on PATH
#   GH_TOKEN / GITHUB_TOKEN  with the `gh` CLI present: download the templates through the GitHub API
#                   (needed if the repo is private); otherwise plain curl is used
set -euo pipefail

# ---- pins ---------------------------------------------------------------------------------------------------------
GODOT_VERSION="4.7.2"
TEMPLATES_DIRNAME="${GODOT_VERSION}.stable"
TEMPLATES_ASSET="godot-${GODOT_VERSION}-android-templates.zip"
TEMPLATES_SHA256="53db48b9230cfe332212c363815df473bc29f12c9bf2190130ad9abd1f95d824"
REPO="wrynn7-ctrl/scorched-earth-clone"
RELEASE_TAG="tools-godot-${GODOT_VERSION}"

BUILD_TOOLS_VERSION="36.1.0"          # matches buildTools in Godot 4.7.2's android_source.zip (config.gradle)
ANDROID_PLATFORM="android-36"         # targetSdk of Godot 4.7.2's templates
CMDLINE_TOOLS_BUILD="13114758"        # cmdline-tools 19.0
CMDLINE_TOOLS_SHA256="7ec965280a073311c339e571cd5de778b9975026cfcbe79f2b1cdcb1e15317ee"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip"

PRESET="Android"
OUT_NAME="craterline-debug.apk"
KEY_ALIAS="androiddebugkey"
KEY_PASS="android"
# -------------------------------------------------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME="${ROOT}/game"
BUILD_DIR="${ROOT}/build"
OUT_APK="${BUILD_DIR}/${OUT_NAME}"
KEYSTORE="${ROOT}/tools/android/debug.keystore"
DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
TEMPLATES_DIR="${DATA_HOME}/godot/export_templates/${TEMPLATES_DIRNAME}"
SETTINGS_FILE="${CONFIG_HOME}/godot/editor_settings-4.7.tres"   # Godot names it editor_settings-<major>.<minor>.tres

log() { echo "build_android_debug: $*" >&2; }
die() { echo "build_android_debug: ERROR: $*" >&2; exit 1; }

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

# ---- 5. Export ----------------------------------------------------------------------------------------------------
mkdir -p "${BUILD_DIR}"
rm -f "${OUT_APK}"
LOG="$(mktemp)"
trap 'rm -f "${LOG}"' EXIT

log "importing project (registers scripts and assets)..."
if ! "${GODOT}" --headless --path "${GAME}" --import >"${LOG}" 2>&1; then
  cat "${LOG}" >&2
  die "project import failed"
fi

log "exporting preset '${PRESET}' -> ${OUT_APK}"
if ! "${GODOT}" --headless --path "${GAME}" --export-debug "${PRESET}" "../build/${OUT_NAME}" >"${LOG}" 2>&1; then
  cat "${LOG}" >&2
  die "godot export failed (see log above)"
fi
# Keep the log readable: drop per-file "ADDING:" lines, progress bars and the JVM proxy banner.
sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' "${LOG}" | grep -v -E '^(ADDING:|\[ *[0-9]+%|Picked up JAVA_TOOL_OPTIONS)' >&2 || true
[[ -s "${OUT_APK}" ]] || die "export produced no APK at ${OUT_APK} (see log above)"

log "verifying signature..."
VERIFY="$("${APKSIGNER}" verify --verbose --print-certs "${OUT_APK}" 2>&1)" || { echo "${VERIFY}" >&2; die "apksigner verify FAILED for ${OUT_APK}"; }
APK_SHA256="$(printf '%s\n' "${VERIFY}" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n1)"
KEY_SHA256="$(keytool -list -v -keystore "${KEYSTORE}" -storepass "${KEY_PASS}" -alias "${KEY_ALIAS}" 2>/dev/null \
  | sed -n 's/^[[:space:]]*SHA256: //p' | head -n1 | tr -d ':' | tr 'A-F' 'a-f')"
[[ -n "${APK_SHA256}" && "${APK_SHA256}" == "${KEY_SHA256}" ]] \
  || die "APK is not signed with the committed debug key (apk=${APK_SHA256:-none} key=${KEY_SHA256:-none})"
log "signature OK (debug key SHA-256 ${APK_SHA256})"

SIZE_BYTES="$(stat -c %s "${OUT_APK}")"
echo "APK: ${OUT_APK}"
echo "Size: ${SIZE_BYTES} bytes ($(( (SIZE_BYTES + 524288) / 1048576 )) MiB)"
