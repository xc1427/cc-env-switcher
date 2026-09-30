#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
BASE_PNG="$BUILD_DIR/AppIcon-1024.png"
OUTPUT_ICNS="$ROOT_DIR/Packaging/macOS/AppIcon.icns"

mkdir -p "$BUILD_DIR"
swift "$ROOT_DIR/script/generate-app-icon.swift" "$BASE_PNG"

if [ -e "$ICONSET_DIR" ]; then mv "$ICONSET_DIR" "$ICONSET_DIR.previous.$(date +%s).$$"; fi
mkdir -p "$ICONSET_DIR"

cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"

printf '%s\n' "$OUTPUT_ICNS"
