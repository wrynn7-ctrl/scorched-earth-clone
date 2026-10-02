#!/usr/bin/env bash
# Installs Godot 4.7.2 (Linux editor) from this repo's `tools-godot-4.7.2` release.
# Idempotent. Prints the binary path on stdout (all other messages go to stderr).
# Honours GODOT_BIN: if set, it is validated and printed instead (CI uses this).
set -euo pipefail

VERSION="4.7.2"
INSTALL_DIR="${HOME}/.local/godot"
BIN="${INSTALL_DIR}/Godot_v${VERSION}-stable_linux.x86_64"
URL="https://github.com/wrynn7-ctrl/scorched-earth-clone/releases/download/tools-godot-${VERSION}/godot-${VERSION}-linux.x86_64.zip"

if [[ -n "${GODOT_BIN:-}" ]]; then
  if [[ ! -x "${GODOT_BIN}" ]]; then
    echo "error: GODOT_BIN is set but '${GODOT_BIN}' is not an executable file" >&2
    exit 1
  fi
  echo "Using GODOT_BIN override" >&2
  echo "${GODOT_BIN}"
  exit 0
fi

if [[ ! -x "${BIN}" ]]; then
  echo "Godot ${VERSION} not found at ${BIN}; downloading..." >&2
  command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }
  command -v unzip >/dev/null || { echo "error: unzip is required" >&2; exit 1; }
  mkdir -p "${INSTALL_DIR}"
  TMP_ZIP="$(mktemp "${INSTALL_DIR}/download.XXXXXX.zip")"
  trap 'rm -f "${TMP_ZIP}"' EXIT
  curl -fL --retry 3 -o "${TMP_ZIP}" "${URL}" || { echo "error: download failed: ${URL}" >&2; exit 1; }
  unzip -o -q "${TMP_ZIP}" -d "${INSTALL_DIR}"
  chmod +x "${BIN}"
  [[ -x "${BIN}" ]] || { echo "error: ${BIN} missing after unzip" >&2; exit 1; }
else
  echo "Godot ${VERSION} already installed" >&2
fi

echo "${BIN}"
