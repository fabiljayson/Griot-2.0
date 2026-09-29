#!/usr/bin/env bash
# Builds the Flutter Android release APK, pointing it at the production API —
# the same backend (and therefore the same database) the web app and admin use.
#
# Env:
#   API_BASE_URL   Backend base URL baked into the release build.
#                  Defaults to the Render service from render.yaml.
#
# Requires a release signing key at frontend/android/key.properties. The Gradle
# build refuses to assemble a release without one rather than falling back to
# the Android debug keystore, which is published in the AOSP source tree and so
# cannot authenticate a real release.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
API_BASE_URL="${API_BASE_URL:-https://griot-backend-7ie7.onrender.com}"
KEY_PROPERTIES="$REPO_ROOT/frontend/android/key.properties"

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

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  log_error "Missing release signing config: $KEY_PROPERTIES"
  log_error "Generate an upload key and write key.properties before building a release:"
  log_error "  keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \\"
  log_error "    -keysize 2048 -validity 10000 -alias upload"
  log_error "See frontend/android/app/build.gradle.kts for the expected keys."
  exit 1
fi

log_info "Building Android release (API_BASE_URL=$API_BASE_URL)"
cd "$REPO_ROOT/frontend"
flutter pub get
# RELEASE_BUILD=true is what arms AppConstants.assertCleartextBaseUrlIsSafe().
# Without it the app would ship a cleartext origin silently: Android blocks the
# request at the network layer and iOS blocks it via ATS, so the failure would
# only show up on device as an app that cannot reach its own API.
flutter build apk --release \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  --dart-define=RELEASE_BUILD=true

log_info "APK: $(find build/app/outputs/flutter-apk -name 'app-release.apk' -print -quit)"