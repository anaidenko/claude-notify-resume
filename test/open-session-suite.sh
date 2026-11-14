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
for tool in osascript code terminal-notifier open; do
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
EXTHOST=""
trap 'rm -rf "$STUB_BIN" "$WORK"; [ -n "$EXTHOST" ] && kill "$EXTHOST" 2>/dev/null' EXIT

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

# The detected host picks the app. A bare "vscode" carries no window, which is
# the case for a CLI in VS Code's integrated terminal. There is no tab to return
# to, and opening the folder alone would not resume the conversation.
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

printf '\nVS Code tab\n'

# A session from the VS Code extension reopens as its own tab in its own
# window. VS Code sends a protocol URL to its last active window unless the URL
# names one with windowId, and the extension opens the session in whichever
# window receives it. In another project's window that means a new, empty
# session (seen live, including a 1-in-3 race when focusing the window first).
# So the host carries the window id plus the pid of that window's extension
# host. A live extension host proves the id still means the same window.
FAKE_HELPER="$WORK/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)"
mkdir -p "$(dirname "$FAKE_HELPER")"
ln -s /bin/bash "$FAKE_HELPER"
# The trailing `true` keeps bash from exec-ing sleep, which would rename the
# process and stop it posing as an extension host.
"$FAKE_HELPER" -c 'sleep 120; true' &
EXTHOST=$!

SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$EXTHOST" "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
check "a live VS Code window gets the session's own tab" \
    "open vscode://anthropic.claude-code/open?session=s1&windowId=7" "$SENT"

# A dead extension host means the window closed or VS Code restarted, and its
# window ids may now name other windows. That is the wrong-window case above,
# so fall back to a terminal rather than guess.
(exit 0) &
DEAD=$!
wait "$DEAD"
SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$DEAD" "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a gone extension host falls back to Terminal" 'application "Terminal"' "$SENT"
case "$SENT" in
    *vscode://*)
        printf '  FAIL  a gone extension host must not send the URL\n'
        FAIL=$((FAIL + 1))
        ;;
    *)
        printf '  ok    a gone extension host sends no URL\n'
        PASS=$((PASS + 1))
        ;;
esac

# A live pid that is not an extension host (a recycled pid) proves nothing.
SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$$" "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a recycled pid falls back to Terminal" 'application "Terminal"' "$SENT"

# TERMINAL forces a terminal, as documented, over a detected editor too.
SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$EXTHOST" CLAUDE_NOTIFY_TERMINAL=iTerm \
    "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "TERMINAL overrides a VS Code tab" 'application "iTerm"' "$SENT"

# The extension silently ignores an id with `/`, `\` or `..`, which would make
# the click a no-op. Such an id never reaches the URL.
SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$EXTHOST" "$REPO_ROOT/scripts/open-session.sh" "../x" "$WORK")"
contains "an odd session id falls back to Terminal" 'application "Terminal"' "$SENT"

# `open` fails when nothing handles vscode:// (VS Code uninstalled since).
# The recording stub is put back afterwards rather than deleted: a later check
# reaching `open` would otherwise run the real one and raise a real window.
mv "$STUB_BIN/open" "$STUB_BIN/open.recording"
cat >"$STUB_BIN/open" <<STUB
#!/bin/bash
printf 'open %s\n' "\$*" >>"$STUB_LOG"
exit 1
STUB
chmod +x "$STUB_BIN/open"
SENT="$(run CLAUDE_NOTIFY_HOST="vscode:7:$EXTHOST" "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a failed open falls back to Terminal" 'application "Terminal"' "$SENT"
mv "$STUB_BIN/open.recording" "$STUB_BIN/open"

kill "$EXTHOST" 2>/dev/null
wait "$EXTHOST" 2>/dev/null
EXTHOST=""

printf '\nResume command\n'

# The command has to survive the quoting layers, and carry this session's id.
SPACED="$WORK/My Project"
mkdir -p "$SPACED"
SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "sess-42" "$SPACED")"
contains "resumes the right session" "claude --resume sess-42" "$SENT"
# printf %q gives `My\ Project`, then the AppleScript layer doubles the
# backslash — so the script that reaches osascript carries `My\\ Project`.
contains "quotes a cwd with spaces" 'My\\ Project' "$SENT"

printf '\nCold start\n'

# Launching a terminal opens its startup window; a `do script` on top of that is
# a second window, so a cold start has to reuse the startup window and a warm
# one must not. The probe decides which — and it once answered from Launch
# Services, which reports "not running" for a visible Terminal whenever the
# caller's environment is stripped the way the click handler's is. That sent
# every warm click down the cold branch, i.e. the empty window this guards
# against. `pgrep` is stubbed here to pin each branch to the intended answer.
pgrep_stub() {
    cat >"$STUB_BIN/pgrep" <<STUB
#!/bin/bash
exit $1
STUB
    chmod +x "$STUB_BIN/pgrep"
}

pgrep_stub 0 # terminal already running -> warm
SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
case "$SENT" in
    *"in front window"*)
        printf '  FAIL  a running Terminal must open its own window\n'
        FAIL=$((FAIL + 1))
        ;;
    *)
        printf '  ok    a running Terminal opens its own window\n'
        PASS=$((PASS + 1))
        ;;
esac

pgrep_stub 1 # terminal not running -> cold, reuse the startup window
SENT="$(run "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a cold Terminal reuses the startup window" "in front window" "$SENT"

pgrep_stub 0
SENT="$(run CLAUDE_NOTIFY_HOST=iTerm "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a running iTerm creates a window" "create window" "$SENT"

pgrep_stub 1
SENT="$(run CLAUDE_NOTIFY_HOST=iTerm "$REPO_ROOT/scripts/open-session.sh" "s1" "$WORK")"
contains "a cold iTerm reuses the startup window" "current session of current window" "$SENT"

rm -f "$STUB_BIN/pgrep"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
