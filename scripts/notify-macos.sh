#!/usr/bin/env bash
# macOS banner. Called by notify.sh with the fields it already resolved:
# <status> <chat> <session-id> <cwd> [host]
#
# Senders, best first: the compiled icon app (Claude icon, clickable), then
# terminal-notifier (clickable), then AppleScript (neither, but needs nothing
# installed). The app needs no terminal-notifier: it posts by itself.
set -uo pipefail

STATUS="$1"
CHAT="$2"
SESSION_ID="${3:--}"
CWD="${4:--}"
# The app Claude Code runs under: iTerm, Terminal, vscode[:<window>:<pid>],
# vscode-insiders, or empty. It comes from notify.sh because this script runs
# detached: from here the process tree ends at launchd, so a walk finds nothing.
HOST="${5:-}"

# Honour the test-stub directory here too: this script is also called directly,
# without notify.sh having set up PATH.
[ -n "${CLAUDE_NOTIFY_BIN:-}" ] && PATH="$CLAUDE_NOTIFY_BIN:$PATH" && export PATH

# Escape a value for embedding in an AppleScript double-quoted string.
# AppleScript only understands \\ and \" — it hard-errors on anything else,
# notably the `\ ` that `printf %q` produces for a space.
applescript_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

HAVE_TN=
command -v terminal-notifier >/dev/null 2>&1 && HAVE_TN=1

# plain_banner <title> <message>: a banner with no click action. Through
# terminal-notifier when installed; else AppleScript, which works on a bare
# macOS but shows Script Editor's icon, and opens Script Editor when clicked.
plain_banner() {
    if [ -n "$HAVE_TN" ]; then
        terminal-notifier -title "$1" -message "$2" -sound Glass >/dev/null 2>&1
    else
        osascript -e "display notification \"$(applescript_escape "$2")\" with title \"$(applescript_escape "$1")\" sound name \"Glass\"" \
            </dev/null >/dev/null 2>&1
    fi
}

# Overridable so the test suite never writes to the real user's state.
STATE_DIR="${CLAUDE_NOTIFY_STATE_DIR:-$HOME/.claude/claude-code-notify}"
APP="$STATE_DIR/Claude Code.app"

# Offer the icon setup once, as a banner rather than on stderr: a hook that
# exits 0 has its stderr swallowed, so a printed hint would never be seen. It
# copies the npx installer rather than this script's path: the path names this
# plugin version, whose directory the next update deletes, while the installer
# always builds from the copy installed at the time.
# `set -C` makes the marker creation exclusive, so two concurrent hooks cannot
# both decide they are the first.
if [ ! -d "$APP" ] && [ -z "${CLAUDE_NOTIFY_STATE_DIR:-}" ]; then
    ICON_HINT="$STATE_DIR/.icon-hint-shown"
    if [ ! -f "$ICON_HINT" ] && mkdir -p "$STATE_DIR" 2>/dev/null; then
        if (set -C; : >"$ICON_HINT") 2>/dev/null; then
            printf '%s\n' "npx @anaidenko/claude-notify-resume" | pbcopy 2>/dev/null
            if [ -n "$HAVE_TN" ]; then
                plain_banner "Want the Claude icon on these?" \
                    "Setup command copied — paste it into a terminal."
            else
                plain_banner "Want clickable banners?" \
                    "Setup command copied — paste it into a terminal."
            fi
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
# and keeps working, just without the icon, until the app is rebuilt.
NOTIFIER_BIN="$APP/Contents/MacOS/claude-notify"
MARKER="$APP/Contents/Resources/native-notifier"
if [ -f "$MARKER" ] && [ -x "$NOTIFIER_BIN" ] &&
    [ "$SESSION_ID" != "-" ] && [ "$CWD" != "-" ]; then
    OPENER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/open-session.sh"
    # The host goes last, after the group: the click runs inside the bundle long
    # after this hook is gone, so it travels in the notification. A pre-1.3.3
    # binary ignores the extra argument and its clicks fall back to a terminal.
    post() {
        "$NOTIFIER_BIN" post "$STATUS" "$CHAT" "$SESSION_ID" "$CWD" "$OPENER" \
            "claude-$SESSION_ID" "$HOST" >/dev/null 2>&1
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
    # Renew the registration up front instead, until the app is rebuilt.
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
    # Still refused, or the binary crashed: fall through to the other senders,
    # so a broken bundle costs the icon rather than the banner.
fi

if [ -z "$HAVE_TN" ]; then
    plain_banner "$STATUS" "$CHAT"
    exit 0
fi

ARGS=(-title "$STATUS" -message "$CHAT" -sound Glass)

# -group collapses repeat banners from one chat instead of stacking them.
[ "$SESSION_ID" != "-" ] && ARGS+=(-group "claude-$SESSION_ID")

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
