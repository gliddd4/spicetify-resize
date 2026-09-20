#!/bin/sh
#
# install.sh — make Spotify's window freely resizable.
#
# Spotify.app is NOT modified. This installs the injected library and builds a
# small launcher app that starts Spotify with that library loaded.
#
# Why a launcher app rather than editing Spotify: the obvious approach is to
# drop a shim inside Spotify.app and point CFBundleExecutable at it. That breaks
# Spotify's code signature seal, and macOS kills the process:
#
#   signal:      SIGKILL (Code Signature Invalid)
#   termination: CODESIGNING - "Taskgated Invalid Signature"
#   parentProc:  launchd
#
# It survives `open -a` testing and then dies on launchd-initiated launches,
# which is the worst possible failure: silent during testing, fatal at boot.
# A separate, self-consistent, signed bundle avoids it entirely.
#
# Usage:  sh scripts/install.sh [path/to/Spotify.app]

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB_SRC="$REPO_ROOT/dist/libnomin.dylib"
LAUNCH_SRC="$REPO_ROOT/dist/SpotifyResizable"
INSTALL_DIR="$HOME/.spotify-resizer"
LIB_DST="$INSTALL_DIR/libnomin.dylib"
APP_DEST="$HOME/Applications/Spotify Resizable.app"
APP_EXEC_NAME="SpotifyResizable"
ICON_NAME="AppIcon"

SPOTIFY_APP="${1:-/Applications/Spotify.app}"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- sanity checks

[ "$(uname -s)" = "Darwin" ] || fail "this only works on macOS"

[ -d "$SPOTIFY_APP" ] || fail "Spotify not found at $SPOTIFY_APP
Install it from https://www.spotify.com/download, or pass the path:
  sh scripts/install.sh /path/to/Spotify.app"

if [ -d "$SPOTIFY_APP/Contents/_MASReceipt" ]; then
	fail "this is a Mac App Store build of Spotify.
Spicetify and this tool cannot patch MAS builds. Reinstall Spotify from
https://www.spotify.com/download and run this again."
fi

[ -x "$SPOTIFY_APP/Contents/MacOS/Spotify" ] || fail "no Spotify binary in $SPOTIFY_APP/Contents/MacOS"

if [ ! -f "$LIB_SRC" ] || [ ! -f "$LAUNCH_SRC" ]; then
	say "build artifacts missing — building first."
	sh "$REPO_ROOT/scripts/build.sh" || fail "build failed"
fi

# --------------------------------------------------------- install the library

mkdir -p "$INSTALL_DIR"
cp "$LIB_SRC" "$LIB_DST"
chmod 644 "$LIB_DST"

if command -v codesign >/dev/null 2>&1; then
	codesign --force --sign - "$LIB_DST" >/dev/null 2>&1 || true
fi

# macOS quarantines anything downloaded. A quarantined dylib can be refused by
# dyld, which would silently produce a normal, unresizable Spotify.
xattr -d com.apple.quarantine "$LIB_DST" 2>/dev/null || true

say "installed library: $LIB_DST"

# ----------------------------------------------------- build the launcher .app

say "building launcher: $APP_DEST"

rm -rf "$APP_DEST"
mkdir -p "$APP_DEST/Contents/MacOS" "$APP_DEST/Contents/Resources"

cp "$LAUNCH_SRC" "$APP_DEST/Contents/MacOS/$APP_EXEC_NAME"
chmod 755 "$APP_DEST/Contents/MacOS/$APP_EXEC_NAME"

# Use Spotify's own icon so the launcher is recognisable in the Dock.
if [ -f "$SPOTIFY_APP/Contents/Resources/AppIcon.icns" ]; then
	cp "$SPOTIFY_APP/Contents/Resources/AppIcon.icns" "$APP_DEST/Contents/Resources/$ICON_NAME.icns"
fi

cat > "$APP_DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Spotify Resizable</string>
	<key>CFBundleExecutable</key>
	<string>$APP_EXEC_NAME</string>
	<key>CFBundleIconFile</key>
	<string>$ICON_NAME</string>
	<key>CFBundleIdentifier</key>
	<string>local.spotify.resizable</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Spotify Resizable</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.music</string>
	<key>LSMinimumSystemVersion</key>
	<string>10.15</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# Sign the whole bundle. Without this, taskgated rejects it the same way it
# rejected the in-bundle shim.
codesign --force --sign - "$APP_DEST" || say "WARNING: codesign failed — the launcher may be killed at launch"

if codesign -dv "$APP_DEST" 2>&1 | grep -q "Signature=adhoc"; then
	say "launcher signed : yes (ad-hoc)"
else
	say "WARNING: launcher has NO signature. macOS will likely kill it at launch."
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
	"$LSREGISTER" -f "$APP_DEST" || true
	say "re-registered with LaunchServices"
fi

# ---------------------------------------------------------------------- done

say ""
say "Done. Spotify.app was not modified."
say ""
say "IMPORTANT - avoid a second Dock icon:"
say "  Drag '$APP_DEST' into your Dock and REMOVE the existing Spotify icon."
say "  Launch Spotify through this app, not through Spotify.app directly."
say ""
say "Verify:"
say "  sh scripts/status.sh"
say ""
say "Note: Spotify updates replace the bundle and undo this. Re-run install.sh"
say "after updating, or run scripts/block-updates.sh to stop them."
