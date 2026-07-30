#!/usr/bin/env bash
# Checks for the click handler — the flagship path, and the one where two bugs
# hid the longest (an editor-hosted `--resume=<id>` never matched, and a bundle
# path baked in at build time died on the next update).
#
#   ./test/open-session-suite.sh
#
# `osascript`, `code` and `terminal-notifier` are shadowed by stubs that record
# their arguments, so nothing is driven and no banner is delivered. Which app
# actually raises a window is left to manual verification — that part cannot be
# asserted without a real desktop.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

[ "$(uname -s)" = "Darwin" ] || {
    printf 'This suite is macOS-only (this is %s).\n' "$(uname -s)" >&2
    exit 1
}

STUB_BIN="$(mktemp -d)"
STUB_LOG="$STUB_BIN/calls.log"
for tool in osascript code terminal-notifier; do
    cat >"$STUB_BIN/$tool" <<STUB
#!/bin/bash
printf '%s' "$tool" >>"$STUB_LOG"
for arg in "\$@"; do printf ' %s' "\$arg" >>"$STUB_LOG"; done
printf '\n' >>"$STUB_LOG"
# Only osascript is fed a script on stdin (via heredoc), and its arguments alone
# say nothing — so record the body for that one. Reading stdin unconditionally
# would hang the stubs that are called without any.
if [ "$tool" = "osascript" ] && [ ! -t 0 ]; then
    cat >>"$STUB_LOG" 2>/dev/null
fi
exit 0
STUB
    chmod +x "$STUB_BIN/$tool"
done
WORK="$(mktemp -d)"
trap 'rm -rf "$STUB_BIN" "$WORK"' EXIT

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

# Run the handler with stubs in front, and return what it "drove".
run() {
    : >"$STUB_LOG"
    env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$@" >/dev/null 2>&1
    cat "$STUB_LOG"
}

printf '\nRobustness\n'

"$REPO_ROOT/scripts/open-session.sh" >/dev/null 2>&1
check "exit 0 with no arguments" "0" "$?"

"$REPO_ROOT/scripts/open-session.sh" "s1" >/dev/null 2>&1
check "exit 0 with a missing cwd" "0" "$?"

env CLAUDE_NOTIFY_BIN="$STUB_BIN" "$REPO_ROOT/scripts/open-session.sh" "s1" "/nonexistent/folder" >/dev/null 2>&1
check "exit 0 when the folder is gone" "0" "$?"

printf '\nVanished folder\n'

# A click can land long after the banner; the folder may be gone by then. Saying
# so beats opening a terminal on a path that does not exist.
SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "s1" "/nonexistent/folder")"
contains "reports a missing folder" "Session folder is gone" "$SENT"
case "$SENT" in
    *"do script"*)
        printf '  FAIL  a missing folder must not open a terminal\n'
        FAIL=$((FAIL + 1))
        ;;
    *)
        printf '  ok    a missing folder opens no terminal\n'
        PASS=$((PASS + 1))
        ;;
esac

printf '\nChoosing the app\n'

# The detected host picks the app. VS Code is deliberately not followed: it has
# no scriptable terminal, so resuming there would mean pasting by hand.
SENT="$(run CLAUDE_NOTIFY_HOST=vscode "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a VS Code host still gets a terminal" "Terminal" "$SENT"
case "$SENT" in
    *"code $WORK"*)
        printf '  FAIL  a VS Code host must not merely open the folder\n'
        FAIL=$((FAIL + 1))
        ;;
    *)
        printf '  ok    a VS Code host does not just open the folder\n'
        PASS=$((PASS + 1))
        ;;
esac

SENT="$(run CLAUDE_NOTIFY_HOST=iTerm "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "an iTerm host drives iTerm" 'application "iTerm"' "$SENT"

SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "no host falls back to Terminal" 'application "Terminal"' "$SENT"

# An explicit setting beats the detected host.
SENT="$(run CLAUDE_NOTIFY_HOST=iTerm CLAUDE_NOTIFY_TERMINAL=Terminal \
    "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "TERMINAL overrides the host" 'application "Terminal"' "$SENT"

printf '\nResume command\n'

# The command has to survive the quoting layers, and carry this session's id.
SPACED="$WORK/My Project"
mkdir -p "$SPACED"
SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "sess-42" "$SPACED")"
contains "resumes the right session" "claude --resume sess-42" "$SENT"
# printf %q gives `My\ Project`, then the AppleScript layer doubles the
# backslash — so the script that reaches osascript carries `My\\ Project`.
contains "quotes a cwd with spaces" 'My\\ Project' "$SENT"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
