#!/bin/sh
#
# uninstall.sh — remove the resize patch.
#
# Deletes the launcher app and the injected library. Spotify.app is not modified
# by the current design, so there is nothing to restore there; this also cleans
# up after the older in-bundle shim in case one is still present.
#
# Usage:  sh scripts/uninstall.sh [path/to/Spotify.app]

set -eu

INSTALL_DIR="$HOME/.spotify-resizer"
APP_DEST="$HOME/Applications/Spotify Resizable.app"
REAL_BIN_NAME="Spotify"
SHIM_NAME="SpotifyLauncher"

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
PLIST="$SPOTIFY_APP/Contents/Info.plist"
SHIM="$SPOTIFY_APP/Contents/MacOS/$SHIM_NAME"

say() { printf '%s\n' "$*"; }

[ -d "$SPOTIFY_APP" ] || { printf 'error: Spotify not found at %s\n' "$SPOTIFY_APP" >&2; exit 1; }

if pgrep -f "^$SPOTIFY_APP/Contents/MacOS/$REAL_BIN_NAME( |\$)" >/dev/null 2>&1; then
	say "NOTE: Spotify is running. Quit it before the change takes effect:"
	say "      osascript -e 'quit app \"Spotify\"'"
	say ""
fi

# ---- launcher app (current design)

if [ -d "$APP_DEST" ]; then
	rm -rf "$APP_DEST"
	say "  removed $APP_DEST"
fi

# ---- in-bundle shim (older design, in case it is still around)

current_exec=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || echo "")

if [ "$current_exec" = "$SHIM_NAME" ]; then
	if [ -f "$INSTALL_DIR/Info.plist.orig" ]; then
		cp "$INSTALL_DIR/Info.plist.orig" "$PLIST"
		say "  restored $PLIST from backup"
	else
		/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $REAL_BIN_NAME" "$PLIST"
		say "  set CFBundleExecutable back to $REAL_BIN_NAME in place"
	fi
	[ -f "$SHIM" ] && rm -f "$SHIM" && say "  removed $SHIM"
fi

# ---- library

if [ "${KEEP_LIBRARY:-0}" = "1" ]; then
	say "  kept $INSTALL_DIR (KEEP_LIBRARY=1)"
elif [ -d "$INSTALL_DIR" ]; then
	rm -rf "$INSTALL_DIR"
	say "  removed $INSTALL_DIR"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ] && [ -d "$SPOTIFY_APP" ]; then
	"$LSREGISTER" -f "$SPOTIFY_APP" || true
	say "  re-registered with LaunchServices"
fi

say ""
say "Current state:"
say "  CFBundleExecutable : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || echo '?')"
say "  in-bundle shim     : $([ -f "$SHIM" ] && echo present || echo absent)"
say "  launcher app       : $([ -d "$APP_DEST" ] && echo present || echo absent)"
say ""
say "Restart Spotify from Spotify.app — it will run stock, at its normal 800x600"
say "minimum."
