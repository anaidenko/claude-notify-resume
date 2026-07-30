#!/usr/bin/env bash
# macOS checks for the notification hook.
#
#   ./test/run-macos-tests.sh
#
# Unlike the Linux suite this runs on the host, not in a container — macOS
# cannot be containerised. Which means a real banner would land in your own
# Notification Centre, so `terminal-notifier` and `osascript` are shadowed by
# stubs on PATH that record their arguments instead of delivering anything.
# (`bash -x` alone is not enough: it traces a command *and* still runs it.)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

# Stub directory, prepended to PATH for every dispatch check below.
STUB_BIN="$(mktemp -d)"
STUB_LOG="$STUB_BIN/calls.log"
for tool in terminal-notifier osascript; do
    cat >"$STUB_BIN/$tool" <<STUB
#!/bin/bash
printf '%s' "$tool" >>"$STUB_LOG"
for arg in "\$@"; do printf ' %s' "\$arg" >>"$STUB_LOG"; done
printf '\n' >>"$STUB_LOG"
exit 0
STUB
    chmod +x "$STUB_BIN/$tool"
done
TRANSCRIPT="$(mktemp)"
# One trap for everything: a second `trap ... EXIT` would silently replace this
# one and leak the stub directory.
trap 'rm -rf "$STUB_BIN"; rm -f "$TRANSCRIPT"' EXIT

# Run a dispatch with the stubs in front, and print what got "sent".
capture() {
    : >"$STUB_LOG"
    env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" "$@" >/dev/null 2>&1
    cat "$STUB_LOG"
}

[ "$(uname -s)" = "Darwin" ] || {
    printf 'This suite is macOS-only (this is %s). Use test/run-linux-tests.sh.\n' "$(uname -s)" >&2
    exit 1
}

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

contains() {
    local name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*)
            printf '  ok    %s\n' "$name"
            PASS=$((PASS + 1))
            ;;
        *)
            printf '  FAIL  %s\n        missing: %s\n        in:      %s\n' "$name" "$needle" "$haystack"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

cat >"$TRANSCRIPT" <<'JSONL'
{"type":"ai-title","aiTitle":"First working title","sessionId":"s1"}
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
JSONL

payload() {
    printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$REPO_ROOT"
}

printf '\nParser\n'

FIELDS="$(payload | node "$REPO_ROOT/scripts/notify-parse.js")"
check "session id"         "s1"                            "$(printf '%s\n' "$FIELDS" | sed -n 1p)"
check "last ai-title wins" "Fix the geofence rounding bug" "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

printf '\nDispatch\n'

SENT="$(capture "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "Fix the geofence rounding bug" "s1" "$REPO_ROOT")"
contains "status becomes the title"   "-title Replied"                "$SENT"
contains "chat name becomes the body" "Fix the geofence rounding bug"  "$SENT"

# A title beginning with "[" is swallowed by terminal-notifier, which then
# falls back to its own default of "Terminal" — hence the TEST · marker.
: >"$STUB_LOG"
payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" CLAUDE_NOTIFY_TEST=1 "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
contains "test marker carries no brackets" "TEST · Replied" "$(cat "$STUB_LOG")"

printf '\nRobustness\n'

payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on a normal payload" "0" "$?"

printf 'not json' | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on malformed payload" "0" "$?"

printf '' | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on empty stdin" "0" "$?"

# With terminal-notifier gone the AppleScript fallback must take over, so stub
# only osascript here and leave terminal-notifier genuinely absent. Write the
# stub fresh rather than sed-ing a copy: `sed -i ''` is BSD-only and breaks
# outright when GNU sed is first on PATH.
FALLBACK_BIN="$(mktemp -d)"
FALLBACK_LOG="$FALLBACK_BIN/calls.log"
cat >"$FALLBACK_BIN/osascript" <<STUB
#!/bin/bash
printf 'osascript' >>"$FALLBACK_LOG"
for arg in "\$@"; do printf ' %s' "\$arg" >>"$FALLBACK_LOG"; done
printf '\n' >>"$FALLBACK_LOG"
exit 0
STUB
chmod +x "$FALLBACK_BIN/osascript"
PATH="$FALLBACK_BIN:/usr/bin:/bin" "$REPO_ROOT/scripts/notify-macos.sh" \
    "Replied" 'A title with "quotes"' "s1" "$REPO_ROOT" >/dev/null 2>&1
SENT="$(cat "$FALLBACK_LOG" 2>/dev/null)"
rm -rf "$FALLBACK_BIN"
contains "falls back to AppleScript"      "osascript"     "$SENT"
contains "escapes quotes for AppleScript" '\"quotes\"'    "$SENT"

# A cwd with a space used to be mangled by the quoting layers, leaving the
# click broken. The click now runs open-session.sh, so assert the path survives
# as a single argument. Force the -execute branch by pointing STATE_DIR at a
# location with no bundle, so this holds however the developer configured it.
SPACED_PARENT="$(mktemp -d)"
SPACED_DIR="$SPACED_PARENT/My Test Project"
mkdir -p "$SPACED_DIR"
: >"$STUB_LOG"
env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$SPACED_PARENT/state" \
    "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$SPACED_DIR" >/dev/null 2>&1
SENT="$(cat "$STUB_LOG")"

EXECUTE_ARG="$(printf '%s' "$SENT" | sed -n 's/.*-execute \(.*\)$/\1/p')"
if [ -z "$EXECUTE_ARG" ]; then
    printf '  FAIL  no -execute argument was produced\n        %s\n' "$SENT"
    FAIL=$((FAIL + 1))
else
    # Let the shell re-split it exactly as terminal-notifier will, and check the
    # directory arrives intact rather than split on its space.
    # The command carries a CLAUDE_NOTIFY_HOST=... prefix, so cwd is the last
    # argument rather than a fixed position.
    GOT_CWD="$(eval "set -- $EXECUTE_ARG"; eval "printf '%s' \"\${$#}\"")"
    if [ "$GOT_CWD" = "$SPACED_DIR" ]; then
        printf '  ok    a cwd with spaces survives as one argument\n'
        PASS=$((PASS + 1))
    else
        printf '  FAIL  a cwd with spaces is mangled\n        expected: %s\n        actual:   %s\n' \
            "$SPACED_DIR" "$GOT_CWD"
        FAIL=$((FAIL + 1))
    fi
fi
rm -rf "$SPACED_PARENT"

# An apostrophe is the other character that breaks a quoting layer — the same
# family of bug as the space, and just as silent when it strikes.
QUOTE_PARENT="$(mktemp -d)"
QUOTE_DIR="$QUOTE_PARENT/O'Brien Dir"
mkdir -p "$QUOTE_DIR"
: >"$STUB_LOG"
env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$QUOTE_PARENT/state" \
    "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$QUOTE_DIR" >/dev/null 2>&1
SENT="$(cat "$STUB_LOG")"
EXECUTE_ARG="$(printf '%s' "$SENT" | sed -n 's/.*-execute \(.*\)$/\1/p')"
GOT_CWD="$(eval "set -- $EXECUTE_ARG"; eval "printf '%s' \"\${$#}\"" 2>/dev/null)"
if [ "$GOT_CWD" = "$QUOTE_DIR" ]; then
    printf '  ok    a cwd with an apostrophe survives\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL  a cwd with an apostrophe is mangled\n        expected: %s\n        actual:   %s\n' \
        "$QUOTE_DIR" "$GOT_CWD"
    FAIL=$((FAIL + 1))
fi
rm -rf "$QUOTE_PARENT"

printf '\nMuting\n'

# CLAUDE_NOTIFY_MUTE drops the listed statuses. The list is hand-written, so
# case and stray spaces must not matter — and a partial word must NOT match, or
# muting "Repl" would silently swallow "Replied".
mute_probe() {
    local name="$1" mute="$2" status="$3" want="$4"
    : >"$STUB_LOG"
    payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" \
        CLAUDE_NOTIFY_MUTE="$mute" "$REPO_ROOT/scripts/notify.sh" "$status" >/dev/null 2>&1
    local got
    if [ -s "$STUB_LOG" ]; then got="sent"; else got="muted"; fi
    check "$name" "$want" "$got"
}

mute_probe "exact match is muted"        "Replied"                  "Replied"           "muted"
mute_probe "other statuses still fire"   "Replied"                  "Permission needed" "sent"
mute_probe "case is ignored"             "replied"                  "Replied"           "muted"
mute_probe "spaces around commas"        "Replied, Waiting for you" "Waiting for you"   "muted"
mute_probe "later entry also matches"    "Input needed,Replied"     "Replied"           "muted"
mute_probe "empty list mutes nothing"    ""                         "Replied"           "sent"
mute_probe "partial word does not match" "Repl"                     "Replied"           "sent"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
