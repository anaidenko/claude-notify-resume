#!/usr/bin/env bash
# Desktop notification hook for Claude Code.
#
# The banner leads with the status ("Replied") and carries the chat's own
# AI-generated name as its body, so parallel sessions stay distinguishable.
# On macOS, clicking it reopens that exact conversation via `claude --resume`.
#
# Usage: notify.sh <status>   (hook JSON payload arrives on stdin)
set -uo pipefail

STATUS="${1:-Claude Code}"

# Settings may come from a config file as well as the environment; the
# environment wins. Sourced before the mute check so a file-only MUTE applies.
# shellcheck source=scripts/load-config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-config.sh"

# CLAUDE_NOTIFY_MUTE is a comma-separated list of statuses to drop, so anyone
# who finds a banner on every reply too chatty can keep just the ones that need
# them — e.g. CLAUDE_NOTIFY_MUTE="Replied,Waiting for you". Checked first, before
# any work: a muted status should cost nothing.
#
# Matching ignores case and surrounding spaces, because this list is written by
# hand. Matching the bare status (not the TEST · form) keeps a muted status muted
# while debugging.
if [ -n "${CLAUDE_NOTIFY_MUTE:-}" ]; then
    mute_probe="$(printf '%s' "$STATUS" | tr '[:upper:]' '[:lower:]')"
    IFS=','
    for muted in $CLAUDE_NOTIFY_MUTE; do
        # Trim: "a, b" must match " b" as well as "b".
        muted="$(printf '%s' "$muted" | tr '[:upper:]' '[:lower:]' |
            sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
        [ -n "$muted" ] && [ "$muted" = "$mute_probe" ] && exit 0
    done
    unset IFS
fi

# Set CLAUDE_NOTIFY_TEST=1 to mark a banner as a manual test, so a real
# notification is never mistaken for one while debugging.
#
# No brackets in the marker: a -title beginning with "[" is swallowed by
# terminal-notifier, which then falls back to its default title of "Terminal".
[ "${CLAUDE_NOTIFY_TEST:-}" = "1" ] && STATUS="TEST · $STATUS"

# Hooks inherit a minimal PATH with neither Homebrew nor nvm on it, so `node`
# and the notifier binary are both missing unless they are added back. Without
# this the parser silently fails and every banner degrades to a generic title.
# CLAUDE_NOTIFY_BIN lets the test suite put stub binaries ahead of the real
# ones. Without it a test run would deliver actual banners, since the Homebrew
# path below deliberately outranks whatever the caller had on PATH.
PATH="${CLAUDE_NOTIFY_BIN:+$CLAUDE_NOTIFY_BIN:}/opt/homebrew/bin:/usr/local/bin:$PATH"
# nvm installs are version-stamped. Pick the highest version rather than
# whichever the glob yields last: plain sorting puts v9 after v22, and this
# project's JS uses syntax an old Node rejects outright.
if ! command -v node >/dev/null 2>&1 && [ -d "$HOME/.nvm/versions/node" ]; then
    newest="$(
        for candidate in "$HOME"/.nvm/versions/node/v*/bin/node; do
            [ -x "$candidate" ] && printf '%s\n' "$candidate"
        done | sed 's|.*/node/v||; s|/bin/node$||' |
            sort -t. -k1,1n -k2,2n -k3,3n | tail -1
    )"
    [ -n "$newest" ] && PATH="$HOME/.nvm/versions/node/v$newest/bin:$PATH"
fi
export PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(dirname "$SCRIPT_DIR")"
PARSER="$SCRIPT_DIR/notify-parse.js"

# A notification must never break the session: every failure path exits 0.
[ -f "$PARSER" ] || exit 0

NODE_BIN="$(command -v node 2>/dev/null)"
[ -n "$NODE_BIN" ] || exit 0
FIELDS="$("$NODE_BIN" "$PARSER" 2>/dev/null)"

SESSION_ID="$(printf '%s\n' "$FIELDS" | sed -n 1p)"
CWD="$(printf '%s\n' "$FIELDS" | sed -n 3p)"
CHAT="$(printf '%s\n' "$FIELDS" | sed -n 4p)"

# `ai-title` is an internal transcript record, not a documented contract — fall
# back to the project directory if a future version stops emitting it.
if [ -z "$CHAT" ] && [ -n "${CWD:-}" ] && [ "$CWD" != "-" ]; then
    CHAT="$(basename "$CWD")"
fi
[ -n "$CHAT" ] || CHAT="Claude Code"
[ "${#CHAT}" -gt 60 ] && CHAT="${CHAT:0:59}…"

# Which app is Claude Code running under? The click needs it to resume in the
# right terminal, and only the hook's ancestors can tell: TERM_PROGRAM is empty
# in the hook environment, and by click time the tree is gone. Resolved here,
# before delivery detaches. Once this script exits, the detached child is
# reparented to launchd and has no ancestors left to walk. That is how 1.3.0
# lost the host, so every fallback click opened Terminal. macOS only, since
# Linux banners have no click.
HOST=""
if [ "$(uname -s)" = "Darwin" ]; then
    probe_pid=$PPID
    for _ in 1 2 3 4 5 6; do
        if [ -z "$probe_pid" ] || [ "$probe_pid" = "1" ]; then
            break
        fi
        probe_cmd="$(ps -o comm= -p "$probe_pid" 2>/dev/null)"
        case "$probe_cmd" in
            # Insiders is checked first: its path also contains "Visual Studio
            # Code", and a vscode:// click would open the stable app instead.
            *"Visual Studio Code - Insiders"*) HOST="vscode-insiders"; break ;;
            *"Visual Studio Code"* | *"Code Helper"*) HOST="vscode"; break ;;
            *iTerm*) HOST="iTerm"; break ;;
            *Terminal.app*) HOST="Terminal"; break ;;
        esac
        probe_pid="$(ps -o ppid= -p "$probe_pid" 2>/dev/null | tr -d ' ')"
    done

    # Under the VS Code extension, the click reopens the session's own tab, so
    # it needs the window. VS Code sends a vscode:// URL to its last active
    # window unless the URL names one. In another project's window, the
    # extension starts a new, empty session instead. The window id is visible
    # only in the extension host's open files: each one keeps its window's log
    # directory, logs/<session>/window<N>/exthost/, open. Its pid goes along so
    # the click can check that the window is still the same one. A pty host
    # (integrated terminal) owns no window and stays a bare "vscode".
    if [ "$HOST" = "vscode" ]; then
        # /usr/sbin is not always on a hook's PATH.
        LSOF="$(command -v lsof 2>/dev/null || printf '%s' /usr/sbin/lsof)"
        window_id="$("$LSOF" -p "$probe_pid" -Fn 2>/dev/null |
            sed -n 's|^n.*/logs/[^/]*/window\([0-9][0-9]*\)/exthost/.*|\1|p' | head -1)"
        [ -n "$window_id" ] && HOST="vscode:$window_id:$probe_pid"
    fi
fi

# Deliver from a fully detached background child, stdio closed.
#
# The harness waits for the hook's stdout/stderr to reach EOF, not for the hook
# to exit — and every descendant inherits those descriptors. So a notifier that
# blocks holds the turn open even once notify.sh has returned: the 2026-08-26
# hang, ~60s of spinner on every turn, traced to a `terminal-notifier -sender`
# parked forever in an AppKit event loop. Closing stdio here cuts the
# inheritance, so the turn ends whatever the notifier decides to do.
#
# CLAUDE_NOTIFY_BIN (the test-stub marker) keeps delivery synchronous, so the
# suites can assert on stub captures right after notify.sh returns.
deliver() {
    case "$(uname -s)" in
        Darwin) "$PLUGIN_ROOT/scripts/notify-macos.sh" "$STATUS" "$CHAT" "$SESSION_ID" "$CWD" "$HOST" ;;
        Linux) "$PLUGIN_ROOT/scripts/notify-linux.sh" "$STATUS" "$CHAT" ;;
    esac
}

if [ -n "${CLAUDE_NOTIFY_BIN:-}" ]; then
    deliver
else
    deliver </dev/null >/dev/null 2>&1 &
fi

exit 0
