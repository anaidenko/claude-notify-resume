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

# A click runs with a minimal PATH — the same trap notify.sh works around.
# Without this, `code` and `terminal-notifier` are both missing and the handler
# reports them as "not installed" on a machine where they plainly are.
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

RESUME="cd $(printf '%q' "$CWD") && claude --resume $(printf '%q' "$SESSION_ID")"

# Find the tab already running this session, if any, so a second click focuses
# it instead of opening a duplicate. Match on the running process rather than
# the tab title: Claude Code overwrites the title with the chat's own name, so
# a marker written there does not survive.
EXISTING_TTY="$(ps ax -o tty=,command= 2>/dev/null |
    awk -v id="$SESSION_ID" '$0 ~ ("claude --resume " id) { print $1; exit }')"

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

# shellcheck source=scripts/load-config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/load-config.sh"

# Which app to drive. The detected host (CLAUDE_NOTIFY_HOST, resolved from the
# process tree at notify time — TERM_PROGRAM is empty in the hook environment)
# picks iTerm over Terminal so the session lands in the terminal you use.
#
# VS Code is deliberately NOT followed here: it has no scriptable terminal, so
# the best it could do is open the folder and leave you to paste the command.
# Resuming the conversation is the point, so a VS Code host still gets a real
# terminal. `CLAUDE_NOTIFY_TERMINAL=vscode` opts back into folder-only.
HOST="${CLAUDE_NOTIFY_HOST:-}"
[ "$HOST" = "vscode" ] && HOST="Terminal"
TERMINAL_APP="${CLAUDE_NOTIFY_TERMINAL:-${HOST:-Terminal}}"

if [ "$TERMINAL_APP" = "vscode" ] || [ "$TERMINAL_APP" = "code" ]; then
    # VS Code has no scriptable terminal, so this opens the folder and leaves
    # the resume command on the clipboard rather than pretending otherwise.
    # `code` is installed by "Shell Command: Install 'code' command in PATH".
    if command -v code >/dev/null 2>&1; then
        # No flag: VS Code raises the window already holding this folder, and
        # opens a new one only when none has it. -n would always create a new
        # window; -r would hijack whichever window was last active.
        code "$CWD" >/dev/null 2>&1
        printf '%s' "$RESUME" | pbcopy 2>/dev/null
        notify "Session opened in VS Code" "Resume command copied — paste it into the terminal." "Glass"
        exit 0
    fi
    notify "VS Code CLI not found" "Install it via Shell Command: Install 'code' command in PATH."
    exit 0
fi

if [ "$TERMINAL_APP" = "iTerm" ] || [ "$TERMINAL_APP" = "iTerm2" ]; then
    if [ -n "$EXISTING_TTY" ]; then
        osascript >/dev/null 2>&1 <<EOF
tell application "iTerm"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if (tty of s as string) is "/dev/$(escape "$EXISTING_TTY")" then
                    select s
                    select t
                    return
                end if
            end repeat
        end repeat
    end repeat
end tell
EOF
        exit 0
    fi
    osascript >/dev/null 2>&1 <<EOF
tell application "iTerm"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow to write text "$(escape "$RESUME")"
end tell
EOF
    exit 0
fi

# Terminal.app: focus the tab already running this session — matched by tty,
# which is stable — rather than stacking up a window per click.
if [ -n "$EXISTING_TTY" ]; then
    osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            if (tty of t as string) is "/dev/$(escape "$EXISTING_TTY")" then
                set selected of t to true
                set index of w to 1
                return
            end if
        end repeat
    end repeat
end tell
EOF
    exit 0
fi

osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
    activate
    do script "$(escape "$RESUME")"
end tell
EOF
