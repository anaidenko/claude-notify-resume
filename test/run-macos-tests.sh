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
# lsregister too: the native path re-registers the icon bundle on a refused post,
# and the real tool would write a test bundle into the user's Launch Services.
for tool in terminal-notifier osascript lsregister; do
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

# A manual rename writes a custom-title record, after which the transcript
# keeps re-emitting the old ai-title on every turn — so the rename must win by
# type, not by position. Lives in STUB_BIN so the existing trap cleans it up.
RENAMED_TRANSCRIPT="$STUB_BIN/renamed.jsonl"
cat >"$RENAMED_TRANSCRIPT" <<'JSONL'
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
{"type":"custom-title","customTitle":"Geofence: the rename","sessionId":"s1"}
{"type":"ai-title","aiTitle":"Fix the geofence rounding bug","sessionId":"s1"}
JSONL
FIELDS="$(printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s"}' "$RENAMED_TRANSCRIPT" "$REPO_ROOT" |
    node "$REPO_ROOT/scripts/notify-parse.js")"
check "custom-title beats a later ai-title" "Geofence: the rename" "$(printf '%s\n' "$FIELDS" | sed -n 4p)"

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
# The state dir matters: the icon app outranks every other sender, and the
# real one in ~/.claude would post a real banner.
PATH="$FALLBACK_BIN:/usr/bin:/bin" CLAUDE_NOTIFY_STATE_DIR="$FALLBACK_BIN/state" \
    "$REPO_ROOT/scripts/notify-macos.sh" \
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

printf '\nNative notifier\n'

# The compiled bundle is the main path, and the one that went silent: after a
# macOS update Launch Services no longer knew the bundle, usernoted refused every
# post, and the binary exited 0 all the same. A fake bundle stands in for it
# here; its exit statuses come from a queue, one per call, so each case scripts
# what macOS answers: 0 posted, 3 client refused, 4 switched off by the user.
NATIVE_STATE="$STUB_BIN/native-state"
NATIVE_APP="$NATIVE_STATE/Claude Code.app"
NATIVE_QUEUE="$STUB_BIN/native-queue"
mkdir -p "$NATIVE_APP/Contents/MacOS" "$NATIVE_APP/Contents/Resources"
cat >"$NATIVE_APP/Contents/MacOS/claude-notify" <<STUB
#!/bin/bash
printf 'claude-notify %s\n' "\$*" >>"$STUB_LOG"
rc="\$(head -1 "$NATIVE_QUEUE")"
tail -n +2 "$NATIVE_QUEUE" >"$NATIVE_QUEUE.next"
mv "$NATIVE_QUEUE.next" "$NATIVE_QUEUE"
exit "\${rc:-0}"
STUB
chmod +x "$NATIVE_APP/Contents/MacOS/claude-notify"

# native_probe <marker content> <exit status>... — prints the call sequence,
# one tool name per call, e.g. "claude-notify,lsregister,claude-notify".
native_probe() {
    local marker="$1"
    shift
    printf '%s' "$marker" >"$NATIVE_APP/Contents/Resources/native-notifier"
    printf '%s\n' "$@" >"$NATIVE_QUEUE"
    : >"$STUB_LOG"
    env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$NATIVE_STATE" \
        "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$REPO_ROOT" >/dev/null 2>&1
    NATIVE_RC=$?
    awk '{ print $1 }' "$STUB_LOG" | paste -sd, -
}

check "accepted post: one native call, nothing else" \
    "claude-notify" "$(native_probe 2 0)"
check "refused client: re-register the bundle, then retry" \
    "claude-notify,lsregister,claude-notify" "$(native_probe 2 3 0)"
contains "re-registers the bundle itself" "lsregister -f $NATIVE_APP" "$(cat "$STUB_LOG")"
check "still refused: fall back to terminal-notifier" \
    "claude-notify,lsregister,claude-notify,terminal-notifier" "$(native_probe 2 3 3)"
contains "the fallback banner stays clickable" "-execute" "$(cat "$STUB_LOG")"
# Not a fault to route around: a banner from another sender would override a
# choice the user made in System Settings.
check "switched off by the user: no other sender" \
    "claude-notify" "$(native_probe 2 4)"
check "crashed notifier: fall back, no re-register" \
    "claude-notify,terminal-notifier" "$(native_probe 2 139)"
# A binary built before the exit statuses existed reports 0 whatever happened,
# so the refusal cannot be seen — the registration is renewed up front instead.
check "pre-1.3.1 binary: re-register before every post" \
    "lsregister,claude-notify" "$(native_probe '' 0)"
native_probe 2 3 3 >/dev/null
check "exit 0 when the native path fails" "0" "$NATIVE_RC"

# The click on a native banner runs inside the bundle, long after the hook, so
# the host has to travel inside the notification. It is the last argument, after
# the group, so a pre-1.3.3 binary simply ignores it.
printf '2' >"$NATIVE_APP/Contents/Resources/native-notifier"
printf '0\n' >"$NATIVE_QUEUE"
: >"$STUB_LOG"
env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$NATIVE_STATE" \
    "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$REPO_ROOT" "vscode:7:123" >/dev/null 2>&1
contains "a native banner carries the host to its click" "claude-s1 vscode:7:123" "$(cat "$STUB_LOG")"

printf '\nWithout terminal-notifier\n'

# The app posts by itself, so terminal-notifier is a fallback, not a
# requirement. It used to be checked first: without it, every banner went
# through AppleScript even with the app built — no icon, and no click.
NO_TN_BIN="$STUB_BIN/no-tn"
mkdir -p "$NO_TN_BIN"
for tool in osascript lsregister; do ln -s "$STUB_BIN/$tool" "$NO_TN_BIN/$tool"; done
cat >"$NO_TN_BIN/pbcopy" <<STUB
#!/bin/bash
printf 'pbcopy %s\n' "\$(cat)" >>"$STUB_LOG"
STUB
chmod +x "$NO_TN_BIN/pbcopy"

# no_tn_probe <exit status>...: native_probe with terminal-notifier absent.
no_tn_probe() {
    printf '2' >"$NATIVE_APP/Contents/Resources/native-notifier"
    printf '%s\n' "$@" >"$NATIVE_QUEUE"
    : >"$STUB_LOG"
    env PATH="$NO_TN_BIN:/usr/bin:/bin" CLAUDE_NOTIFY_STATE_DIR="$NATIVE_STATE" \
        "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$REPO_ROOT" >/dev/null 2>&1
    awk '{ print $1 }' "$STUB_LOG" | paste -sd, -
}
check "the app posts with no terminal-notifier" "claude-notify" "$(no_tn_probe 0)"
check "a refused app falls back to AppleScript" \
    "claude-notify,lsregister,claude-notify,osascript" "$(no_tn_probe 3 3)"

printf '\nSetup hint\n'

# Offered once, as a banner. What it copies must outlive the version that
# copied it: a path into the plugin cache is deleted by the next update, so it
# is the npx installer instead. HOME stands in for the real one, because the
# hint is only ever offered for the default state dir.
HINT_HOME="$STUB_BIN/hint-home"
hint_probe() {
    : >"$STUB_LOG"
    env -u CLAUDE_NOTIFY_STATE_DIR -u CLAUDE_NOTIFY_BIN HOME="$HINT_HOME" PATH="$1" \
        "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$REPO_ROOT" >/dev/null 2>&1
    cat "$STUB_LOG"
}
SENT="$(hint_probe "$STUB_BIN:$NO_TN_BIN:/usr/bin:/bin")"
contains "the hint copies the npx installer" "pbcopy npx @anaidenko/claude-notify-resume" "$SENT"
contains "the hint arrives as a banner" "-title Want the Claude icon on these?" "$SENT"
contains "the real banner still follows" "-title Replied" "$SENT"
SENT="$(hint_probe "$STUB_BIN:$NO_TN_BIN:/usr/bin:/bin")"
check "the hint is offered once" "0" "$(printf '%s\n' "$SENT" | grep -c pbcopy)"
rm -rf "$HINT_HOME"
SENT="$(hint_probe "$NO_TN_BIN:/usr/bin:/bin")"
contains "with no terminal-notifier, the hint offers clicks" "Want clickable banners?" "$SENT"
rm -rf "$HINT_HOME"

printf '\nDetached delivery\n'

# The 1.2.1 hang: terminal-notifier (and any notifier) inherits the hook's
# stdout and stderr, and the harness waits for those pipes to close — not for
# the hook to exit. A notifier that blocks therefore stalled every turn for the
# whole hook timeout, even though notify.sh itself had already finished.
# So assert on the PIPES closing, not on the exit status: an earlier version of
# this check timed the script's exit and passed while the pipes stayed open.
HANG_DIR="$(mktemp -d)"
mkdir -p "$HANG_DIR/scripts"
cp "$REPO_ROOT/scripts/notify.sh" "$REPO_ROOT/scripts/load-config.sh" \
    "$REPO_ROOT/scripts/notify-parse.js" "$HANG_DIR/scripts/"
# A notifier that never returns, standing in for a wedged usernoted or a
# pending TCC prompt.
printf '#!/usr/bin/env bash\nsleep 60\n' >"$HANG_DIR/scripts/notify-macos.sh"
chmod +x "$HANG_DIR/scripts/notify-macos.sh"

# Read the hook's stdout to EOF exactly as the harness does. `cat` returns only
# once every writer has let go of the pipe, so this hangs for the full 60s if a
# descendant keeps holding it.
HANG_START=$SECONDS
( payload | "$HANG_DIR/scripts/notify.sh" "Replied" | cat >/dev/null 2>&1 ) &
HANG_PID=$!
( sleep 15; kill -9 $HANG_PID 2>/dev/null ) >/dev/null 2>&1 &
HANG_GUARD=$!
wait $HANG_PID 2>/dev/null
HANG_ELAPSED=$((SECONDS - HANG_START))
kill $HANG_GUARD 2>/dev/null
wait $HANG_GUARD 2>/dev/null
pkill -f "$HANG_DIR/scripts/notify-macos.sh" >/dev/null 2>&1
rm -rf "$HANG_DIR"

if [ "$HANG_ELAPSED" -lt 10 ]; then
    printf '  ok    a blocked notifier does not hold the hook'"'"'s pipes open\n'
    PASS=$((PASS + 1))
else
    printf '  FAIL  a blocked notifier held the hook'"'"'s pipes for %ss\n' "$HANG_ELAPSED"
    FAIL=$((FAIL + 1))
fi

printf '\nHost detection\n'

# The click must land in the app Claude Code runs under, and that is only
# knowable from the hook's ancestors (TERM_PROGRAM is empty in the hook). 1.3.0
# moved delivery into a detached child, which is reparented to launchd once
# notify.sh exits — a walk from there found no ancestors, so every fallback
# click opened Terminal. Run notify.sh detached, exactly as in production (no
# CLAUDE_NOTIFY_BIN: that switches delivery to synchronous and hides the bug),
# under a parent posing as iTerm, and record the host it hands to delivery.
HOST_DIR="$(mktemp -d)"
mkdir -p "$HOST_DIR/scripts"
cp "$REPO_ROOT/scripts/notify.sh" "$REPO_ROOT/scripts/load-config.sh" \
    "$REPO_ROOT/scripts/notify-parse.js" "$HOST_DIR/scripts/"
cat >"$HOST_DIR/scripts/notify-macos.sh" <<STUB
#!/usr/bin/env bash
printf '%s' "\${5-<no host argument>}" >"$HOST_DIR/host.txt"
STUB
chmod +x "$HOST_DIR/scripts/notify-macos.sh"
payload >"$HOST_DIR/payload.json"

# host_probe <fake app executable> [log file to hold open], both relative to
# HOST_DIR. Prints the host handed to delivery, with the fake parent's own pid
# written as PID.
#
# `ps` reports a symlink by its own path, so a symlinked bash shows up as the
# app. A copy of the binary would not do: macOS kills a relocated system binary
# on launch. The trailing `true` stops bash from exec-ing notify.sh in its own
# place, which would take the fake parent out of the tree.
host_probe() {
    local exe="$HOST_DIR/$1" log="${2:+$HOST_DIR/$2}"
    mkdir -p "$(dirname "$exe")"
    [ -L "$exe" ] || ln -s /bin/bash "$exe"
    [ -z "$log" ] || mkdir -p "$(dirname "$log")"
    rm -f "$HOST_DIR/host.txt" "$HOST_DIR/parent.pid"
    # shellcheck disable=SC2016  # must expand in the inner bash, not here
    "$exe" -c '
        printf "%s" "$$" >"$1/parent.pid"
        [ -z "$2" ] || exec 3>>"$2"
        "$1/scripts/notify.sh" "Replied" <"$1/payload.json"
        true' _ "$HOST_DIR" "$log" >/dev/null 2>&1
    for _ in $(seq 50); do
        [ -f "$HOST_DIR/host.txt" ] && break
        sleep 0.1
    done
    local host parent
    host="$(cat "$HOST_DIR/host.txt" 2>/dev/null)"
    parent="$(cat "$HOST_DIR/parent.pid" 2>/dev/null)"
    printf '%s' "${host//$parent/PID}"
}

check "host is resolved before delivery detaches" "iTerm" \
    "$(host_probe "iTerm.app/Contents/MacOS/iTerm2")"

# A VS Code session reopens as its own tab, which needs the window it lives in.
# Each window's extension host keeps that window's log directory open
# (logs/<session>/window<N>/exthost/), so the id is read from its open files.
# The pid rides along so the click can tell the id still means that window.
check "a VS Code extension host names its window" "vscode:7:PID" "$(host_probe \
    "Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)" \
    "Code/logs/20261114T204338/window7/exthost/exthost.log")"

# A CLI in VS Code's integrated terminal sits under the pty host, which owns no
# window. Without an id there is no tab to return to.
check "VS Code without a window stays a bare vscode" "vscode" "$(host_probe \
    "Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper")"

# Insiders lives at "Visual Studio Code - Insiders.app", so a plain VS Code
# match would claim it, and a vscode:// URL would then open the stable app. Its
# own scheme is untested, so it is named and left to a terminal.
check "VS Code Insiders is not taken for VS Code" "vscode-insiders" "$(host_probe \
    "Visual Studio Code - Insiders.app/Contents/Frameworks/Code - Insiders Helper (Plugin).app/Contents/MacOS/Code - Insiders Helper (Plugin)" \
    "Code - Insiders/logs/20261114T204338/window7/exthost/exthost.log")"
rm -rf "$HOST_DIR"

# ...and the host notify.sh resolved is the one the click receives.
SENT="$(capture "$REPO_ROOT/scripts/notify-macos.sh" "Replied" "chat" "s1" "$REPO_ROOT" "iTerm")"
contains "the click carries the host" "CLAUDE_NOTIFY_HOST=iTerm" "$SENT"

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

printf '\nConfig file\n'

# Settings can live in a file instead of the global `env` block, which exports
# into every process Claude Code spawns. The environment still wins, so a one-off
# override works; and a malformed file must never take the hook down.
CONFIG_FILE="$STUB_BIN/notify.conf"

config_probe() {
    local name="$1" body="$2" want="$3"
    shift 3
    printf '%s' "$body" >"$CONFIG_FILE"
    : >"$STUB_LOG"
    payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" \
        CLAUDE_NOTIFY_CONFIG="$CONFIG_FILE" "$@" \
        "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
    local got
    if [ -s "$STUB_LOG" ]; then got="sent"; else got="muted"; fi
    check "$name" "$want" "$got"
}

config_probe "file mutes a status"        'MUTE=Replied
' "muted"
config_probe "comments and spaces"       '# a comment

  MUTE = replied
' "muted"
config_probe "environment overrides file" 'MUTE=Replied
' "sent" env CLAUDE_NOTIFY_MUTE=Other
config_probe "junk lines are skipped"    'not a config line
MUTE=Replied
!!!=x
' "muted"

# The one rule: a broken config must not break the session.
printf 'garbage\n\001\002\nMUTE\n=\n' >"$CONFIG_FILE"
payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" \
    CLAUDE_NOTIFY_CONFIG="$CONFIG_FILE" "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 on a malformed config" "0" "$?"

payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" \
    CLAUDE_NOTIFY_CONFIG="/nonexistent/config" "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
check "exit 0 when the config is absent" "0" "$?"
rm -f "$CONFIG_FILE"

# An empty environment variable is how you switch a file setting off for one
# run, so set-but-empty must beat the file — testing non-emptiness silently
# broke that.
printf 'MUTE=Replied\n' >"$CONFIG_FILE"
: >"$STUB_LOG"
payload | env CLAUDE_NOTIFY_BIN="$STUB_BIN" CLAUDE_NOTIFY_STATE_DIR="$STUB_BIN/state" \
    CLAUDE_NOTIFY_CONFIG="$CONFIG_FILE" CLAUDE_NOTIFY_MUTE= \
    "$REPO_ROOT/scripts/notify.sh" "Replied" >/dev/null 2>&1
if [ -s "$STUB_LOG" ]; then
    check "empty variable overrides the file" "sent" "sent"
else
    check "empty variable overrides the file" "sent" "muted"
fi

# A `#` inside quotes belongs to the value; only an unquoted one starts a
# comment. Stripping comments first turned the value into garbage.
printf 'TERMINAL="iTerm # keep"\n' >"$CONFIG_FILE"
# shellcheck disable=SC2016  # must expand in the inner bash, not here
GOT="$(env CLAUDE_NOTIFY_CONFIG="$CONFIG_FILE" bash -c \
    '. "$0"; printf "%s" "${CLAUDE_NOTIFY_TERMINAL:-}"' \
    "$REPO_ROOT/scripts/load-config.sh")"
check "quoted # stays in the value" "iTerm # keep" "$GOT"

printf 'TERMINAL=iTerm # drop\n' >"$CONFIG_FILE"
# shellcheck disable=SC2016  # must expand in the inner bash, not here
GOT="$(env CLAUDE_NOTIFY_CONFIG="$CONFIG_FILE" bash -c \
    '. "$0"; printf "%s" "${CLAUDE_NOTIFY_TERMINAL:-}"' \
    "$REPO_ROOT/scripts/load-config.sh")"
check "unquoted # starts a comment" "iTerm" "$GOT"
rm -f "$CONFIG_FILE"

printf '\nResuming\n'

# Both spellings appear in the wild: a shell resume writes `--resume <id>`, the
# VS Code extension writes `--resume=<id>`. Matching only the first form meant
# editor-hosted sessions were never found, so every click opened a new window.
# Run the real expression out of the script rather than a copy of it: an earlier
# version of this test asserted on its own inline awk, so it stayed green while
# the script it was meant to cover did something else.
# shellcheck disable=SC2016  # matches the literal $SESSION_ID in the script
TTY_MATCH="$(sed -n 's/^ *awk -v id="\$SESSION_ID" //p' "$REPO_ROOT/scripts/open-session.sh" |
    head -1 | sed "s/')\"$/'/")"
[ -n "$TTY_MATCH" ] || {
    printf '  FAIL  could not lift the tty-match expression from open-session.sh\n'
    FAIL=$((FAIL + 1))
}

for form in "--resume SESSIONX" "--resume=SESSIONX"; do
    MATCHED="$(printf 'ttys999 claude %s\n' "$form" |
        eval awk -v 'id="SESSIONX"' "$TTY_MATCH")"
    check "tty match: claude $form" "ttys999" "$MATCHED"
done

# The VS Code extension spawns a copy with no controlling terminal, which `ps`
# prints as `??` and lists before the real tab. Taking the first match picked a
# tty that can never own a tab, so the tab lookup failed and each click opened
# another window next to the session that was already there.
MATCHED="$(printf '?? claude --resume=SESSIONX\nttys999 claude --resume SESSIONX\n' |
    eval awk -v 'id="SESSIONX"' "$TTY_MATCH")"
check "a ttyless row does not mask the real tab" "ttys999" "$MATCHED"

printf '\n%d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
