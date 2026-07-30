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

# The icon and a clickable banner body are mutually exclusive: -sender gives the
# banner the Claude icon but takes the click with it, leaving the "Show" action
# button as the way in (verified — -execute is ignored whenever -sender is
# present). Show is a fine alternative, and the icon is what makes a banner
# recognisable at a glance, so installing the bundle is the whole opt-in.
if [ -d "$APP" ] && [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # -sender routes the click to the bundle, which resumes the session by
    # reading this state file. Write-then-rename: a click landing mid-write
    # would otherwise read a half-written file and silently do nothing.
    mkdir -p "$STATE_DIR"
    if printf '%s\n%s\n' "$SESSION_ID" "$CWD" >"$STATE_DIR/last-session.tmp" 2>/dev/null; then
        mv -f "$STATE_DIR/last-session.tmp" "$STATE_DIR/last-session" 2>/dev/null
    fi
    ARGS+=(-sender "$BUNDLE_ID")
elif [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # No custom icon, but the whole banner is clickable. The click runs
    # open-session.sh, which reuses this session's existing tab when there is
    # one — keeping the conditional logic in a script rather than trying to
    # express it inside a nested AppleScript literal.
    # Absolute: the click runs from an arbitrary working directory.
    OPENER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/open-session.sh"

    # Which app is Claude Code running under? Only knowable now — by the time
    # the banner is clicked the process tree is gone and the frontmost app is
    # Notification Centre. Walk up from this hook to the first app we can drive.
    HOST=""
    probe_pid=$PPID
    for _ in 1 2 3 4 5 6; do
        if [ -z "$probe_pid" ] || [ "$probe_pid" = "1" ]; then
            break
        fi
        probe_cmd="$(ps -o comm= -p "$probe_pid" 2>/dev/null)"
        case "$probe_cmd" in
            *"Visual Studio Code"*|*"Code Helper"*) HOST="vscode"; break ;;
            *iTerm*) HOST="iTerm"; break ;;
            *Terminal.app*) HOST="Terminal"; break ;;
        esac
        probe_pid="$(ps -o ppid= -p "$probe_pid" 2>/dev/null | tr -d ' ')"
    done

    ARGS+=(-execute "$(printf 'CLAUDE_NOTIFY_HOST=%q %q %q %q' "$HOST" "$OPENER" "$SESSION_ID" "$CWD")")
fi

terminal-notifier "${ARGS[@]}" >/dev/null 2>&1 || true
exit 0
