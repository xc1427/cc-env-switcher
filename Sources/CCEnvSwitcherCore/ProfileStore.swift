import Foundation

package final class ProfileStore {
    private let fileManager: FileManager
    private let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    package init(paths: AppPaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        let decoder = JSONDecoder()
        self.decoder = decoder
    }

    package func ensureBootstrapFiles() throws {
        try migrateLegacyStorageIfNeeded()
        try fileManager.createDirectory(at: paths.applicationSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.backupDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.profilesDirectoryURL, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: paths.profilesIndexURL.path) {
            try normalizeEscapedSlashesInBootstrapProfileIfNeeded()
            return
        }

        try writeConfiguration(makeBootstrapConfiguration())
    }

    package func loadConfiguration() throws -> ProfileConfiguration {
        try ensureBootstrapFiles()

        let indexData = try Data(contentsOf: paths.profilesIndexURL)
        let index = try decoder.decode(ProfileIndex.self, from: indexData)
        let profiles = try loadProfiles()
        let configuration = ProfileConfiguration(
            version: index.version,
            profiles: profiles
        )
        try validate(configuration)
        return configuration
    }

    package func loadState(stateURL: URL? = nil) -> AppState {
        let targetStateURL = stateURL ?? paths.stateURL

        guard fileManager.fileExists(atPath: targetStateURL.path) else {
            return AppState(lastAppliedProfileId: nil, lastAppliedAt: nil)
        }

        do {
            let data = try Data(contentsOf: targetStateURL)
            return try decoder.decode(AppState.self, from: data)
        } catch {
            return AppState(lastAppliedProfileId: nil, lastAppliedAt: nil)
        }
    }

    package func saveState(_ state: AppState, stateURL: URL? = nil) throws {
        let targetStateURL = stateURL ?? paths.stateURL
        try ensureBootstrapFiles()
        try fileManager.createDirectory(at: targetStateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: targetStateURL, options: .atomic)
    }

    private func migrateLegacyStorageIfNeeded() throws {
        let legacyDirectory = legacyApplicationSupportDirectory()
        guard legacyDirectory.standardizedFileURL != paths.applicationSupportDirectory.standardizedFileURL else {
            return
        }

        guard fileManager.fileExists(atPath: legacyDirectory.path) else {
            return
        }

        guard !fileManager.fileExists(atPath: paths.applicationSupportDirectory.path) else {
            return
        }

        try fileManager.createDirectory(
            at: paths.applicationSupportDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try fileManager.moveItem(at: legacyDirectory, to: paths.applicationSupportDirectory)
        } catch {
            try fileManager.copyItem(at: legacyDirectory, to: paths.applicationSupportDirectory)
            try? fileManager.removeItem(at: legacyDirectory)
        }
    }

    private func loadProfiles() throws -> [ClaudeProfile] {
        let profileURLs = try fileManager
            .contentsOfDirectory(at: paths.profilesDirectoryURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != paths.profilesIndexURL.lastPathComponent }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try profileURLs.map { url in
            let data = try Data(contentsOf: url)
            var profile = try decoder.decode(ClaudeProfile.self, from: data)
            profile.id = url.deletingPathExtension().lastPathComponent
            return profile
        }
    }

    private func makeBootstrapConfiguration() -> ProfileConfiguration {
        ProfileConfiguration(
            version: 1,
            profiles: [
                ClaudeProfile(
                    id: "vercel-ai-gateway",
                    description: "Sample remote Anthropic-compatible provider",
                    env: [
                        "API_TIMEOUT_MS": "30000000",
                        "ANTHROPIC_API_KEY": "",
                        "ANTHROPIC_BASE_URL": "https://ai-gateway.vercel.sh",
                        "ANTHROPIC_AUTH_TOKEN": "<set-me>",
                        "ANTHROPIC_SMALL_FAST_MODEL": "anthropic/claude-sonnet-4.6",
                        "ANTHROPIC_DEFAULT_OPUS_MODEL": "anthropic/claude-opus-4.6",
                        "ANTHROPIC_DEFAULT_SONNET_MODEL": "anthropic/claude-sonnet-4.6",
                        "ANTHROPIC_DEFAULT_HAIKU_MODEL": "anthropic/claude-haiku-4.5",
                        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                        "NON_SENSE_ENV_VAR": "foo"
                    ]
                )
            ]
        )
    }

    private func writeConfiguration(_ configuration: ProfileConfiguration) throws {
        let index = ProfileIndex(version: configuration.version)
        let indexData = try encoder.encode(index)
        try indexData.write(to: paths.profilesIndexURL, options: .atomic)

        for profile in configuration.profiles {
            let profileData = try encoder.encode(profile)
            let profileURL = paths.profilesDirectoryURL.appendingPathComponent("\(profile.id).json")
            // 索引丢失时只补齐引导文件，不覆盖用户已经保存的 profile。
            if !fileManager.fileExists(atPath: profileURL.path) {
                try profileData.write(to: profileURL, options: .atomic)
            }
        }
    }

    private func normalizeEscapedSlashesInBootstrapProfileIfNeeded() throws {
        let bootstrapProfileURL = paths.profilesDirectoryURL.appendingPathComponent("vercel-ai-gateway.json")
        guard fileManager.fileExists(atPath: bootstrapProfileURL.path) else {
            return
        }

        let existing = try String(contentsOf: bootstrapProfileURL, encoding: .utf8)
        guard existing.contains("\\/") else {
            return
        }

        let normalized = existing.replacingOccurrences(of: "\\/", with: "/")
        guard normalized != existing else {
            return
        }

        let output = normalized.hasSuffix("\n") ? normalized : normalized + "\n"
        try Data(output.utf8).write(to: bootstrapProfileURL, options: .atomic)
    }

    private func validate(_ configuration: ProfileConfiguration) throws {
        guard configuration.version == 1 else {
            throw ValidationError(message: "Unsupported profile schema version: \(configuration.version)")
        }

        var seenIDs = Set<String>()
        for profile in configuration.profiles {
            guard !profile.id.isEmpty else {
                throw ValidationError(message: "A profile is missing its id.")
            }

            guard seenIDs.insert(profile.id).inserted else {
                throw ValidationError(message: "Duplicate profile id '\(profile.id)'.")
            }
        }
    }

    private func legacyApplicationSupportDirectory() -> URL {
        paths.homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("cc-env-switcher", isDirectory: true)
    }
}

struct ValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
