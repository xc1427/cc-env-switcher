# cc-env-switcher

A native macOS app for switching Claude Code environment profiles. Preview each change, apply it to Terminal, Visual Studio Code, and Claude Code, and keep backups of the files you change.

**macOS 13+ · Apple Silicon and Intel · MIT**

## Install

With Node.js 20 or later:

```sh
npm install -g cc-env-switcher
cc-env-switcher
```

Or download the DMG from [GitHub Releases](https://github.com/xc1427/cc-env-switcher/releases) and drag the app to Applications. The npm package includes the native app: no Swift compiler, build step, or install script is required.

The app is ad-hoc signed, **not Apple-notarized**. macOS may block a downloaded app on first launch. Review the source and release before deciding whether to allow it in System Settings → Privacy & Security. Building from source is also supported.

## Use

1. Open the app and choose **Reveal Profile in Finder...**. Profiles live in `~/.config/cc-env-switcher/profiles/`.
2. Add one JSON file per provider/configuration. The filename is the profile's ID. Keep `index.json` (schema version metadata).
3. Refresh profiles, select one, and review the per-target preview.
4. Click **Apply**, inspect the confirmation, and confirm.
5. Open a new shell session, reload VS Code, and restart Claude Code to pick up the changes.

Example `my-provider.json`:

```json
{
  "description": "My Anthropic-compatible provider",
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.example.com",
    "ANTHROPIC_AUTH_TOKEN": "replace-with-your-token",
    "ANTHROPIC_API_KEY": "",
    "ANTHROPIC_MODEL": "your-provider-model-id"
  }
}
```

Profiles and backups can contain credentials. Keep them private; do not commit them to Git. The generated sample is a template, not a working account.

## What changes

| Target | Managed data |
| --- | --- |
| Terminal | Adds a `source ~/.config/cc-env-switcher/env.sh` line to `~/.zshrc`; writes exports to that `env.sh` |
| VS Code | Updates `claudeCode.environmentVariables` in `~/Library/Application Support/Code/User/settings.json` |
| Claude Code | Updates the `env` object in `~/.claude/settings.json` |

Only `ANTHROPIC_*`, `CLAUDE_CODE_*`, and `API_TIMEOUT_MS` are managed. **A profile overlays the keys it declares; existing keys omitted from that profile are retained.** Set an explicit empty string when that is the provider's intended value. Other VS Code settings and Claude Code hooks/permissions are preserved. Cursor is not read or modified.

The app warns about conflicting managed exports in `.zshrc`. Remove those manually once you have reviewed them. Existing files are backed up before writes under `~/.config/cc-env-switcher/backups/`, with manifests describing each apply operation. The last-applied state is updated only when all targets succeed. Writes across targets are not a transaction: inspect failures and backups if a target cannot be written.

**Debug Mode** redirects configuration targets to files under the app's `debug/` directory. It is useful for trying previews and backups without applying to your live targets.

`CC_ENV_SWITCHER_HOME` or `XDG_CONFIG_HOME` can override profile/state/backup storage. The live shell export file remains `~/.config/cc-env-switcher/env.sh`.

## Develop

Requires macOS and a Swift 5.10+ toolchain (Xcode / Command Line Tools).

```sh
swift test
npm run build:app
npm run assemble
node --test Tests/*.test.cjs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [architecture](docs/ARCHITECTURE.md).

## License

[MIT](LICENSE).
