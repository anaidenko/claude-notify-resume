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

# The click can land long after the banner was sent — the folder may have been
# renamed, unmounted, or cleaned up if it was temporary.
if [ ! -d "$CWD" ]; then
    osascript -e "display notification \"$(printf '%s' "$CWD" | sed 's/\\/\\\\/g; s/"/\\"/g')\" with title \"Session folder is gone\" sound name \"Basso\"" >/dev/null 2>&1
    exit 0
fi

RESUME="cd $(printf '%q' "$CWD") && claude --resume $(printf '%q' "$SESSION_ID")"
# Marks the tab so a later click can find it instead of opening a duplicate.
TAB_TITLE="claude:$SESSION_ID"

escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Which terminal to drive. Terminal.app is the safe default: it is always
# present, whereas iTerm and VS Code may not be installed.
TERMINAL_APP="${CLAUDE_NOTIFY_TERMINAL:-Terminal}"

if [ "$TERMINAL_APP" = "vscode" ] || [ "$TERMINAL_APP" = "code" ]; then
    # VS Code has no scriptable terminal, so this opens the folder and leaves
    # the resume command on the clipboard rather than pretending otherwise.
    # `code` is installed by "Shell Command: Install 'code' command in PATH".
    if command -v code >/dev/null 2>&1; then
        # VS Code focuses an existing window for this folder; -n avoids hijacking
        # an unrelated window when the folder is not open anywhere.
        code --new-window "$CWD" >/dev/null 2>&1
        printf '%s' "$RESUME" | pbcopy 2>/dev/null
        osascript -e 'display notification "Resume command copied — paste it into the VS Code terminal." with title "Session opened in VS Code"' >/dev/null 2>&1
        exit 0
    fi
    osascript -e 'display notification "Install it via Shell Command: Install code command in PATH." with title "VS Code CLI not found"' >/dev/null 2>&1
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
