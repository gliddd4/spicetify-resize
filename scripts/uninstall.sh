#!/bin/sh
#
# uninstall.sh — restore Spotify to stock.
#
# Puts CFBundleExecutable back to "Spotify" and removes the launch shim. The
# real Spotify binary was never modified, so there is nothing to restore there.
#
# Usage:  sh scripts/uninstall.sh [path/to/Spotify.app]

set -eu

INSTALL_DIR="$HOME/.spotify-resizer"
PLIST_BACKUP="$INSTALL_DIR/Info.plist.orig"
SHIM_NAME="SpotifyLauncher"
REAL_BIN_NAME="Spotify"

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
PLIST="$SPOTIFY_APP/Contents/Info.plist"
MACOS_DIR="$SPOTIFY_APP/Contents/MacOS"
SHIM="$MACOS_DIR/$SHIM_NAME"

say() { printf '%s\n' "$*"; }

[ -d "$SPOTIFY_APP" ] || { printf 'error: Spotify not found at %s\n' "$SPOTIFY_APP" >&2; exit 1; }
[ -f "$PLIST" ] || { printf 'error: no Info.plist at %s\n' "$PLIST" >&2; exit 1; }

if pgrep -f "^$SPOTIFY_APP/Contents/MacOS/$REAL_BIN_NAME( |\$)" >/dev/null 2>&1; then
	say "NOTE: Spotify is running. Quit it before the change takes effect:"
	say "      osascript -e 'quit app \"Spotify\"'"
	say ""
fi

current_exec=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || echo "")

if [ "$current_exec" = "$REAL_BIN_NAME" ]; then
	say "Already stock (CFBundleExecutable = $REAL_BIN_NAME)."
else
	say "CFBundleExecutable is '$current_exec' — restoring."

	# Prefer the byte-exact backup. It also carries any other plist keys the
	# user or another tool may have set before we ran.
	if [ -f "$PLIST_BACKUP" ] && \
	   [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST_BACKUP" 2>/dev/null || echo "")" = "$REAL_BIN_NAME" ]; then
		cp "$PLIST_BACKUP" "$PLIST"
		say "  restored $PLIST from backup"
	else
		/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $REAL_BIN_NAME" "$PLIST"
		say "  set CFBundleExecutable in place (no usable backup found)"
	fi
fi

if [ -f "$SHIM" ]; then
	rm -f "$SHIM"
	say "  removed $SHIM"
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
	"$LSREGISTER" -f "$SPOTIFY_APP" || true
	say "  re-registered with LaunchServices"
fi

# The library is inert without the shim, but remove it on request.
if [ "${KEEP_LIBRARY:-0}" != "1" ] && [ -d "$INSTALL_DIR" ]; then
	rm -rf "$INSTALL_DIR"
	say "  removed $INSTALL_DIR"
else
	say "  kept $INSTALL_DIR (KEEP_LIBRARY=1)"
fi

say ""
say "Current state:"
say "  CFBundleExecutable : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
say "  shim present       : $([ -f "$SHIM" ] && echo yes || echo no)"
say ""
say "Restart Spotify:"
say "  osascript -e 'quit app \"Spotify\"' && sleep 2 && open -a Spotify"
say ""
say "The code signature is not byte-for-byte restorable, because modifying and"
say "re-signing a bundle rewrites it. This only affects 'codesign --verify'."
say "Spotify runs normally, and a Spotify update or reinstall restores the"
say "original signature."
