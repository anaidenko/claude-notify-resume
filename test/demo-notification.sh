#!/usr/bin/env bash
# Send one notification, exactly as a hook would, to see the real banner.
#
#   ./test/demo-notification.sh                      # "Replied"
#   ./test/demo-notification.sh "Permission needed"  # any status
#   ./test/demo-notification.sh Replied --test       # prefixed "TEST ·"
#
#   CLAUDE_NOTIFY_DEMO_CHAT="Fix the geofence rounding bug" \
#     ./test/demo-notification.sh                    # choose the chat name
#
# The banner is indistinguishable from a real one — that is the point: it is
# what you would screenshot for a README. Set CLAUDE_NOTIFY_DEMO_CHAT when the
# newest transcript's title is not what you want in the picture. Pass --test to
# mark it visibly instead (e.g. while debugging alongside live sessions).
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS="${1:-Replied}"
MARK_AS_TEST=0
[ "${2:-}" = "--test" ] && MARK_AS_TEST=1

# An explicit chat name skips transcript lookup entirely — dispatch takes the
# name as an argument, so no transcript is involved.
if [ -n "${CLAUDE_NOTIFY_DEMO_CHAT:-}" ]; then
    [ "$MARK_AS_TEST" -eq 1 ] && STATUS="TEST · $STATUS"
    # Banners are grouped per session, and macOS *replaces* one already on
    # screen from the same group. Demoing several in a row therefore needs a
    # distinct id each time, or only the last one is ever seen.
    DEMO_ID="demo-$(printf '%s' "$CLAUDE_NOTIFY_DEMO_CHAT" | cksum | cut -d' ' -f1)"

    # Keep the demo out of the real click state: with the icon bundle installed,
    # dispatch records the session it just announced, and a demo would leave a
    # `demo-…` id there — so clicking Show on a genuine pending banner
    # afterwards would try to resume a session that never existed. The bundle
    # still has to be visible for the banner to look real, so copy it across.
    DEMO_STATE="$(mktemp -d)"
    if [ -d "$HOME/.claude/claude-code-notify/Claude Code.app" ]; then
        cp -R "$HOME/.claude/claude-code-notify/Claude Code.app" "$DEMO_STATE/" 2>/dev/null
    fi
    trap 'rm -rf "$DEMO_STATE"' EXIT
    export CLAUDE_NOTIFY_STATE_DIR="$DEMO_STATE"

    case "$(uname -s)" in
        Darwin) "$REPO_ROOT/scripts/notify-macos.sh" "$STATUS" "$CLAUDE_NOTIFY_DEMO_CHAT" "$DEMO_ID" "$REPO_ROOT" ;;
        Linux) "$REPO_ROOT/scripts/notify-linux.sh" "$STATUS" "$CLAUDE_NOTIFY_DEMO_CHAT" ;;
        *) printf 'Unsupported platform: %s\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    printf 'Sent: %s / %s\n' "$STATUS" "$CLAUDE_NOTIFY_DEMO_CHAT"
    exit 0
fi

# A demo is only convincing with a real chat name, so borrow the most recently
# updated transcript. `ls -t` sorts per xargs batch, which picks the wrong file
# once there are thousands of them — sort by mtime across the whole set.
TRANSCRIPT="$(find "$HOME/.claude/projects" -name '*.jsonl' -type f -exec stat -f '%m %N' {} + 2>/dev/null |
    sort -rn | head -1 | cut -d' ' -f2-)"

# `stat -f` is BSD; fall back to GNU syntax on Linux.
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT="$(find "$HOME/.claude/projects" -name '*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null |
        sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [ -n "$TRANSCRIPT" ]; then
    CHAT="$(node "$REPO_ROOT/scripts/notify-parse.js" <<<"{\"session_id\":\"demo\",\"transcript_path\":\"$TRANSCRIPT\",\"cwd\":\"$REPO_ROOT\"}" 2>/dev/null | sed -n 4p)"
    printf 'Chat name: %s\n' "${CHAT:-(none found — falling back to the directory name)}"
else
    printf 'No transcript found — the banner will show the directory name.\n'
    TRANSCRIPT=""
fi

if [ "$MARK_AS_TEST" -eq 1 ]; then
    printf '{"session_id":"demo","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$REPO_ROOT" |
        CLAUDE_NOTIFY_TEST=1 "$REPO_ROOT/scripts/notify.sh" "$STATUS"
    printf 'Sent, prefixed "TEST ·".\n'
else
    printf '{"session_id":"demo","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$REPO_ROOT" |
        "$REPO_ROOT/scripts/notify.sh" "$STATUS"
    printf 'Sent — a real banner, identical to what a hook produces.\n'
fi
