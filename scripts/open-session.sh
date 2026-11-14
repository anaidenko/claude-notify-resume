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
# CLAUDE_NOTIFY_BIN first so the test suite can shadow `code`, `osascript` and
# `terminal-notifier` — the Homebrew paths below deliberately outrank whatever
# the caller had, so a plain PATH prepend cannot win.
PATH="${CLAUDE_NOTIFY_BIN:+$CLAUDE_NOTIFY_BIN:}/opt/homebrew/bin:/usr/local/bin:$PATH"
export PATH

RESUME="cd $(printf '%q' "$CWD") && claude --resume $(printf '%q' "$SESSION_ID")"

# Find the tab already running this session, if any, so a second click focuses
# it instead of opening a duplicate. Match on the running process rather than
# the tab title: Claude Code overwrites the title with the chat's own name, so
# a marker written there does not survive.
# Both spellings occur: a shell resume writes `--resume <id>`, while the VS Code
# extension spawns `--resume=<id>`. Matching only the space form silently missed
# every editor-hosted session.
# A session can show up more than once: the VS Code extension spawns a copy with
# no controlling terminal, which `ps` prints as `??`, alongside the real tab. The
# `??` row sorts first, so taking the first match found a tty that can never own
# a tab — the lookup then failed and every click opened another window while the
# real tab sat there. Skip the ttyless rows and take the first genuine one.
EXISTING_TTY="$(ps ax -o tty=,command= 2>/dev/null |
    awk -v id="$SESSION_ID" '$1 != "??" && $0 ~ ("--resume[= ]" id) { print $1; exit }')"

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
HOST="${CLAUDE_NOTIFY_HOST:-}"

# A session from the VS Code extension reopens as its own tab in its own window,
# through the extension's URL handler. It never runs a second process in a
# terminal. The host is vscode:<window>:<extension host pid>, because VS Code
# sends the URL to its last active window unless windowId names one. In another
# project's window the extension opens a new, empty session instead. Focusing
# the right window first does not fix that: it raced, and lost one time in
# three.
vscode_tab() {
    local rest window exthost
    rest="${HOST#vscode:}"
    window="${rest%%:*}"
    exthost="${rest#*:}"
    case "$window" in '' | *[!0-9]*) return 1 ;; esac
    case "$exthost" in '' | *[!0-9]*) return 1 ;; esac
    # The extension silently ignores an id containing `/`, `\` or `..`. Such a
    # click would do nothing at all, so it goes to a terminal instead.
    case "$SESSION_ID" in *[!A-Za-z0-9-]*) return 1 ;; esac
    # Is it still the same window? Its extension host must be alive. A dead one
    # means the window closed or VS Code restarted, and the ids may now name
    # other windows.
    case "$(ps -o comm= -p "$exthost" 2>/dev/null)" in
        *"Code Helper"*) ;;
        *) return 1 ;;
    esac
    open "vscode://anthropic.claude-code/open?session=$SESSION_ID&windowId=$window" >/dev/null 2>&1
}

# TERMINAL forces a terminal, as documented, even over a detected editor.
if [ -z "${CLAUDE_NOTIFY_TERMINAL:-}" ]; then
    case "$HOST" in
        vscode:*:*) vscode_tab && exit 0 ;;
    esac
fi

# Everything else that is editor-hosted resumes in a terminal: a CLI in VS
# Code's integrated terminal (no window id, and no tab to return to), Insiders
# (untested), or a window that is gone. Opening the folder alone would not
# resume the conversation.
case "$HOST" in vscode*) HOST="Terminal" ;; esac
TERMINAL_APP="${CLAUDE_NOTIFY_TERMINAL:-${HOST:-Terminal}}"

if [ "$TERMINAL_APP" = "iTerm" ] || [ "$TERMINAL_APP" = "iTerm2" ]; then
    if [ -n "$EXISTING_TTY" ]; then
        FOCUSED="$(osascript 2>/dev/null <<EOF
tell application "iTerm"
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                if (tty of s as string) is "/dev/$(escape "$EXISTING_TTY")" then
                    select s
                    select t
                    activate
                    return "yes"
                end if
            end repeat
        end repeat
    end repeat
    return "no"
end tell
EOF
)"
        [ "$FOCUSED" = "yes" ] && exit 0
    fi
    # Same startup-window story as Terminal: launching iTerm opens one window
    # already, so only create another when iTerm was running before us. Probed
    # with `pgrep` for the reason spelled out at the Terminal branch below.
    # The process is `iTerm2` even though the app is `iTerm`, so an -x match on
    # the app name finds nothing and every start would look cold.
    pgrep -x iTerm2 >/dev/null 2>&1 && ITERM_WAS_RUNNING=true || ITERM_WAS_RUNNING=false
    if [ "$ITERM_WAS_RUNNING" = "true" ]; then
        osascript >/dev/null 2>&1 <<EOF
tell application "iTerm"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow to write text "$(escape "$RESUME")"
end tell
EOF
    else
        osascript >/dev/null 2>&1 <<EOF
tell application "iTerm"
    activate
    try
        tell current session of current window to write text "$(escape "$RESUME")"
    on error
        set newWindow to (create window with default profile)
        tell current session of newWindow to write text "$(escape "$RESUME")"
    end try
end tell
EOF
    fi
    exit 0
fi

# Terminal.app: focus the tab already running this session — matched by tty,
# which is stable — rather than stacking up a window per click.
# A tty may exist without any tab of this app owning it — the session could be
# running under a different terminal, inside tmux, or in the VS Code extension.
# Report whether a tab was actually focused, and fall through to opening a new
# window when it was not; otherwise the click activates the app and does nothing.
if [ -n "$EXISTING_TTY" ]; then
    FOCUSED="$(osascript 2>/dev/null <<EOF
tell application "Terminal"
    repeat with w in windows
        repeat with t in tabs of w
            if (tty of t as string) is "/dev/$(escape "$EXISTING_TTY")" then
                set selected of t to true
                set index of w to 1
                activate
                return "yes"
            end if
        end repeat
    end repeat
    return "no"
end tell
EOF
)"
    [ "$FOCUSED" = "yes" ] && exit 0
fi

# Launching Terminal creates its startup window; a `do script` on top of that
# yields a pair — one empty, one ours. When Terminal was not already running,
# run the command in that startup window instead.
#
# The obvious probe, `application "Terminal" is running`, answers from the
# caller's Launch Services session, and the click handler runs in the same
# stripped environment as the hook — there it reports `false` for a Terminal
# that is plainly on screen, so the cold-start branch fired on a warm start and
# produced the empty window it exists to prevent. `pgrep` asks the kernel for a
# process and is not subject to that; it does not launch anything either.
pgrep -x Terminal >/dev/null 2>&1 && TERMINAL_WAS_RUNNING=true || TERMINAL_WAS_RUNNING=false
if [ "$TERMINAL_WAS_RUNNING" = "true" ]; then
    osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
    activate
    do script "$(escape "$RESUME")"
end tell
EOF
else
    osascript >/dev/null 2>&1 <<EOF
tell application "Terminal"
    activate
    try
        do script "$(escape "$RESUME")" in front window
    on error
        do script "$(escape "$RESUME")"
    end try
end tell
EOF
fi
