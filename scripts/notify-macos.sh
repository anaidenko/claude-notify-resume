#!/usr/bin/env bash
# macOS banner via terminal-notifier. Called by notify.sh with the fields it
# already parsed: <status> <chat> <session-id> <cwd>
set -uo pipefail

STATUS="$1"
CHAT="$2"
SESSION_ID="${3:--}"
CWD="${4:--}"

# Honour the test-stub directory here too: this script is also called directly,
# without notify.sh having set up PATH.
[ -n "${CLAUDE_NOTIFY_BIN:-}" ] && PATH="$CLAUDE_NOTIFY_BIN:$PATH" && export PATH

# Escape a value for embedding in an AppleScript double-quoted string.
# AppleScript only understands \\ and \" — it hard-errors on anything else,
# notably the `\ ` that `printf %q` produces for a space.
applescript_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Fall back to AppleScript when terminal-notifier is absent, so the plugin
# works on a bare macOS with nothing installed. The trade-off: `display
# notification` shows the host app's icon (Script Editor) and supports no click
# action, so terminal-notifier remains the better path when available.
if ! command -v terminal-notifier >/dev/null 2>&1; then
    osascript -e "display notification \"$(applescript_escape "$CHAT")\" with title \"$(applescript_escape "$STATUS")\" sound name \"Glass\"" >/dev/null 2>&1 || true
    exit 0
fi

# Overridable so the test suite never writes to the real user's state.
STATE_DIR="${CLAUDE_NOTIFY_STATE_DIR:-$HOME/.claude/claude-code-notify}"
APP="$STATE_DIR/Claude Code.app"
BUNDLE_ID="com.claude-code.notify"

ARGS=(-title "$STATUS" -message "$CHAT" -sound Glass)

# -group collapses repeat banners from one chat instead of stacking them.
[ "$SESSION_ID" != "-" ] && ARGS+=(-group "claude-$SESSION_ID")

# The icon and a clickable banner body are mutually exclusive, and the icon is
# NOT the default: -sender gives the banner the Claude icon but takes the click
# with it, leaving only the "Show" action button (verified — -execute is ignored
# whenever -sender is present). Losing a click most people expect to work is the
# worse trade, so the bundle alone is not enough: opting in takes
# CLAUDE_NOTIFY_ICON=1 as well.
if [ -d "$APP" ] && [ "${CLAUDE_NOTIFY_ICON:-}" = "1" ] && [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # -sender routes the click to the bundle, which resumes the session by
    # reading this state file. Write-then-rename: a click landing mid-write
    # would otherwise read a half-written file and silently do nothing.
    mkdir -p "$STATE_DIR"
    if printf '%s\n%s\n' "$SESSION_ID" "$CWD" >"$STATE_DIR/last-session.tmp" 2>/dev/null; then
        mv -f "$STATE_DIR/last-session.tmp" "$STATE_DIR/last-session" 2>/dev/null
    fi
    ARGS+=(-sender "$BUNDLE_ID")
elif [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # No bundle: no custom icon, but -execute makes the click exact.
    #
    # Two layers of quoting, and they are not interchangeable. `printf %q`
    # protects the value for the shell that finally runs it; the result is then
    # embedded in an AppleScript string literal, which needs its own escaping —
    # skip that and any cwd containing a space produces `\ `, on which
    # AppleScript fails with a syntax error and the click silently does nothing.
    # The click can land long after the banner was sent, by which time the
    # folder may be renamed, unmounted or (for a temporary dir) cleaned up.
    # Check inside the command rather than letting `cd` fail with a bare
    # "no such file or directory" in a freshly opened window.
    # No quotes in the fallback message: this string is nested inside an
    # AppleScript literal which is itself inside the single-quoted -execute
    # argument, so either quote character would terminate a layer early.
    QUOTED_CWD="$(printf '%q' "$CWD")"
    RESUME="cd $QUOTED_CWD 2>/dev/null && claude --resume $(printf '%q' "$SESSION_ID") || echo claude-code-notify:\\ that\\ session\\ folder\\ no\\ longer\\ exists"
    ARGS+=(-execute "osascript -e 'tell application \"Terminal\" to do script \"$(applescript_escape "$RESUME")\"' -e 'tell application \"Terminal\" to activate'")
fi

terminal-notifier "${ARGS[@]}" >/dev/null 2>&1 || true
exit 0
