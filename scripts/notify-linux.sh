#!/usr/bin/env bash
# Linux banner via notify-send (libnotify).
#
# Verified against a real notification daemon over D-Bus (test/dbus-suite.sh),
# though not yet on a physical Linux desktop. Click-to-resume is deliberately
# omitted — notify-send has no portable click action, and the notification
# daemon varies by desktop environment.
set -uo pipefail

STATUS="$1"
CHAT="$2"

# Honour the test-stub directory here too: this script is also called directly,
# without notify.sh having set up PATH.
[ -n "${CLAUDE_NOTIFY_BIN:-}" ] && PATH="$CLAUDE_NOTIFY_BIN:$PATH" && export PATH

# Without libnotify nothing can be delivered. The notice goes to stderr, which
# Claude Code only surfaces when a hook exits non-zero — so in practice this is a
# breadcrumb for someone running the script by hand, not something the user will
# see. Exiting non-zero to force it would break the one rule this plugin has.
# The README states the dependency instead.
if ! command -v notify-send >/dev/null 2>&1; then
    NOTICE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-notify/missing-libnotify"
    if [ ! -f "$NOTICE" ]; then
        mkdir -p "$(dirname "$NOTICE")" 2>/dev/null &&
            : >"$NOTICE" 2>/dev/null &&
            printf 'claude-notify-resume: notify-send not found, so no banners will appear.\n  Install libnotify:  sudo apt install libnotify-bin   (or your distro'\''s package)\n  This notice is shown once.\n' >&2
    fi
    exit 0
fi

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
