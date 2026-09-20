#!/bin/sh
#
# status.sh — report whether the resize patch is currently in effect.
#
# Useful after a Spotify update, which silently reverts everything.
#
# Usage:  sh scripts/status.sh [path/to/Spotify.app]

set -eu

INSTALL_DIR="$HOME/.spotify-resizer"
LIB="$INSTALL_DIR/libnomin.dylib"
SHIM_NAME="SpotifyLauncher"
REAL_BIN_NAME="Spotify"

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
PLIST="$SPOTIFY_APP/Contents/Info.plist"
SHIM="$SPOTIFY_APP/Contents/MacOS/$SHIM_NAME"
RELAUNCHER="$SPOTIFY_APP/Contents/MacOS/sp_relauncher"

ok()   { printf '  %-22s %s\n' "$1" "$2"; }

if [ ! -d "$SPOTIFY_APP" ]; then
	printf 'Spotify not found at %s\n' "$SPOTIFY_APP" >&2
	exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo "?")
exec_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST" 2>/dev/null || echo "?")

printf 'Spotify %s  (%s)\n\n' "$version" "$SPOTIFY_APP"

if [ "$exec_name" = "$SHIM_NAME" ]; then
	ok "launch shim" "installed (CFBundleExecutable = $SHIM_NAME)"
else
	ok "launch shim" "NOT installed (CFBundleExecutable = $exec_name)"
fi

if [ -f "$SHIM" ]; then
	ok "shim file" "present"
else
	ok "shim file" "missing"
fi

if [ -f "$LIB" ]; then
	ok "helper library" "present at $LIB"
else
	ok "helper library" "missing"
fi

pid=$(pgrep -f "^$SPOTIFY_APP/Contents/MacOS/$REAL_BIN_NAME( |\$)" 2>/dev/null | head -1 || true)
if [ -n "$pid" ]; then
	if lsof -p "$pid" 2>/dev/null | grep -q libnomin; then
		ok "running process" "pid $pid, helper LOADED"
	else
		ok "running process" "pid $pid, helper NOT loaded"
	fi
else
	ok "running process" "not running"
fi

if [ -f "$RELAUNCHER" ]; then
	if [ -x "$RELAUNCHER" ]; then
		ok "auto-updates" "enabled (sp_relauncher executable)"
	else
		ok "auto-updates" "blocked (sp_relauncher not executable)"
	fi
fi

printf '\n'
if [ "$exec_name" = "$SHIM_NAME" ] && [ -f "$SHIM" ] && [ -f "$LIB" ]; then
	printf 'Patch is installed. Restart Spotify if the running process has no helper.\n'
else
	printf 'Patch is NOT fully installed. Run: sh scripts/install.sh\n'
fi
