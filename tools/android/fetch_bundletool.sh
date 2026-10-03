#!/usr/bin/env bash
# Prints a Java classpath for Google's `bundletool` (used to validate AABs), downloading it on first use.
# bundletool is published on Google Maven (not Maven Central) and needs its dependencies, so Gradle resolves it for us
# into ~/.cache/craterline/bundletool-<version>/ (the all-in-one jar lives on a GitHub release page, which the cloud
# dev container cannot reach). Exit 1 and print nothing on stdout if it cannot be fetched; the caller then skips validation.
# Usage: java -cp "$(tools/android/fetch_bundletool.sh)" com.android.tools.build.bundletool.BundleToolMain validate --bundle=x.aab
set -euo pipefail

BUNDLETOOL_VERSION="1.18.3"
BUNDLETOOL_SHA256="ccad18514fd97db010856b2bbed40f481f8ba9349368c97ae54d72e3567d0171"   # matches Google Maven's .sha256
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${XDG_CACHE_HOME:-${HOME}/.cache}/craterline/bundletool-${BUNDLETOOL_VERSION}"
log() { echo "fetch_bundletool: $*" >&2; }

if ! ls "${DEST}"/bundletool-*.jar >/dev/null 2>&1; then
  GRADLEW="${ROOT}/game/android/build/gradlew"   # any Gradle wrapper will do; the Android build template ships one
  if [[ ! -x "${GRADLEW}" ]]; then log "no Gradle wrapper at ${GRADLEW}; run an Android build first"; exit 1; fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "${TMP}"' EXIT
  echo "rootProject.name = 'bundletool-fetch'" >"${TMP}/settings.gradle"
  cat >"${TMP}/build.gradle" <<GRADLE
configurations { bt }
repositories { google(); mavenCentral() }
dependencies { bt 'com.android.tools.build:bundletool:${BUNDLETOOL_VERSION}' }
tasks.register('fetch', Copy) { from configurations.bt; into '${DEST}' }
GRADLE
  mkdir -p "${DEST}"
  ok=0
  for attempt in 1 2 3; do   # Maven mirrors answer 429 in bursts
    if "${GRADLEW}" -p "${TMP}" --no-daemon --console=plain -q fetch >"${TMP}/log" 2>&1; then ok=1; break; fi
    sleep $(( attempt * 10 ))
  done
  if (( ok == 0 )); then tail -n 15 "${TMP}/log" >&2; rm -rf "${DEST}"; log "could not download bundletool ${BUNDLETOOL_VERSION}"; exit 1; fi
fi
[[ -f "${DEST}/bundletool-${BUNDLETOOL_VERSION}.jar" ]] || { log "bundletool jar missing in ${DEST}"; exit 1; }
echo "${BUNDLETOOL_SHA256}  ${DEST}/bundletool-${BUNDLETOOL_VERSION}.jar" | sha256sum -c --quiet - \
  || { rm -rf "${DEST}"; log "checksum mismatch for bundletool-${BUNDLETOOL_VERSION}.jar (cache removed)"; exit 1; }
printf '%s\n' "${DEST}/*"
