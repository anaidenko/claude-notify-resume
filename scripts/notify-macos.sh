#!/usr/bin/env bash
# macOS banner via terminal-notifier. Called by notify.sh with the fields it
# already resolved: <status> <chat> <session-id> <cwd> [host]
set -uo pipefail

STATUS="$1"
CHAT="$2"
SESSION_ID="${3:--}"
CWD="${4:--}"
# The app Claude Code runs under (vscode, iTerm, Terminal, or empty). It comes
# from notify.sh because this script runs detached: from here the process tree
# ends at launchd, so a walk would find nothing.
HOST="${5:-}"

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

ARGS=(-title "$STATUS" -message "$CHAT" -sound Glass)

# -group collapses repeat banners from one chat instead of stacking them.
[ "$SESSION_ID" != "-" ] && ARGS+=(-group "claude-$SESSION_ID")

# Offer the icon setup once, as a banner rather than on stderr: a hook that
# exits 0 has its stderr swallowed, so a printed hint would never be seen. The
# path is filled in from this install, since the script knows where it lives.
# `set -C` makes the marker creation exclusive, so two concurrent hooks cannot
# both decide they are the first.
if [ ! -d "$APP" ] && [ -z "${CLAUDE_NOTIFY_STATE_DIR:-}" ]; then
    ICON_HINT="$STATE_DIR/.icon-hint-shown"
    if [ ! -f "$ICON_HINT" ] && mkdir -p "$STATE_DIR" 2>/dev/null; then
        if (set -C; : >"$ICON_HINT") 2>/dev/null; then
            SETUP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-macos-icon.sh"
            printf '%s\n' "$SETUP_PATH" | pbcopy 2>/dev/null
            terminal-notifier -title "Want the Claude icon on these?" \
                -message "Setup command copied — paste it into a terminal." \
                -sound Glass >/dev/null 2>&1 || true
        fi
    fi
fi

# With the bundle installed, the bundle itself posts the notification through
# the native UserNotifications API — so the banner carries the Claude icon AND
# the whole body is clickable: the click lands in the bundle's own delegate,
# with this session's id and cwd riding inside the notification. No spoofed
# sender, no shared state file, no fake-bundle launch quirks.
#
# The marker file distinguishes a compiled bundle from the older script-only
# one, which does not understand `post` — that one falls through to -execute
# and keeps working, just without the icon, until setup is re-run.
NOTIFIER_BIN="$APP/Contents/MacOS/claude-notify"
MARKER="$APP/Contents/Resources/native-notifier"
if [ -f "$MARKER" ] && [ -x "$NOTIFIER_BIN" ] &&
    [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    OPENER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/open-session.sh"
    post() {
        "$NOTIFIER_BIN" post "$STATUS" "$CHAT" "$SESSION_ID" "$CWD" "$OPENER" \
            "claude-$SESSION_ID" >/dev/null 2>&1
    }

    # Launch Services can forget the bundle — it lives in a hidden directory
    # nothing rescans, and a macOS update is the likely trigger — and usernoted
    # then refuses every post ("Failed to find or validate client"), visible
    # only in the system log.
    # Re-registering is what setup did in the first place, and costs ~30ms.
    # Looked up on PATH first only so the test suite can stub it.
    LSREGISTER="$(command -v lsregister 2>/dev/null)"
    [ -n "$LSREGISTER" ] ||
        LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    reregister() { "$LSREGISTER" -f "$APP" >/dev/null 2>&1; }

    # An empty marker means a binary built before 1.3.1, which exits 0 whatever
    # macOS answered — a refused post is indistinguishable from a delivered one.
    # Renew the registration up front instead, until setup is re-run.
    if [ ! -s "$MARKER" ]; then
        reregister
        post
        exit 0
    fi

    # The exit status is the binary's verdict: 0 posted, 3 macOS refused us as a
    # client, 4 the user switched "Claude Code" off in System Settings.
    post
    rc=$?
    if [ "$rc" -eq 3 ]; then
        reregister
        post
        rc=$?
    fi
    # 4 is a choice rather than a fault: a banner from another sender would
    # override it, so nothing routes around it.
    case "$rc" in 0 | 4) exit 0 ;; esac
    # Still refused, or the binary crashed: fall through to terminal-notifier,
    # so a broken bundle costs the icon rather than the banner.
fi

if [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    # No custom icon, but the whole banner is clickable. The click runs
    # open-session.sh, which reuses this session's existing tab when there is
    # one — keeping the conditional logic in a script rather than trying to
    # express it inside a nested AppleScript literal.
    # Absolute: the click runs from an arbitrary working directory.
    OPENER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/open-session.sh"

    ARGS+=(-execute "$(printf 'CLAUDE_NOTIFY_HOST=%q %q %q %q' "$HOST" "$OPENER" "$SESSION_ID" "$CWD")")
fi

terminal-notifier "${ARGS[@]}" >/dev/null 2>&1 || true
exit 0
