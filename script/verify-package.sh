#!/bin/sh
set -eu
VERSION="${1:?Usage: verify-package.sh <version-or-tarball>}"
VERIFY_DIR="$(mktemp -d /tmp/cc-env-switcher-verify.XXXXXX)"
case "$VERSION" in /*|*.tgz) SPEC="$VERSION" ;; *) SPEC="cc-env-switcher@$VERSION" ;; esac
npm install --prefix "$VERIFY_DIR" --ignore-scripts --no-audit --no-fund --registry=https://registry.npmjs.org "$SPEC"
PKG="$VERIFY_DIR/node_modules/cc-env-switcher"
node "$PKG/bin/cc-env-switcher.js" --version
node "$PKG/bin/cc-env-switcher.js" --help
codesign --verify --deep --strict "$PKG/cc-env-switcher.app"
lipo "$PKG/cc-env-switcher.app/Contents/MacOS/cc-env-switcher" -verify_arch arm64 x86_64
test -f "$PKG/LICENSE"
printf 'Verified installation: %s\n' "$VERIFY_DIR"
