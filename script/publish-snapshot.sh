#!/bin/sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
npm run ci
cd publish
npm version "$(node -p 'require("./package.json").version')-snapshot.$(date -u +%Y%m%d%H%M%S)" --no-git-tag-version
npm publish --tag snapshot --access public --registry=https://registry.npmjs.org
