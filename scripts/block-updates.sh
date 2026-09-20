#!/bin/sh
#
# block-updates.sh — stop Spotify from replacing its own app bundle.
#
# WHY THIS WORKS
#
# Spotify's macOS updater downloads a new .app and then hands the swap to a
# helper binary, Contents/MacOS/sp_relauncher. Inspecting the binaries shows
# sp_relauncher is the only one that knows how to do it:
#
#   replaceItemAtURL:withItemAtURL:backupItemName:options:resultingItemURL:error:
#   update_started   old-app-version   new-app-version   launch-updated-client
#
# The main Spotify binary contains none of those strings; it only references
# "sp_relauncher" by name. So removing the execute bit from sp_relauncher means
# the download can still happen but the swap cannot, and Spotify keeps running
# the version you have.
#
# WHY NOT THE OBVIOUS ALTERNATIVES
#
#   spicetify spotify-updates block
#       Reported "success" but left the binary byte-identical on Spotify
#       1.3.1.234. It is a find/replace against version-specific bytes that no
#       longer match, so it fails silently. Do not rely on it.
#
#   Making the app bundle read-only
#       Breaks `spicetify apply`, which writes into the bundle.
#
#   An in-app setting
#       None exists. Spotify's desktop client has no auto-update toggle, and no
#       "automatic update" string appears anywhere in the UI bundles.
#
# HOW MUCH TO TRUST THIS
#
# This is mechanism-based, not vendor-supported. It was verified to leave
# Spotify fully functional, but it cannot be verified to block an update without
# waiting for one to be released. If an update does slip through, the resize
# patch is reverted — re-run install.sh.
#
# Usage:  sh scripts/block-updates.sh [path/to/Spotify.app]

set -eu

SPOTIFY_APP="${1:-/Applications/Spotify.app}"
RELAUNCHER="$SPOTIFY_APP/Contents/MacOS/sp_relauncher"

say() { printf '%s\n' "$*"; }

[ -d "$SPOTIFY_APP" ] || { printf 'error: Spotify not found at %s\n' "$SPOTIFY_APP" >&2; exit 1; }
[ -f "$RELAUNCHER" ] || { printf 'error: no sp_relauncher at %s\n' "$RELAUNCHER" >&2; exit 1; }

if [ ! -x "$RELAUNCHER" ]; then
	say "Updates are already blocked (sp_relauncher is not executable)."
	exit 0
fi

chmod -x "$RELAUNCHER"
say "blocked: removed the execute bit from"
say "  $RELAUNCHER"
say ""
say "Spotify will keep running the version you have. To re-enable updates:"
say "  sh scripts/allow-updates.sh"
