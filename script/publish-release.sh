#!/bin/sh
set -eu
ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
[ -z "$(git status --porcelain)" ] || { printf 'Commit changes before publishing.\n' >&2; exit 1; }
npm run ci
npm publish ./publish --access public --registry=https://registry.npmjs.org
VERSION="$(node -p 'require("./package.json").version')"
sh script/verify-package.sh "$VERSION"
printf 'Published %s. Create the GitHub release and tag after verification.\n' "$VERSION"
