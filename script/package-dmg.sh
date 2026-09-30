#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARTIFACTS_DIR="$BUILD_DIR/artifacts"
STAGING_DIR="$BUILD_DIR/dmg-staging"
APP_NAME="${APP_NAME:-cc-env-switcher}"
DMG_PATH="$ARTIFACTS_DIR/$APP_NAME.dmg"

APP_BUNDLE="$("$ROOT_DIR/script/build-macos-app.sh")"

mkdir -p "$ARTIFACTS_DIR"
if [ -e "$STAGING_DIR" ]; then mv "$STAGING_DIR" "$STAGING_DIR.previous.$(date +%s).$$"; fi
mkdir -p "$STAGING_DIR"

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
cp "$ROOT_DIR/README.md" "$STAGING_DIR/"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

printf '%s\n' "$DMG_PATH"
