# Contributing

Requires macOS 13+, Swift 5.10+, and Node.js 20+. Xcode or the Command Line Tools must provide both macOS architecture SDKs for a universal release.

## Structure

- `Sources/CCEnvSwitcherCore`: profile storage, target adapters, previews, backups and apply logic.
- `Sources/CCEnvSwitcherApp`: SwiftUI views and view model.
- `Sources/CCEnvSwitcherExecutable`: app entry point.
- `Tests`: core and app regression tests.
- `Packaging/macOS`: bundle metadata and icon sources.
- `bin`: npm launcher; `script`: build, packaging and release commands.

The interface is in English. Architecture and engineering notes use Chinese. Test with temporary target paths or Debug Mode; never use real credentials in fixtures.

## Test and build

```sh
npm ci --ignore-scripts
swift test
npm run assemble
node --test Tests/*.test.cjs
npm run build:dmg
```

`npm run ci` runs Swift tests, assembles the universal app/npm package, and verifies the packaged launcher and bundle. `build/artifacts/cc-env-switcher.app` is the native output; `publish/` is the only directory published to npm. The repository root is marked private to prevent publishing source by mistake.

Build products are ignored. Build scripts move old artifacts aside instead of deleting them. App version comes from `package.json`.

## Release

For later versions, use `npm run changeset` and `npm run version-packages` to update the version and changelog, then commit. No AI CLI is needed for releases.

```sh
npm login --registry=https://registry.npmjs.org --auth-type=web
npm run publish:release
```

The release script requires a clean working tree, runs checks, publishes `publish/`, then installs the released version into a temporary directory and verifies its bundle/signature/architectures. Publishing may require interactive 2FA. After successful verification, tag the source commit and create a GitHub Release with the DMG and checksums. Never overwrite an existing published version.

For a prerelease: `npm run publish:snapshot`. For a local tarball check:

```sh
npm pack ./publish --pack-destination /tmp
sh script/verify-package.sh /tmp/cc-env-switcher-0.1.0.tgz
```

The verification script does not launch an app or touch live settings. Perform interactive checks separately using isolated profiles and Debug Mode.

See [macOS distribution](docs/macos-distribution.md) for signing limitations.
