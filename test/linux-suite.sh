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

# Shadow notify-send with a stub that records its arguments. In a container
# there is no notification daemon anyway, but this suite also runs directly on
# a Linux contributor's desktop — where a real banner per assertion would be
# obnoxious, and where the arguments are what we actually want to check.
STUB_BIN="$(mktemp -d)"
STUB_LOG="$STUB_BIN/calls.log"
cat >"$STUB_BIN/notify-send" <<STUB
#!/bin/bash
printf 'notify-send' >>"$STUB_LOG"
for arg in "\$@"; do printf ' %s' "\$arg" >>"$STUB_LOG"; done
printf '\n' >>"$STUB_LOG"
exit 0
STUB
chmod +x "$STUB_BIN/notify-send"
trap 'rm -rf "$STUB_BIN"' EXIT

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

# A manual rename writes a custom-title record, after which the transcript
# keeps re-emitting the old ai-title on every turn — the rename must win by
# type, not by position.
RENAMED=/tmp/renamed-transcript.jsonl
cat >"$RENAMED" <<'JSONL'
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
{"type":"custom-title","customTitle":"Geofence: the rename","sessionId":"s1"}
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
JSONL
FIELDS="$(payload "$RENAMED" | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "custom-title beats a later ai-title" "Geofence: the rename" "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

FIELDS="$(payload /nonexistent.jsonl | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "missing transcript → empty title" "" "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

FIELDS="$(printf 'not json' | node "$PLUGIN_ROOT/scripts/notify-parse.js")"
check "malformed payload → placeholders" "-" "$(printf '%s\n' "$FIELDS" | sed -n 1p)"

printf '\nDispatch\n'

payload "$TRANSCRIPT" | env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 with a working notify-send" "0" "$?"

printf 'not json' | env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on malformed payload" "0" "$?"

printf '' | env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on empty stdin" "0" "$?"

# The likeliest real-world failure: libnotify not installed. Shadow notify-send
# with a stub that reports "not found" rather than moving the system binary —
# this suite also runs on a contributor's own machine, where renaming
# /usr/bin/notify-send is not an acceptable side effect. (Emptying PATH instead
# would be too blunt: bash itself would stop resolving, and the script would
# die at its shebang rather than exercise the path under test.)
NO_BIN="$(mktemp -d)"
printf '#!/bin/sh\nexit 127\n' >"$NO_BIN/notify-send"
chmod +x "$NO_BIN/notify-send"
payload "$TRANSCRIPT" | env CLAUDE_NOTIFY_BIN="$NO_BIN" "$PLUGIN_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 when notify-send fails" "0" "$?"
rm -rf "$NO_BIN"

# The title is what a Linux user actually sees, so assert the arguments the
# stub recorded rather than trusting that the script got there.
: >"$STUB_LOG"
env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$PLUGIN_ROOT/scripts/notify-linux.sh" "Replied" "Fix the geofence rounding bug" >/dev/null 2>&1
ARGS="$(cat "$STUB_LOG")"
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
