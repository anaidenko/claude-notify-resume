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

case "$(uname -s)" in
    Darwin) "$PLUGIN_ROOT/scripts/notify-macos.sh" "$STATUS" "$CHAT" "$SESSION_ID" "$CWD" ;;
    Linux) "$PLUGIN_ROOT/scripts/notify-linux.sh" "$STATUS" "$CHAT" ;;
esac

exit 0
