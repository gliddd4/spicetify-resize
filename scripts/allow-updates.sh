#!/bin/sh
#
# allow-updates.sh — re-enable Spotify's auto-updates.
#
# Restores the execute bit on sp_relauncher. See block-updates.sh for why that
# binary is the lever.
#
# Usage:  sh scripts/allow-updates.sh [path/to/Spotify.app]

set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
RELAUNCHER="$SPOTIFY_APP/Contents/MacOS/sp_relauncher"

say() { printf '%s\n' "$*"; }

[ -d "$SPOTIFY_APP" ] || { printf 'error: Spotify not found at %s\n' "$SPOTIFY_APP" >&2; exit 1; }
[ -f "$RELAUNCHER" ] || { printf 'error: no sp_relauncher at %s\n' "$RELAUNCHER" >&2; exit 1; }

if [ -x "$RELAUNCHER" ]; then
	say "Updates are already enabled."
	exit 0
fi

chmod +x "$RELAUNCHER"
say "enabled: restored the execute bit on"
say "  $RELAUNCHER"
say ""
say "Heads up: the next Spotify update will replace the app bundle and revert"
say "the resize patch. Re-run install.sh afterwards."
