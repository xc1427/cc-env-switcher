import Foundation

package struct DebugTargetSeeder {
    private let fileManager: FileManager

    package init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    package func seed(at paths: AppPaths) throws {
        try write(text: zshrcContents(envFileURL: paths.managedShellEnvironmentURL), to: paths.zshrcURL)
        try write(text: envContents(), to: paths.managedShellEnvironmentURL)
        try write(data: vscodeSettingsData(), to: paths.vscodeSettingsURL)
        try write(data: claudeSettingsData(), to: paths.claudeSettingsURL)
    }

    private let baselineEnvironmentEntries: [EnvironmentEntry] = [
        EnvironmentEntry(name: "API_TIMEOUT_MS", value: "30000000"),
        EnvironmentEntry(name: "ANTHROPIC_API_KEY", value: ""),
        EnvironmentEntry(name: "ANTHROPIC_AUTH_TOKEN", value: "<set-me>"),
        EnvironmentEntry(name: "ANTHROPIC_BASE_URL", value: "https://ai-gateway.vercel.sh"),
        EnvironmentEntry(name: "ANTHROPIC_DEFAULT_HAIKU_MODEL", value: "anthropic/claude-haiku-4.5"),
        EnvironmentEntry(name: "ANTHROPIC_DEFAULT_OPUS_MODEL", value: "anthropic/claude-opus-4.6"),
        EnvironmentEntry(name: "ANTHROPIC_DEFAULT_SONNET_MODEL", value: "anthropic/claude-sonnet-4.6"),
        EnvironmentEntry(name: "ANTHROPIC_SMALL_FAST_MODEL", value: "anthropic/claude-sonnet-4.6"),
        EnvironmentEntry(name: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", value: "1")
    ]

    private func zshrcContents(envFileURL: URL) -> String {
        """
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        export EDITOR="code -w"
        export HISTSIZE="5000"
        alias ll="ls -lah"
        alias gs="git status -sb"
        source "\(envFileURL.path)"
        """
    }

    private func envContents() -> String {
        let envLines = baselineEnvironmentEntries.map { entry in
            #"export \#(entry.name)="\#(shellEscape(entry.value))""#
        }.joined(separator: "\n")

        return """
        # Baseline debug environment for backup verification.
        # This file intentionally includes unrelated content so backups prove full-file preservation.
        export DEBUG_BASELINE_MARKER="keep-me"
        export PATH="/opt/homebrew/bin:$PATH"
        \(envLines)
        """
    }

    private func vscodeSettingsData() throws -> Data {
        try jsonData(from: [
            "editor.fontSize": 14,
            "editor.tabSize": 2,
            "files.autoSave": "onFocusChange",
            "terminal.integrated.fontSize": 13,
            "window.commandCenter": true,
            "workbench.colorTheme": "Default Light Modern",
            "claudeCode.environmentVariables": baselineEnvironmentEntries.map(environmentObject)
        ])
    }

    private func claudeSettingsData() throws -> Data {
        let env = Dictionary(uniqueKeysWithValues: baselineEnvironmentEntries.map { ($0.name, $0.value) })
        return try jsonData(from: [
            "env": env,
            "model": "sonnet",
            "permissions": [
                "defaultMode": "acceptEdits",
                "deny": [
                    "Read(**/.env)",
                    "Bash(rm -rf *)"
                ]
            ],
            "hooks": [
                "Notification": [
                    [
                        "matcher": "*",
                        "hooks": [
                            [
                                "type": "command",
                                "command": "/usr/bin/true"
                            ]
                        ]
                    ]
                ]
            ]
        ])
    }

    private func environmentObject(_ entry: EnvironmentEntry) -> [String: String] {
        [
            "name": entry.name,
            "value": entry.value
        ]
    }

    private func jsonData(from object: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func write(text: String, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        try Data(normalized.utf8).write(to: url, options: .atomic)
    }

    private func write(data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }

    private func shellEscape(_ value: String) -> String {
        value.replacingOccurrences(of: #"\"#, with: #"\\\"#)
    }
}
