#!/bin/sh
#
# build.sh — compile the injected library.
#
# Produces dist/libnomin.dylib, ad-hoc signed. Ad-hoc is sufficient because
# Spotify carries com.apple.security.cs.disable-library-validation, so it does
# not require the library to be signed by its own team.

set -eu

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$REPO_ROOT/src/nomin.m"
OUT_DIR="$REPO_ROOT/dist"
OUT="$OUT_DIR/libnomin.dylib"

if ! command -v clang >/dev/null 2>&1; then
	echo "error: clang not found. Install the Xcode command line tools:" >&2
	echo "  xcode-select --install" >&2
	exit 1
fi

if [ ! -f "$SRC" ]; then
	echo "error: $SRC not found" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"

echo "building $OUT"

# -fobjc-arc keeps the runtime calls correct; -O2 because this runs in the host
# app's address space and should cost it nothing measurable.
clang \
	-dynamiclib \
	-fobjc-arc \
	-O2 \
	-fvisibility=hidden \
	-framework Cocoa \
	-o "$OUT" \
	"$SRC"

# Signing is required on Apple Silicon and harmless on Intel. Without it, dyld
# refuses to load the library on arm64.
codesign --force --sign - "$OUT"

echo
echo "built:"
ls -la "$OUT"
echo
codesign -dv "$OUT" 2>&1 | sed -n '1,4p'
