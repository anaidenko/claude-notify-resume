#!/usr/bin/env bash
# Build the tiny .app bundle that gives the banner its Claude icon (macOS takes
# the banner icon from the sending application, and ignores terminal-notifier's
# -appIcon/-contentImage for that slot). The npx installer runs it on macOS,
# from the installed copy, so nobody has to type this path.
#
#   setup-macos-icon.sh            build it, then send a test banner
#   setup-macos-icon.sh remove     delete it (banners keep working, no icon)
#
# The app posts natively and receives its own clicks, so with it installed
# banners need neither terminal-notifier nor AppleScript. Without it they still
# work, through terminal-notifier (clickable, no Claude icon) or AppleScript
# (neither).
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

# Before anything is deleted: a missing compiler must not cost a working app.
# `command -v swiftc` alone proves nothing — /usr/bin/swiftc is a shim present
# on every Mac, and without the tools it pops an install dialog and fails.
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swiftc >/dev/null 2>&1; then
    printf 'The Xcode Command Line Tools are missing. Install them first:\n' >&2
    printf '    xcode-select --install\n' >&2
    exit 1
fi

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
printf '  compiling the notifier app (first run takes ~30s)…\n'
if ! swiftc -O -o "$APP/Contents/MacOS/claude-notify" "$PLUGIN_ROOT/scripts/claude-notify.swift" 2>&1 | sed 's/^/    /'; then
    # A half-built bundle would stop the hooks from offering setup again.
    rm -rf "$APP"
    printf 'compilation failed — the notifier app was not built.\n' >&2
    exit 1
fi
touch "$APP"

# Marks this as the compiled bundle; notify-macos.sh refuses to `post` through
# the older script-only one, which would misread the argument. The content says
# the binary reports a refused post in its exit status: an empty marker is a
# pre-1.3.1 build that exits 0 regardless, so the caller cannot trust it.
printf '2\n' >"$APP/Contents/Resources/native-notifier"

# An unsigned bundle is refused when macOS tries to launch it from a notification
# click — silently, with no error anywhere. An ad-hoc signature (`-s -`) is enough;
# it needs no developer account, and without it the Show button does nothing.
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

# Launch Services must know the bundle, or usernoted refuses its posts.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP" >/dev/null 2>&1 || true

printf '  ✓ built %s: banners get the Claude icon, and a click reopens the chat\n' "$APP"

# The first post from a new app makes macOS ask whether it may notify; the post
# waits for that answer. Its exit status is the verdict (claude-notify.swift):
# 0 posted, 3 refused as a client, 4 switched off by the user. So the
# permission walk-through is printed only when it is needed.
printf '  sending a test banner (if macOS asks, choose Allow)…\n'
rc=0
"$APP/Contents/MacOS/claude-notify" post "TEST · Notifications are on" \
    "Claude Code will notify you here." >/dev/null 2>&1 || rc=$?
SETTINGS='open "x-apple.systempreferences:com.apple.preference.notifications"'
case "$rc" in
    0)
        printf '  ✓ sent. Not on screen? Check Focus, or System Settings → Notifications → Claude Code.\n'
        ;;
    4)
        printf '\n  ! Notifications from "Claude Code" are switched off, so banners stay\n'
        printf '    silent. Turn on "Allow notifications" for it in System Settings →\n'
        printf '    Notifications:  %s\n' "$SETTINGS"
        ;;
    *)
        printf '\n  ! macOS refused the test banner (status %s). The hooks re-register the\n' "$rc"
        printf '    app and retry on each banner, and fall back to plain banners meanwhile.\n'
        ;;
esac
