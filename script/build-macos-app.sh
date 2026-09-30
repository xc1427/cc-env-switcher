#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARTIFACTS_DIR="$BUILD_DIR/artifacts"
APP_NAME="${APP_NAME:-cc-env-switcher}"
EXECUTABLE_NAME="cc-env-switcher"
APP_VERSION="${APP_VERSION:-$(node -p "require(process.argv[1]).version" "$ROOT_DIR/package.json")}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-io.github.xc1427.cc-env-switcher}"
PLIST_TEMPLATE="$ROOT_DIR/Packaging/macOS/Info.plist"
APP_BUNDLE="$ARTIFACTS_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SIGNED_IDENTITY="${CODE_SIGN_IDENTITY:--}"
ICON_GENERATOR="$ROOT_DIR/script/generate-app-icon.sh"
ICON_SOURCE="$ROOT_DIR/Packaging/macOS/AppIcon.svg"
ICON_OUTPUT="$ROOT_DIR/Packaging/macOS/AppIcon.icns"

mkdir -p "$ARTIFACTS_DIR"
if [ -e "$APP_BUNDLE" ]; then mv "$APP_BUNDLE" "$APP_BUNDLE.previous.$(date +%s).$$"; fi

if [ -f "$ICON_SOURCE" ] && [ -x "$ICON_GENERATOR" ]; then
  if [ ! -f "$ICON_OUTPUT" ] || [ "$ICON_SOURCE" -nt "$ICON_OUTPUT" ] || [ "$ICON_GENERATOR" -nt "$ICON_OUTPUT" ]; then
    "$ICON_GENERATOR" >/dev/null
  fi
fi

swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE_NAME" >/dev/null
BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE_NAME" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$EXECUTABLE_NAME"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$PLIST_TEMPLATE" "$CONTENTS_DIR/Info.plist"
cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_IDENTIFIER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

if [ -f "$ICON_OUTPUT" ]; then
  cp "$ICON_OUTPUT" "$RESOURCES_DIR/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist"
fi

if [ "$SIGNED_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  codesign --force --deep --timestamp --options runtime --sign "$SIGNED_IDENTITY" "$APP_BUNDLE"
fi

printf '%s\n' "$APP_BUNDLE"
