#!/bin/sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PUBLISH_DIR="$ROOT_DIR/publish"
mkdir -p "$ROOT_DIR/build"
if [ -e "$PUBLISH_DIR" ]; then mv "$PUBLISH_DIR" "$ROOT_DIR/build/publish.previous.$(date +%s).$$"; fi
mkdir -p "$PUBLISH_DIR/bin"
APP_BUNDLE="$(sh "$ROOT_DIR/script/build-macos-app.sh")"
ditto "$APP_BUNDLE" "$PUBLISH_DIR/cc-env-switcher.app"
cp "$ROOT_DIR/bin/cc-env-switcher.js" "$PUBLISH_DIR/bin/"
chmod +x "$PUBLISH_DIR/bin/cc-env-switcher.js"
cp "$ROOT_DIR/README.md" "$ROOT_DIR/LICENSE" "$ROOT_DIR/CHANGELOG.md" "$PUBLISH_DIR/"
node - "$ROOT_DIR" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const root = process.argv[2];
const source = require(path.join(root, 'package.json'));
const pkg = Object.fromEntries(['name', 'version', 'description', 'license', 'author', 'repository', 'homepage', 'bugs', 'engines', 'publishConfig'].map(key => [key, source[key]]));
pkg.os = ['darwin'];
pkg.cpu = ['arm64', 'x64'];
pkg.bin = { 'cc-env-switcher': 'bin/cc-env-switcher.js' };
pkg.files = ['bin/', 'cc-env-switcher.app/', 'README.md', 'LICENSE', 'CHANGELOG.md'];
fs.writeFileSync(path.join(root, 'publish/package.json'), JSON.stringify(pkg, null, 2) + '\n');
NODE
printf 'Assembled %s\n' "$PUBLISH_DIR"
