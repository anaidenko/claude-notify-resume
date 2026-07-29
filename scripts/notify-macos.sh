#!/usr/bin/env bash
# macOS banner via terminal-notifier. Called by notify.sh with the fields it
# already parsed: <status> <chat> <session-id> <cwd>
set -uo pipefail

STATUS="$1"
CHAT="$2"
SESSION_ID="${3:--}"
CWD="${4:--}"

command -v terminal-notifier >/dev/null 2>&1 || exit 0

STATE_DIR="$HOME/.claude/claude-code-notify"
APP="$STATE_DIR/Claude Code.app"
BUNDLE_ID="com.claude-code.notify"

ARGS=(-title "$STATUS" -message "$CHAT" -sound Glass)

# -group collapses repeat banners from one chat instead of stacking them.
[ "$SESSION_ID" != "-" ] && ARGS+=(-group "claude-$SESSION_ID")

if [ -d "$APP" ] && [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # The bundle exists purely to own the banner's left-hand icon (macOS takes
    # it from the sending app). -sender also takes over the click, so the bundle
    # performs the resume itself, reading the session from this state file.
    mkdir -p "$STATE_DIR"
    printf '%s\n%s\n' "$SESSION_ID" "$CWD" >"$STATE_DIR/last-session" 2>/dev/null
    ARGS+=(-sender "$BUNDLE_ID")
elif [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # No bundle: no custom icon, but -execute makes the click exact.
    RESUME="cd $(printf '%q' "$CWD") && claude --resume $(printf '%q' "$SESSION_ID")"
    ARGS+=(-execute "osascript -e 'tell application \"Terminal\" to do script \"${RESUME//\"/\\\"}\"' -e 'tell application \"Terminal\" to activate'")
fi

terminal-notifier "${ARGS[@]}" >/dev/null 2>&1 || true
exit 0
