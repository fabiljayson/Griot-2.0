#!/usr/bin/env bash
# Builds the Flutter web app for Vercel, pointing it at the production API.
#
# Env:
#   API_BASE_URL   Backend base URL baked into the release build.
#                  Defaults to the Render service from render.yaml.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
API_BASE_URL="${API_BASE_URL:-https://griot-backend.onrender.com}"

log_info() {
  printf '[%s] INFO: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

cleanup() {
  if [[ -n "${SDK_CACHE:-}" && -d "$SDK_CACHE" ]]; then
    log_info "Removing temporary Flutter SDK at $SDK_CACHE"
    rm -rf -- "$SDK_CACHE"
  fi
}

trap cleanup EXIT

# --- Dependency check ---------------------------------------------------------
command -v git >/dev/null 2>&1 || {
  log_error "Required command 'git' is missing"
  exit 1
}

# --- Flutter SDK (cloned fresh per build; rejected >256 chars inline) --------
SDK_CACHE="$(mktemp -d)"
SDK_DIR="$SDK_CACHE/flutter"
log_info "Cloning Flutter stable into $SDK_DIR"
git clone --depth 1 --branch stable --single-branch \
  https://github.com/flutter/flutter.git "$SDK_DIR"

export PATH="$SDK_DIR/bin:$PATH"
export PUB_CACHE="$SDK_CACHE/pub-cache"

log_info "Configuring Flutter (web enabled)"
flutter config --no-analytics --no-version-check --enable-web

# --- Build --------------------------------------------------------------------
log_info "Building Flutter web (API_BASE_URL=$API_BASE_URL)"
cd "$REPO_ROOT/frontend"
flutter pub get
flutter build web --release --dart-define="API_BASE_URL=$API_BASE_URL"

log_info "Flutter web build complete"