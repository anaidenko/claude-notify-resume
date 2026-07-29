#!/usr/bin/env bash
# Linux-path checks for notify.sh.
#
# This runs INSIDE the container built by test/Dockerfile — it is the suite
# itself, not the entry point. Run test/run-linux-tests.sh on your own machine;
# invoking this directly on macOS fails, since there is no notify-send.
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        printf '  ok    %s\n' "$name"
        PASS=$((PASS + 1))
    else
        printf '  FAIL  %s\n        expected: %s\n        actual:   %s\n' "$name" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

# A transcript whose ai-title is superseded — the last record must win.
TRANSCRIPT=/tmp/transcript.jsonl
cat >"$TRANSCRIPT" <<'JSONL'
{"type":"user","message":"hello"}
{"type":"ai-title","aiTitle":"First working title","sessionId":"s1"}
{"type":"assistant","message":"hi"}
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
JSONL

payload() {
    printf '{"session_id":"s1","transcript_path":"%s","cwd":"/work/my-project"}' "$1"
}

printf '\nParser\n'

FIELDS="$(payload "$TRANSCRIPT" | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "session id"           "s1"                             "$(printf '%s\n' "$FIELDS" | sed -n 1p)"
check "cwd"                  "/work/my-project"               "$(printf '%s\n' "$FIELDS" | sed -n 3p)"
check "last ai-title wins"   "Fix the geofence rounding bug"  "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

FIELDS="$(payload /nonexistent.jsonl | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "missing transcript → empty title" "" "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

FIELDS="$(printf 'not json' | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "malformed payload → placeholders" "-" "$(printf '%s\n' "$FIELDS" | sed -n 1p)"

printf '\nDispatch\n'

# notify-send writes to a D-Bus daemon that no container has, so it fails —
# which is exactly the path that must not take the session down with it.
payload "$TRANSCRIPT" | "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 with a working notify-send" "0" "$?"

printf 'not json' | "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on malformed payload" "0" "$?"

printf '' | "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on empty stdin" "0" "$?"

# The one failure mode a user is most likely to hit: libnotify not installed.
PATH_SAVE="$PATH"
export PATH=/usr/bin:/bin
NOTIFY_SEND="$(command -v notify-send)"
mv "$NOTIFY_SEND" "${NOTIFY_SEND}.bak"
payload "$TRANSCRIPT" | "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 when notify-send is absent" "0" "$?"
mv "${NOTIFY_SEND}.bak" "$NOTIFY_SEND"
export PATH="$PATH_SAVE"

# The title is what a Linux user actually sees, so assert the arguments rather
# than trusting that the script got there.
# Trace notify-linux.sh directly: notify.sh only dispatches to it, so the
# notify-send invocation never appears in the parent's trace.
ARGS="$(bash -x "$PLUGIN_ROOT/scripts/notify-linux.sh" "Replied" "Fix the geofence rounding bug" 2>&1 | grep -oE "notify-send .*" | head -1)"
case "$ARGS" in
    *"--app-name=Claude Code"*"Replied"*"Fix the geofence rounding bug"*)
        printf '  ok    notify-send receives status + chat name\n'
        PASS=$((PASS + 1))
        ;;
    *)
        printf '  FAIL  notify-send arguments\n        actual: %s\n' "$ARGS"
        FAIL=$((FAIL + 1))
        ;;
esac

# A wrong icon path fails silently — the banner still shows, just plain — so
# assert the flag explicitly rather than trusting the earlier check's success.
case "$ARGS" in
    *"--icon $PLUGIN_ROOT/assets/claude-logo.png"*)
        printf '  ok    notify-send receives the icon path\n'
        PASS=$((PASS + 1))
        ;;
    *)
        printf '  FAIL  icon path missing or wrong\n        expected: --icon %s/assets/claude-logo.png\n        actual:   %s\n' \
            "$PLUGIN_ROOT" "$ARGS"
        FAIL=$((FAIL + 1))
        ;;
esac

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
