#!/bin/sh
#
# launch-debug.sh — start Spotify with the helper loaded, debug logging on, and
# a Chrome DevTools Protocol port open.
#
# The in-bundle shim does not forward a debug port, and `open --args` does not
# forward arguments through a script-based CFBundleExecutable. So for inspecting
# or driving the Spotify UI, launch the real binary directly instead.
#
# Usage:  sh scripts/launch-debug.sh [port]      (default 9222)
# Then:   curl -s http://127.0.0.1:9222/json/version

set -eu

INSTALL_DIR="$HOME/.spotify-resizer"
LIB="$INSTALL_DIR/libnomin.dylib"
REAL_BIN_NAME="Spotify"

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"
BIN="$SPOTIFY_APP/Contents/MacOS/$REAL_BIN_NAME"
PORT="${1:-9222}"

[ -f "$LIB" ] || { printf 'error: no library at %s — run install.sh first\n' "$LIB" >&2; exit 1; }
[ -x "$BIN" ] || { printf 'error: no Spotify binary at %s\n' "$BIN" >&2; exit 1; }

if pgrep -f "^$SPOTIFY_APP/Contents/MacOS/$REAL_BIN_NAME( |\$)" >/dev/null 2>&1; then
	printf 'Spotify is already running. Quit it first:\n' >&2
	printf '  osascript -e '"'"'quit app "Spotify"'"'"'\n' >&2
	exit 1
fi

DYLD_INSERT_LIBRARIES="$LIB"
SPOTIFY_RESIZER_DEBUG=1
export DYLD_INSERT_LIBRARIES SPOTIFY_RESIZER_DEBUG

printf 'starting Spotify with helper + debug logging + CDP on port %s\n' "$PORT"
printf 'CDP endpoint: http://127.0.0.1:%s/json/version\n\n' "$PORT"

exec "$BIN" --remote-debugging-port="$PORT"
