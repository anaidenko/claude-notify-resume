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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON="$(dirname "$SCRIPT_DIR")/assets/claude-logo.png"

# Build the whole argument list rather than a separate ICON_ARGS array: an
# empty array expanded under `set -u` aborts on bash < 4.4, which is what
# macOS still ships.
ARGS=(--app-name="Claude Code")
[ -f "$ICON" ] && ARGS+=(--icon "$ICON")
ARGS+=("$STATUS" "$CHAT")

notify-send "${ARGS[@]}" >/dev/null 2>&1 || true
exit 0
