#!/usr/bin/env bash
# End-to-end Linux delivery check.
#
# The other Linux suite stubs notify-send and asserts on its arguments, which
# proves the script builds the right command but not that anything is actually
# delivered. This one runs a real D-Bus session and a real notification daemon,
# then reads back what the daemon received over the bus — app name, icon path,
# title and body, as the desktop itself would see them.
#
# Needs dbus-x11, notification-daemon, xvfb and libnotify-bin; run it through
# test/Dockerfile.dbus rather than on a workstation.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*)
            printf '  ok    %s\n' "$name"
            PASS=$((PASS + 1))
            ;;
        *)
            printf '  FAIL  %s\n        missing: %s\n' "$name" "$needle"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

eval "$(dbus-launch --sh-syntax)"
Xvfb :99 >/dev/null 2>&1 &
export DISPLAY=:99
sleep 1
/usr/lib/notification-daemon/notification-daemon >/dev/null 2>&1 &
sleep 2

BUS_LOG="$(mktemp)"
dbus-monitor "interface=org.freedesktop.Notifications" >"$BUS_LOG" 2>&1 &
MONITOR_PID=$!
trap 'kill "$MONITOR_PID" 2>/dev/null; rm -f "$BUS_LOG" "$TRANSCRIPT"' EXIT
sleep 1

TRANSCRIPT="$(mktemp)"
cat >"$TRANSCRIPT" <<'JSONL'
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
JSONL

printf '{"session_id":"s1","transcript_path":"%s","cwd":"/plugin"}' "$TRANSCRIPT" |
    "$PLUGIN_ROOT/scripts/notify.sh" "Replied"
sleep 2

# Everything the daemon received for this call, arguments included.
DELIVERED="$(grep -A8 'member=Notify$' "$BUS_LOG")"

printf '\nDelivery over D-Bus\n'

if [ -z "$DELIVERED" ]; then
    printf '  FAIL  nothing reached the notification daemon\n'
    printf '\n0 passed, 1 failed\n\n'
    exit 1
fi

contains "reaches the daemon"     'member=Notify'                        "$DELIVERED"
contains "app name is set"        '"Claude Code"'                        "$DELIVERED"
contains "icon path is delivered" '"/plugin/assets/claude-logo.png"'     "$DELIVERED"
contains "status is the title"    '"Replied"'                            "$DELIVERED"
contains "chat name is the body"  '"Fix the geofence rounding bug"'      "$DELIVERED"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
