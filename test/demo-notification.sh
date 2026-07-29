#!/usr/bin/env bash
# Send one real notification, marked as a test, to see what the banner looks
# like without waiting for a hook to fire.
#
#   ./test/demo-notification.sh                 # "Replied"
#   ./test/demo-notification.sh "Permission needed"
#
# Uses this repo's own session transcript when there is one, so the banner
# carries a realistic chat name rather than a placeholder.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATUS="${1:-Replied}"

# Any recent transcript will do — this is a demo, not a test of a given session.
TRANSCRIPT="$(find "$HOME/.claude/projects" -name '*.jsonl' -type f -print0 2>/dev/null |
    xargs -0 ls -t 2>/dev/null | head -1)"

if [ -n "$TRANSCRIPT" ]; then
    printf 'Using transcript: %s\n' "$TRANSCRIPT"
else
    printf 'No transcript found — the banner will fall back to the directory name.\n'
    TRANSCRIPT=""
fi

printf '{"session_id":"demo","transcript_path":"%s","cwd":"%s"}' "$TRANSCRIPT" "$REPO_ROOT" |
    CLAUDE_NOTIFY_TEST=1 "$REPO_ROOT/scripts/notify.sh" "$STATUS"

printf 'Sent. The banner is prefixed "TEST ·" so it is never mistaken for a real one.\n'
