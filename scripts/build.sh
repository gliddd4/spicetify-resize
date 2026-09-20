#!/bin/sh
#
# build.sh — compile the injected library.
#
# Produces dist/libnomin.dylib, ad-hoc signed. Ad-hoc is sufficient because
# Spotify carries com.apple.security.cs.disable-library-validation, so it does
# not require the library to be signed by its own team.

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB_SRC="$REPO_ROOT/src/nomin.m"
LAUNCH_SRC="$REPO_ROOT/src/launcher.c"
OUT_DIR="$REPO_ROOT/dist"
LIB_OUT="$OUT_DIR/libnomin.dylib"
LAUNCH_OUT="$OUT_DIR/SpotifyResizable"

if ! command -v clang >/dev/null 2>&1; then
	echo "error: clang not found. Install the Xcode command line tools:" >&2
	echo "  xcode-select --install" >&2
	exit 1
fi

for f in "$LIB_SRC" "$LAUNCH_SRC"; do
	[ -f "$f" ] || { echo "error: $f not found" >&2; exit 1; }
done

mkdir -p "$OUT_DIR"

echo "building $LIB_OUT"

# -fobjc-arc keeps the runtime calls correct; -O2 because this runs in the host
# app's address space and should cost it nothing measurable.
clang \
	-dynamiclib \
	-fobjc-arc \
	-O2 \
	-fvisibility=hidden \
	-framework Cocoa \
	-o "$LIB_OUT" \
	"$LIB_SRC"

echo "building $LAUNCH_OUT"

# The launcher is a compiled binary, not a shell script, precisely so it can be
# code signed. See the comment at the top of src/launcher.c.
clang \
	-O2 \
	-arch "$(uname -m)" \
	-o "$LAUNCH_OUT" \
	"$LAUNCH_SRC"

# Signing is required on Apple Silicon and harmless on Intel. Without it, dyld
# refuses to load the library on arm64.
codesign --force --sign - "$LIB_OUT"

# This one is not optional. An unsigned main executable gets killed by taskgated
# with "Taskgated Invalid Signature" as soon as macOS re-evaluates it, which is
# how the original script-based shim failed.
codesign --force --sign - "$LAUNCH_OUT"

echo
echo "built:"
ls -la "$LIB_OUT" "$LAUNCH_OUT"
echo
echo "=== library signature ==="
codesign -dv "$LIB_OUT" 2>&1 | sed -n '1,3p'
echo
echo "=== launcher signature ==="
codesign -dv "$LAUNCH_OUT" 2>&1 | sed -n '1,3p'
