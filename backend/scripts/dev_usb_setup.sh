#!/usr/bin/env bash
#
# One-command local setup for testing the Griot app on a USB-connected phone.
#
#   ./scripts/dev_usb_setup.sh
#
# Starts Django (if it is not already up) on 0.0.0.0:8000 and maps the phone's
# own 127.0.0.1:8000 onto it, so a build compiled with
#
#   flutter build apk --debug --dart-define=API_BASE_URL=http://127.0.0.1:8000
#
# talks to the local SQLite database over the cable. No Wi-Fi and no ufw rule
# is involved: the traffic goes through adbd, not the network stack, so it
# works while the phone is on mobile data or an unvalidated network.
#
# Both steps are idempotent — re-run after unplugging the cable or rebooting
# the phone, which is what tears the tunnel down.
set -euo pipefail

PORT="${PORT:-8000}"
LOG="${LOG:-/tmp/griot_server.log}"
BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- 1. Django dev server ---------------------------------------------------
PY="$BACKEND_DIR/.venv-linux/bin/python"
[ -x "$PY" ] || PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
    echo "error: no python interpreter found" >&2
    exit 1
fi

# config/settings/dev.py scopes ALLOWED_HOSTS (no wildcard), so the LAN
# address has to be handed over via DJANGO_LOCAL_IP. Harmless for the USB
# path, and it is what makes Wi-Fi testing work when the network allows it.
if ss -tln 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    echo "==> Django already listening on :${PORT}"
else
    LAN_IP="$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i + 1); exit}}')"
    [ -n "$LAN_IP" ] || LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [ -n "$LAN_IP" ] || LAN_IP="127.0.0.1"

    cd "$BACKEND_DIR"
    DJANGO_LOCAL_IP="$LAN_IP" setsid "$PY" manage.py runserver "0.0.0.0:${PORT}" \
        </dev/null >"$LOG" 2>&1 &

    for _ in $(seq 20); do
        ss -tln 2>/dev/null | grep -qE ":${PORT}[[:space:]]" && break
        sleep 0.5
    done
    if ss -tln 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
        echo "==> Django started on 0.0.0.0:${PORT} (LAN ${LAN_IP}, log ${LOG})"
    else
        echo "error: Django did not come up — see ${LOG}" >&2
        exit 1
    fi
fi

# --- 2. USB tunnel ----------------------------------------------------------
command -v adb >/dev/null 2>&1 || {
    echo "error: adb not on PATH" >&2
    exit 1
}

SERIAL="$(adb devices \
    | awk '$1 !~ /^List/ && $2 == "device" && $1 !~ /^emulator-/ {print $1; exit}')"
if [ -z "$SERIAL" ]; then
    echo "error: no USB device found — check 'adb devices' and USB debugging" >&2
    exit 1
fi

adb -s "$SERIAL" reverse --remove "tcp:${PORT}" >/dev/null 2>&1 || true
adb -s "$SERIAL" reverse "tcp:${PORT}" "tcp:${PORT}"

echo "==> Tunnel: $(adb -s "$SERIAL" reverse --list | tr '\n' ' ')"
echo "    phone 127.0.0.1:${PORT} -> ${SERIAL} (USB) -> localhost:${PORT}"
echo
echo "Next:"
echo "  cd ../frontend && flutter run -d ${SERIAL} \\"
echo "      --dart-define=API_BASE_URL=http://127.0.0.1:${PORT}"
echo "  tail -f ${LOG}"