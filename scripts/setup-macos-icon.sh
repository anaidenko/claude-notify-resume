#!/usr/bin/env bash
# Optional macOS extra: build the tiny .app bundle that gives the banner a
# Claude icon (macOS takes the banner icon from the sending application, and
# ignores terminal-notifier's -appIcon/-contentImage for that slot).
#
#   setup-macos-icon.sh            build it, then send a test banner
#   setup-macos-icon.sh remove     delete it (banners keep working, no icon)
#
# Notifications work without this — the icon is the only thing it buys, plus
# the click handler that -sender requires.
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$HOME/.claude/claude-code-notify"
APP="$STATE_DIR/Claude Code.app"
# macOS grants notification permission per bundle id, on that id's first ever
# appearance. Changing this string turns every existing install into a new,
# unapproved sender whose banners vanish with no error — keep it stable.
BUNDLE_ID="com.claude-code.notify"

[ "$(uname -s)" = "Darwin" ] || {
    printf 'This script is macOS-only (this is %s).\n' "$(uname -s)" >&2
    exit 1
}

if [ "${1:-}" = "remove" ]; then
    rm -rf "$APP" "$STATE_DIR/last-session"
    printf '  ✓ removed %s\n' "$APP"
    exit 0
fi

ICON="$PLUGIN_ROOT/assets/claude-logo.png"
[ -f "$ICON" ] || {
    printf 'Icon not found: %s\n' "$ICON" >&2
    exit 1
}

mkdir -p "$STATE_DIR"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

ICONSET="$(mktemp -d)/claude.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
    sips -z "$size" "$size" "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
done
cp "$ICONSET/icon_32x32.png" "$ICONSET/icon_16x16@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_64x64.png" "$ICONSET/icon_32x32@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png" 2>/dev/null || true
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/claude.icns"
rm -rf "$(dirname "$ICONSET")"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Code</string>
    <key>CFBundleDisplayName</key><string>Claude Code</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>claude-notify</string>
    <key>CFBundleIconFile</key><string>claude.icns</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

cat >"$APP/Contents/MacOS/claude-notify" <<'SH'
#!/bin/bash
# Clicking a banner launches this; it reopens the chat recorded by notify.sh.
STATE="$HOME/.claude/claude-code-notify/last-session"
[ -f "$STATE" ] || exit 0
SESSION_ID="$(sed -n 1p "$STATE")"
CWD="$(sed -n 2p "$STATE")"
[ -n "$SESSION_ID" ] && [ -d "$CWD" ] || exit 0
osascript \
    -e "tell application \"Terminal\" to do script \"cd $(printf '%q' "$CWD") && claude --resume $SESSION_ID\"" \
    -e 'tell application "Terminal" to activate'
SH
chmod +x "$APP/Contents/MacOS/claude-notify"
touch "$APP"

# Launch Services must know the bundle or -sender silently falls back.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

printf '  ✓ built %s\n' "$APP"

if ! command -v terminal-notifier >/dev/null 2>&1; then
    printf '\n  ! terminal-notifier is missing — install it:  brew install terminal-notifier\n'
    exit 0
fi

printf '\n  ! One manual step: System Settings → Notifications → "Claude Code"\n'
printf '    → turn ON "Allow notifications". A new app starts switched off, and\n'
printf '    macOS then discards its banners with no error and exit code 0.\n'
printf '    Open it with:  open "x-apple.systempreferences:com.apple.preference.notifications"\n'

terminal-notifier -title "TEST · Notifications are on" \
    -message "Claude Code will notify you here." \
    -sound Glass -sender "$BUNDLE_ID" >/dev/null 2>&1 || true
printf '\n  → Sent a test banner. If you did NOT see it, the permission above is\n'
printf '    still off — delivery cannot be detected from a script, so this is\n'
printf '    the only real check.\n'
