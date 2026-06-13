#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC_PATH="$ROOT_DIR/pubspec.yaml"
RELEASE_DIR="$ROOT_DIR/release"
AAB_SOURCE="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
APK_SOURCE="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
AAB_TARGET="$RELEASE_DIR/viddit-app-release.aab"
APK_TARGET="$RELEASE_DIR/viddit-app-release.apk"

log() {
  printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$1"
}

fail() {
  printf '\n[ERROR] %s\n' "$1" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "Required file not found: $path"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
}

read_version_line() {
  grep '^version:' "$PUBSPEC_PATH" | head -n 1
}

bump_version_code() {
  local version_line version_name version_code new_version_code new_version_line
  version_line="$(read_version_line)"
  [[ -n "$version_line" ]] || fail "Could not find version line in pubspec.yaml"

  version_name="${version_line#version: }"
  version_name="${version_name%%+*}"
  version_code="${version_line##*+}"

  [[ "$version_code" =~ ^[0-9]+$ ]] || fail "Current version code is not numeric: $version_code"

  new_version_code="$((version_code + 1))"
  new_version_line="version: ${version_name}+${new_version_code}"

  python3 - "$PUBSPEC_PATH" "$new_version_line" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
new_line = sys.argv[2]
lines = path.read_text().splitlines()

for index, line in enumerate(lines):
    if line.startswith("version: "):
        lines[index] = new_line
        path.write_text("\n".join(lines) + "\n")
        break
else:
    raise SystemExit("version line not found")
PY

  printf '%s|%s|%s\n' "$version_name" "$version_code" "$new_version_code"
}

report_artifact() {
  local path="$1"
  [[ -f "$path" ]] || fail "Artifact missing: $path"
  local size
  size="$(du -h "$path" | awk '{print $1}')"
  printf '  - %s (%s)\n' "$path" "$size"
}

main() {
  require_command flutter
  require_command python3
  require_file "$PUBSPEC_PATH"

  cd "$ROOT_DIR"

  log "Bumping Android version code in pubspec.yaml"
  IFS='|' read -r version_name old_code new_code < <(bump_version_code)
  printf '  Previous: %s+%s\n' "$version_name" "$old_code"
  printf '  New:      %s+%s\n' "$version_name" "$new_code"

  log "Building Android App Bundle (.aab)"
  flutter build appbundle --release

  log "Building Android APK (.apk)"
  flutter build apk --release

  log "Copying artifacts to release/"
  mkdir -p "$RELEASE_DIR"
  cp "$AAB_SOURCE" "$AAB_TARGET"
  cp "$APK_SOURCE" "$APK_TARGET"

  log "Release artifacts ready"
  report_artifact "$AAB_TARGET"
  report_artifact "$APK_TARGET"
}

main "$@"
