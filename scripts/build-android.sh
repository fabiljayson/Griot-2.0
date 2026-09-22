#!/usr/bin/env bash
# Builds the Flutter Android release APK, pointing it at the production API —
# the same backend (and therefore the same database) the web app and admin use.
#
# Env:
#   API_BASE_URL   Backend base URL baked into the release build.
#                  Defaults to the Render service from render.yaml.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
API_BASE_URL="${API_BASE_URL:-https://griot-backend-7ie7.onrender.com}"

log_info() {
  printf '[%s] INFO: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

command -v flutter >/dev/null 2>&1 || {
  log_error "Required command 'flutter' is missing from PATH"
  exit 1
}

log_info "Building Android release (API_BASE_URL=$API_BASE_URL)"
cd "$REPO_ROOT/frontend"
flutter pub get
flutter build apk --release --dart-define="API_BASE_URL=$API_BASE_URL"

log_info "APK: $(find build/app/outputs/flutter-apk -name 'app-release.apk' -print -quit)"