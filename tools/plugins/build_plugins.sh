#!/usr/bin/env bash
# Builds Craterline's Android plugins (android_plugins/: push, Google sign-in, share + deep links) with Gradle and installs
# the AARs into game/addons/craterline_android/bin (generated, git-ignored). Called by tools/android/common.sh, so both
# tools/build_android_debug.sh and tools/build_android_release.sh always ship fresh plugins.
#
#   tools/plugins/build_plugins.sh            build if the sources, pins or google-services.json changed
#   tools/plugins/build_plugins.sh --force    build even if nothing changed
#
# Push (Firebase Cloud Messaging) is built in ONLY when android_plugins/google-services.json exists (CI writes it from the
# GitHub secret GOOGLE_SERVICES_JSON; CRATERLINE_GOOGLE_SERVICES_JSON=/path overrides the location). Without it the push
# AAR is a stub that reports "unavailable" and the app contains no Firebase code at all. docs/FIREBASE_SETUP.md.
#
# Versions: tools/plugins/pin.env (Kotlin, Android Gradle Plugin, Godot library, Firebase BOM, Credential Manager, googleid)
# and the Gradle wrapper (Gradle version + SHA-256 in android_plugins/gradle/wrapper/gradle-wrapper.properties).
# Env: JAVA_HOME (JDK 17+), ANDROID_HOME (SDK with platforms;android-36; tools/android/common.sh provides both).
# Maven Central/Google Maven now and then answer 429; the Gradle run is retried (4 attempts).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="${ROOT}/android_plugins"
ADDON="${ROOT}/game/addons/craterline_android"
BIN="${ADDON}/bin"
PIN="${ROOT}/tools/plugins/pin.env"
PRESETS="${ROOT}/game/export_presets.cfg"

log() { echo "build_plugins: $*" >&2; }
die() { echo "build_plugins: ERROR: $*" >&2; exit 1; }

FORCE=0
while (( $# > 0 )); do
  case "$1" in
    --force) FORCE=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

for tool in unzip sha256sum awk find sort; do
  command -v "${tool}" >/dev/null || die "'${tool}' is required but not installed"
done
[[ -f "${PIN}" && -x "${SRC}/gradlew" && -f "${PRESETS}" && -d "${ADDON}" ]] \
  || die "repository layout is incomplete (need ${PIN}, ${SRC}/gradlew, ${PRESETS}, ${ADDON})"

# shellcheck source=pin.env
source "${PIN}"
for v in ANDROID_PLUGINS_VERSION FIREBASE_BOM_VERSION FIREBASE_MESSAGING_VERSION CREDENTIALS_VERSION GOOGLEID_VERSION; do
  [[ -n "${!v:-}" ]] || die "${v} is missing in ${PIN}"
done

if [[ -z "${JAVA_HOME:-}" ]]; then
  command -v java >/dev/null || die "no JDK found: install Java 17+ or set JAVA_HOME"
  JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
fi
[[ -x "${JAVA_HOME}/bin/java" ]] || die "JAVA_HOME='${JAVA_HOME}' has no bin/java"
export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
[[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/platforms/android-36" ]] \
  || die "ANDROID_HOME must point to an Android SDK with platforms/android-36 (tools/build_android_debug.sh installs one)"
export ANDROID_SDK_ROOT="${ANDROID_HOME}"

# The Android package id comes from the export preset, so google-services.json is checked against the real one.
APP_PACKAGE="$(awk -F'"' '/^package\/unique_name=/ { print $2; exit }' "${PRESETS}")"
[[ -n "${APP_PACKAGE}" ]] || die "package/unique_name not found in ${PRESETS}"

GS_FILE="${SRC}/google-services.json"
if [[ -n "${CRATERLINE_GOOGLE_SERVICES_JSON:-}" ]]; then GS_FILE="${CRATERLINE_GOOGLE_SERVICES_JSON}"; fi
if [[ -f "${GS_FILE}" ]]; then
  FCM=true
  log "push: google-services.json found -> Firebase Cloud Messaging is BUILT IN (package ${APP_PACKAGE})"
else
  FCM=false
  log "push: no google-services.json -> push plugin is a stub (available = false). That is fine for tests and dev builds."
fi

# ---- is the output current? -----------------------------------------------------------------------------------------
# Hash of everything the AARs depend on. Secrets are only hashed, never printed or stored (the stamp is one digest).
inputs_digest() {
  {
    (cd "${SRC}" && LC_ALL=C find . -type f -not -path './build/*' -not -path './*/build/*' -not -path './.gradle/*' \
        -not -path './.kotlin/*' -not -name 'google-services.json' -not -name 'local.properties' -print0 \
      | LC_ALL=C sort -z | xargs -0 sha256sum)
    sha256sum "${PIN}"
    echo "package=${APP_PACKAGE} fcm=${FCM}"
    if [[ "${FCM}" == "true" ]]; then sha256sum "${GS_FILE}" | awk '{ print "google-services " $1 }'; fi
  } | sha256sum | awk '{ print $1 }'
}
STAMP="${BIN}/.inputs.sha256"
WANT="$(inputs_digest)"
AARS=(CraterlinePush CraterlineGoogleSignIn CraterlineShare)
current() {
  [[ "$(cat "${STAMP}" 2>/dev/null || true)" == "${WANT}" && -f "${BIN}/plugins.cfg" ]] || return 1
  local n k
  for n in "${AARS[@]}"; do for k in debug release; do [[ -s "${BIN}/${k}/${n}-${k}.aar" ]] || return 1; done; done
}
if (( FORCE == 0 )) && current; then
  log "plugins are up to date (${BIN})"
  exit 0
fi

# ---- Gradle ---------------------------------------------------------------------------------------------------------
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "${LOG_DIR}"' EXIT
export CRATERLINE_GOOGLE_SERVICES_JSON="${GS_FILE}"
built=0
for attempt in 1 2 3 4; do
  log "gradle assemble (debug + release), attempt ${attempt}/4"
  if (cd "${SRC}" && ./gradlew --no-daemon --console=plain -q "-Pcraterline.appPackage=${APP_PACKAGE}" \
        assembleDebug assembleRelease >"${LOG_DIR}/gradle.log" 2>&1); then
    built=1; break
  fi
  grep -v '^Picked up JAVA_TOOL_OPTIONS' "${LOG_DIR}/gradle.log" | tail -n 25 >&2
  # Only network hiccups are worth retrying; a compile or pin error would fail the same way four times.
  if ! grep -q -E '429|Too Many Requests|Could not (GET|HEAD)|timed out|Connection reset|Read timed out|5[0-9][0-9] from server' "${LOG_DIR}/gradle.log"; then
    die "gradle build of the Android plugins failed (see above)"
  fi
  sleep $(( attempt * 20 ))
done
(( built == 1 )) || die "gradle build of the Android plugins failed 4 times (network trouble? see above)"
grep -v '^Picked up JAVA_TOOL_OPTIONS' "${LOG_DIR}/gradle.log" | sed 's/^/  gradle: /' >&2 || true

# ---- install ---------------------------------------------------------------------------------------------------------
declare -A MODULE=( [CraterlinePush]=push [CraterlineGoogleSignIn]=signin [CraterlineShare]=share )
declare -A CLASS=(
  [CraterlinePush]=com/wrynn7/craterline/plugin/push/CraterlinePush
  [CraterlineGoogleSignIn]=com/wrynn7/craterline/plugin/signin/CraterlineGoogleSignIn
  [CraterlineShare]=com/wrynn7/craterline/plugin/share/CraterlineShare )
[[ -n "${BIN}" && "${BIN}" == "${ROOT}/game/addons/craterline_android/bin" ]] || die "internal error: unexpected output directory"
rm -rf "${BIN}"
mkdir -p "${BIN}/debug" "${BIN}/release"
for name in "${AARS[@]}"; do
  for kind in debug release; do
    aar="${SRC}/${MODULE[${name}]}/build/outputs/aar/${MODULE[${name}]}-${kind}.aar"
    [[ -s "${aar}" ]] || die "gradle did not produce ${aar}"
    # The Godot plugin entry in the AAR manifest and the plugin class itself must be there.
    unzip -p "${aar}" AndroidManifest.xml | grep -a "org.godotengine.plugin.v2.${name}" >/dev/null || die "${aar}: plugin meta-data for ${name} missing"
    unzip -p "${aar}" classes.jar >"${LOG_DIR}/classes.jar"
    unzip -l "${LOG_DIR}/classes.jar" | grep " ${CLASS[${name}]}.class\$" >/dev/null || die "${aar}: class ${CLASS[${name}]} missing"
    cp "${aar}" "${BIN}/${kind}/${name}-${kind}.aar"
  done
done

# What the export plugin (game/addons/craterline_android/export_plugin.gd) reads: which features were built in, and the
# exact Maven coordinates to add to the game's Gradle build (Godot cannot use a BOM, so versions are explicit and pinned).
cat >"${BIN}/plugins.cfg" <<CFG
; Generated by tools/plugins/build_plugins.sh. Do not edit.
[build]
version="${ANDROID_PLUGINS_VERSION}"
fcm=${FCM}

[dependencies]
sign_in=[ "androidx.credentials:credentials:${CREDENTIALS_VERSION}", "androidx.credentials:credentials-play-services-auth:${CREDENTIALS_VERSION}", "com.google.android.libraries.identity.googleid:googleid:${GOOGLEID_VERSION}" ]
fcm=[ "com.google.firebase:firebase-messaging:${FIREBASE_MESSAGING_VERSION}" ]
CFG
printf '%s\n' "${WANT}" >"${STAMP}"

log "installed into ${BIN}:"
(cd "${BIN}" && ls -l debug/*.aar release/*.aar | awk '{ printf "  %8d  %s\n", $5, $9 }') >&2
log "done (push: $( [[ ${FCM} == true ]] && echo 'Firebase built in' || echo 'stub, unavailable' ))"
