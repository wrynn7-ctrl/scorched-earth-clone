#!/usr/bin/env bash
# Google Play Billing plugin for Godot: verify the vendored copy, or rebuild it from the pinned upstream commit.
#
#   tools/setup_billing_plugin.sh             verify game/addons/GodotGooglePlayBilling against tools/billing/SHA256SUMS
#   tools/setup_billing_plugin.sh --rebuild   clone the pinned commit, build the AARs with Gradle, copy them into
#                                             game/addons/GodotGooglePlayBilling, then verify against the pins
#   tools/setup_billing_plugin.sh --zip DIR   (after a verify/rebuild) also write DIR/godot-google-play-billing-<ver>.zip
#                                             and DIR/SHA256SUMS.txt; used by .github/workflows/mirror-plugins.yml
#
# Why vendored: the AARs are tiny (about 40 KB together) and the upstream project publishes no checksums, so the repo
# holds the exact files and their SHA-256 pins. The Play Billing *library* itself (billing-ktx) is a Maven dependency that
# Gradle downloads during the Android build.
# Exit codes: 0 ok, 1 error, 3 rebuilt fine but the hashes differ from the pins (review, then update the pins).
# Env: JAVA_HOME (JDK 17+), ANDROID_HOME (SDK with platforms;android-36; the build-tools are fetched by AGP if missing).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDON_PARENT="${ROOT}/game/addons"
ADDON="${ADDON_PARENT}/GodotGooglePlayBilling"
PINS="${ROOT}/tools/billing/SHA256SUMS"

log() { echo "setup_billing_plugin: $*" >&2; }
die() { echo "setup_billing_plugin: ERROR: $*" >&2; exit 1; }

REBUILD=0
ZIP_DIR=""
while (( $# > 0 )); do
  case "$1" in
    --rebuild) REBUILD=1; shift ;;
    --zip) (( $# >= 2 )) || die "--zip needs a directory"; ZIP_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

# shellcheck source=billing/pin.env
source "${ROOT}/tools/billing/pin.env"
[[ -n "${BILLING_PLUGIN_VERSION:-}" && -n "${BILLING_PLUGIN_COMMIT:-}" && -n "${BILLING_PLUGIN_REPO:-}" ]] || die "tools/billing/pin.env is incomplete"
[[ -f "${PINS}" ]] || die "missing ${PINS}"

verify() {
  (cd "${ADDON_PARENT}" && sha256sum -c --quiet "${PINS}" >/dev/null 2>&1)
}

if (( REBUILD == 1 )); then
  for tool in git unzip; do command -v "${tool}" >/dev/null || die "'${tool}' is required"; done
  if [[ -z "${JAVA_HOME:-}" ]]; then
    command -v java >/dev/null || die "no JDK found: install Java 17+ or set JAVA_HOME"
    JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
  fi
  export JAVA_HOME PATH="${JAVA_HOME}/bin:${PATH}"
  [[ -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/platforms/android-36" ]] \
    || die "ANDROID_HOME must point to an Android SDK that has platforms/android-36 (tools/build_android_debug.sh installs one)"
  export ANDROID_SDK_ROOT="${ANDROID_HOME}"

  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  log "cloning ${BILLING_PLUGIN_REPO} at ${BILLING_PLUGIN_COMMIT}"
  git clone --quiet "${BILLING_PLUGIN_REPO}" "${TMP}/src" || die "git clone failed"
  git -C "${TMP}/src" checkout --quiet "${BILLING_PLUGIN_COMMIT}" || die "pinned commit not found upstream"
  [[ "$(git -C "${TMP}/src" rev-parse HEAD)" == "${BILLING_PLUGIN_COMMIT}" ]] || die "checked-out commit differs from the pin"

  # Maven Central sometimes answers 429 (rate limit) in bursts; Gradle has no retry for that, so retry the whole build.
  built=0
  for attempt in 1 2 3 4; do
    log "gradle build, attempt ${attempt}/4"
    if (cd "${TMP}/src" && ./gradlew --no-daemon --console=plain -q assemble >"${TMP}/gradle.log" 2>&1); then built=1; break; fi
    tail -n 15 "${TMP}/gradle.log" >&2
    sleep $(( attempt * 20 ))
  done
  (( built == 1 )) || die "gradle build of the plugin failed"

  SRC_ADDON="${TMP}/src/addons/GodotGooglePlayBilling"
  for f in bin/debug/GodotGooglePlayBilling-debug.aar bin/release/GodotGooglePlayBilling-release.aar plugin.cfg export_plugin.gd BillingClient.gd LICENSE; do
    [[ -f "${SRC_ADDON}/${f}" ]] || die "build did not produce ${f}"
  done
  rm -rf "${ADDON}"
  mkdir -p "${ADDON_PARENT}"
  cp -r "${SRC_ADDON}" "${ADDON}"
  log "rebuilt into ${ADDON}"
  rm -rf "${TMP}"; trap - EXIT
fi

status=0
if verify; then
  log "OK: GodotGooglePlayBilling ${BILLING_PLUGIN_VERSION} matches ${PINS#"${ROOT}"/}"
else
  echo "setup_billing_plugin: files in ${ADDON} do not match ${PINS}:" >&2
  (cd "${ADDON_PARENT}" && sha256sum -c "${PINS}" 2>&1 | grep -v ': OK$' >&2) || true
  if (( REBUILD == 1 )); then
    status=3
    log "rebuilt files differ from the pins (different toolchain?). Review them, then update tools/billing/SHA256SUMS."
  else
    die "restore the vendored plugin with: git checkout -- game/addons/GodotGooglePlayBilling, or rebuild it: tools/setup_billing_plugin.sh --rebuild"
  fi
fi

if [[ -n "${ZIP_DIR}" ]]; then
  command -v zip >/dev/null || die "'zip' is required for --zip"
  mkdir -p "${ZIP_DIR}"
  ZIP_ABS="$(cd "${ZIP_DIR}" && pwd)/godot-google-play-billing-${BILLING_PLUGIN_VERSION}.zip"
  rm -f "${ZIP_ABS}"
  (cd "${ADDON_PARENT}" && zip -q -r -X "${ZIP_ABS}" GodotGooglePlayBilling)
  (cd "${ZIP_DIR}" && sha256sum "$(basename "${ZIP_ABS}")" > SHA256SUMS.txt && \
    (cd "${ADDON_PARENT}" && sha256sum GodotGooglePlayBilling/bin/*/*.aar) | sed 's#GodotGooglePlayBilling/##' >> SHA256SUMS.txt)
  log "wrote ${ZIP_ABS}"
fi
exit "${status}"
