#!/usr/bin/env bash
# Build the tiny .app bundle that gives the banner its Claude icon (macOS takes
# the banner icon from the sending application, and ignores terminal-notifier's
# -appIcon/-contentImage for that slot). Part of the macOS setup.
#
#   setup-macos-icon.sh            build it, then send a test banner
#   setup-macos-icon.sh remove     delete it (banners keep working, no icon)
#
# Notifications still work without it — the plugin falls back to the terminal's
# own icon, and then the whole banner is clickable, because the -sender flag that
# carries a custom icon also swallows the body click. With the bundle installed,
# "Show" is how you resume.
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
    <!-- Ask for alerts, which stay on screen until dismissed, rather than
         banners that vanish after ~5s — the whole point is to catch you while
         you are looking elsewhere. macOS honours this only when it first
         registers the bundle; afterwards the user's System Settings choice
         wins. -->
    <key>NSUserNotificationAlertStyle</key><string>alert</string>
</dict>
</plist>
PLIST

# The executable is a small compiled binary (scripts/claude-notify.swift): it
# posts the notification natively and receives the click as a real app delegate.
# A fake script-only bundle spoofed via -sender failed four undocumented ways in
# one day — launch refusal, stale daemon bindings, delivery-time launches — and
# swallowed the body click by design. A real app has none of those problems.
if ! command -v swiftc >/dev/null 2>&1; then
    printf 'swiftc not found — install the Xcode Command Line Tools first:\n' >&2
    printf '    xcode-select --install\n' >&2
    exit 1
fi
printf '  compiling the notifier binary (first run takes ~30s)…\n'
if ! swiftc -O -o "$APP/Contents/MacOS/claude-notify" "$PLUGIN_ROOT/scripts/claude-notify.swift" 2>&1 | sed 's/^/    /'; then
    printf 'compilation failed — the icon bundle was not built.\n' >&2
    exit 1
fi
touch "$APP"

# Marks this as the compiled bundle; notify-macos.sh refuses to `post` through
# the older script-only one, which would misread the argument.
touch "$APP/Contents/Resources/native-notifier"

# An unsigned bundle is refused when macOS tries to launch it from a notification
# click — silently, with no error anywhere. An ad-hoc signature (`-s -`) is enough;
# it needs no developer account, and without it the Show button does nothing.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

# Launch Services must know the bundle or -sender silently falls back.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

printf '  ✓ built %s\n' "$APP"

printf '\n  ! Banners now carry the Claude icon, and clicking anywhere on one\n'
printf '    reopens that chat — the bundle posts natively and receives its own\n'
printf '    clicks. Run this script with "remove" to go back to plain banners.\n'

if ! command -v terminal-notifier >/dev/null 2>&1; then
    printf '\n  ! terminal-notifier is missing — install it:  brew install terminal-notifier\n'
    exit 0
fi

printf '\n  ! One manual step: System Settings → Notifications → "Claude Code"\n'
printf '    → turn ON "Allow notifications". A new app starts switched off, and\n'
printf '    macOS then discards its banners with no error and exit code 0.\n'
printf '    While you are there, set the style to "Alerts" so notifications stay\n'
printf '    on screen instead of vanishing after a few seconds.\n'
printf '    Open it with:  open "x-apple.systempreferences:com.apple.preference.notifications"\n'

"$APP/Contents/MacOS/claude-notify" post "TEST · Notifications are on" \
    "Claude Code will notify you here." >/dev/null 2>&1 || true
printf '\n  → Sent a test banner. If you did NOT see it, the permission above is\n'
printf '    still off — delivery cannot be detected from a script, so this is\n'
printf '    the only real check.\n'
