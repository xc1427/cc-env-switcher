import Foundation

package struct AppPaths {
    package let homeDirectory: URL
    package let applicationSupportDirectory: URL
    package let profilesDirectoryURL: URL
    package let profilesIndexURL: URL
    package let stateURL: URL
    package let backupDirectoryURL: URL
    package let zshrcURL: URL
    package let managedShellEnvironmentURL: URL
    package let vscodeSettingsURL: URL
    package let claudeSettingsURL: URL

    package var debugTargetsDirectoryURL: URL {
        applicationSupportDirectory.appendingPathComponent("debug", isDirectory: true)
    }

    package func withTargetFilesInDebugDirectory() -> AppPaths {
        let debugDirectoryURL = debugTargetsDirectoryURL
        return AppPaths(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            profilesDirectoryURL: profilesDirectoryURL,
            profilesIndexURL: profilesIndexURL,
            stateURL: debugDirectoryURL.appendingPathComponent("state.json"),
            backupDirectoryURL: backupDirectoryURL,
            zshrcURL: debugDirectoryURL.appendingPathComponent("debug.zshrc"),
            managedShellEnvironmentURL: debugDirectoryURL.appendingPathComponent("debug.env.sh"),
            vscodeSettingsURL: debugDirectoryURL.appendingPathComponent("debug.vscode.settings.json"),
            claudeSettingsURL: debugDirectoryURL.appendingPathComponent("debug.claude.settings.json")
        )
    }

    package static func live(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppPaths {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let appSupport = resolveStorageDirectory(homeDirectory: homeDirectory, environment: environment)

        return AppPaths(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: appSupport,
            profilesDirectoryURL: appSupport.appendingPathComponent("profiles", isDirectory: true),
            profilesIndexURL: appSupport.appendingPathComponent("profiles/index.json"),
            stateURL: appSupport.appendingPathComponent("state.json"),
            backupDirectoryURL: appSupport.appendingPathComponent("backups", isDirectory: true),
            zshrcURL: homeDirectory.appendingPathComponent(".zshrc"),
            managedShellEnvironmentURL: homeDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh"),
            vscodeSettingsURL: homeDirectory.appendingPathComponent("Library/Application Support/Code/User/settings.json"),
            claudeSettingsURL: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
    }

    package static func resolveStorageDirectory(
        homeDirectory: URL,
        environment: [String: String]
    ) -> URL {
        if let explicitHome = resolveDirectoryPath(
            environmentValue: environment["CC_ENV_SWITCHER_HOME"],
            homeDirectory: homeDirectory
        ) {
            return explicitHome
        }

        if let xdgConfigHome = resolveDirectoryPath(
            environmentValue: environment["XDG_CONFIG_HOME"],
            homeDirectory: homeDirectory
        ) {
            return xdgConfigHome.appendingPathComponent("cc-env-switcher", isDirectory: true)
        }

        return homeDirectory.appendingPathComponent(".config/cc-env-switcher", isDirectory: true)
    }

    private static func resolveDirectoryPath(
        environmentValue: String?,
        homeDirectory: URL
    ) -> URL? {
        guard let rawValue = environmentValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }

        if rawValue == "~" {
            return homeDirectory.standardizedFileURL
        }

        if rawValue.hasPrefix("~/") {
            let relativePath = String(rawValue.dropFirst(2))
            return homeDirectory
                .appendingPathComponent(relativePath, isDirectory: true)
                .standardizedFileURL
        }

        if rawValue.hasPrefix("/") {
            return URL(fileURLWithPath: rawValue, isDirectory: true).standardizedFileURL
        }

        return homeDirectory
            .appendingPathComponent(rawValue, isDirectory: true)
            .standardizedFileURL
    }
}
