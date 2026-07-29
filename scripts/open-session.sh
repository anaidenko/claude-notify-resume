#!/usr/bin/env bash
# Reopen a Claude Code session in a terminal — the click target for a banner.
#
#   open-session.sh <session-id> <cwd>
#
# Extracted from the -execute argument on purpose: that argument nests a shell
# command inside an AppleScript literal inside a single-quoted string, and
# anything conditional becomes unreadable (and unquotable) in that form. Here it
# is ordinary code.
set -uo pipefail

SESSION_ID="${1:-}"
CWD="${2:-}"
[ -n "$SESSION_ID" ] && [ -n "$CWD" ] || exit 0

RESUME="cd $(printf '%q' "$CWD") && claude --resume $(printf '%q' "$SESSION_ID")"
# Marks the tab so a later click can find it instead of opening a duplicate.
TAB_TITLE="claude:$SESSION_ID"

escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Report back to the user. Prefer terminal-notifier: a bare `osascript`
# notification is owned by Script Editor, so clicking it opens Script Editor's
# file dialog — confusing, and nothing to do with this plugin.
notify() {
    if command -v terminal-notifier >/dev/null 2>&1; then
        terminal-notifier -title "$1" -message "$2" -sound "${3:-Basso}" >/dev/null 2>&1
    else
        osascript -e "display notification \"$(escape "$2")\" with title \"$(escape "$1")\" sound name \"${3:-Basso}\"" >/dev/null 2>&1
    fi
}

# The click can land long after the banner was sent — the folder may have been
# renamed, unmounted, or cleaned up if it was temporary.
if [ ! -d "$CWD" ]; then
    notify "Session folder is gone" "$CWD"
    exit 0
fi

# Which terminal to drive. Reopening a session somewhere other than where you
# are working is worse than useless, so detect the host rather than guessing:
# walk the process tree recorded at notify time (CLAUDE_NOTIFY_HOST) and fall
# back to Terminal.app, which is always present.
#
# TERM_PROGRAM is not usable here — it is empty in the environment hooks run in.
TERMINAL_APP="${CLAUDE_NOTIFY_TERMINAL:-${CLAUDE_NOTIFY_HOST:-Terminal}}"

if [ "$TERMINAL_APP" = "vscode" ] || [ "$TERMINAL_APP" = "code" ]; then
    # VS Code has no scriptable terminal, so this opens the folder and leaves
    # the resume command on the clipboard rather than pretending otherwise.
    # `code` is installed by "Shell Command: Install 'code' command in PATH".
    if command -v code >/dev/null 2>&1; then
        # VS Code focuses an existing window for this folder; -n avoids hijacking
        # an unrelated window when the folder is not open anywhere.
        code --new-window "$CWD" >/dev/null 2>&1
        printf '%s' "$RESUME" | pbcopy 2>/dev/null
        notify "Session opened in VS Code" "Resume command copied — paste it into the terminal." "Glass"
        exit 0
    fi
    notify "VS Code CLI not found" "Install it via Shell Command: Install 'code' command in PATH."
    exit 0
fi

if [ "$TERMINAL_APP" = "iTerm" ] || [ "$TERMINAL_APP" = "iTerm2" ]; then
    osascript >/dev/null 2>&1 <<EOF
tell application "iTerm"
    activate
    set targetSession to missing value
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if name of s contains "$(escape "$TAB_TITLE")" then set targetSession to s
            end repeat
        end repeat
    end repeat
    if targetSession is not missing value then
        select targetSession
    else
        set newWindow to (create window with default profile)
        tell current session of newWindow
            set name to "$(escape "$TAB_TITLE")"
            write text "$(escape "$RESUME")"
        end tell
    end if
end tell
EOF
    exit 0
fi

# Terminal.app: reuse the tab carrying this session's marker, if one is still
# open, rather than stacking up a new window per click.
osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
    activate
    set foundTab to missing value
    set foundWindow to missing value
    repeat with w in windows
        repeat with t in tabs of w
            if (custom title of t as string) is "$(escape "$TAB_TITLE")" then
                set foundTab to t
                set foundWindow to w
            end if
        end repeat
    end repeat
    if foundTab is not missing value then
        set selected of foundTab to true
        set index of foundWindow to 1
    else
        set newTab to do script "$(escape "$RESUME")"
        set custom title of newTab to "$(escape "$TAB_TITLE")"
    end if
end tell
EOF
