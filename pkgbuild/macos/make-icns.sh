#!/bin/sh
# Regenerates pkgbuild/macos/Hype.icns from pkgbuild/hype.svg.
#
# Requires librsvg (rsvg-convert) and Apple's iconutil, both available with a
# standard macOS + Homebrew setup. The generated .icns is committed so builds
# do not depend on rsvg-convert; run this only when the SVG changes.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
SVG="$ROOT/pkgbuild/hype.svg"
OUT="$ROOT/pkgbuild/macos/Hype.icns"
ICONSET="$(mktemp -d)/Hype.iconset"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "rsvg-convert is required (brew install librsvg)" >&2
    exit 1
fi

mkdir -p "$ICONSET"
render() { rsvg-convert -w "$1" -h "$1" "$SVG" -o "$ICONSET/$2"; }
render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET" -o "$OUT"
echo "Wrote $OUT"
