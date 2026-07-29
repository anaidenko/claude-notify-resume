#!/usr/bin/env bash
# Linux banner via notify-send (libnotify).
#
# UNVERIFIED: written from the notify-send interface, not exercised on a Linux
# desktop. Click-to-resume is deliberately omitted — notify-send has no portable
# click action, and the notification daemon varies by desktop environment.
set -uo pipefail

STATUS="$1"
CHAT="$2"

command -v notify-send >/dev/null 2>&1 || exit 0

ICON_ARGS=()
ICON="$(dirname "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")")/assets/claude-logo.png"
[ -f "$ICON" ] && ICON_ARGS=(--icon "$ICON")

notify-send "${ICON_ARGS[@]}" --app-name="Claude Code" "$STATUS" "$CHAT" >/dev/null 2>&1 || true
exit 0
