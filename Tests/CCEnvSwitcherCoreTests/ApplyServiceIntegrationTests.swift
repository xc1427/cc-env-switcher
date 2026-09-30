import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class ApplyServiceIntegrationTests: XCTestCase {
    func testBootstrapCreatesSampleProfilesAndSupportDirectories() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = makePaths(in: rootDirectory)
        let store = ProfileStore(paths: paths)

        let configuration = try store.loadConfiguration()
        let indexJSON = try String(contentsOf: paths.profilesIndexURL, encoding: .utf8)

        XCTAssertEqual(configuration.version, 1)
        XCTAssertFalse(configuration.profiles.isEmpty)
        XCTAssertFalse(indexJSON.contains("defaultProfileId"))
        XCTAssertFalse(configuration.profiles.flatMap(\.env.keys).contains("ANTHROPIC_MODEL"))
        XCTAssertFalse(configuration.profiles.flatMap(\.managedEnvironment.keys).contains("ANTHROPIC_MODEL"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.backupDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.appendingPathComponent("profiles", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profilesIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.applicationSupportDirectory.appendingPathComponent("profiles/vercel-ai-gateway.json").path))

        let sampleProfileURL = paths.applicationSupportDirectory.appendingPathComponent("profiles/vercel-ai-gateway.json")
        let sampleProfileJSON = try String(contentsOf: sampleProfileURL, encoding: .utf8)
        XCTAssertTrue(sampleProfileJSON.contains("anthropic/claude-haiku-4.5"))
        XCTAssertTrue(sampleProfileJSON.contains("\"NON_SENSE_ENV_VAR\""))
        XCTAssertTrue(sampleProfileJSON.contains("\"foo\""))
        XCTAssertFalse(sampleProfileJSON.contains("\\/"))
        XCTAssertFalse(sampleProfileJSON.contains("\"id\""))
        XCTAssertFalse(sampleProfileJSON.contains("\"name\""))
    }

    func testApplyServiceHandlesPreviewApplyRemovalAndBackupsAcrossAllTargets() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = makePaths(in: rootDirectory)
        try seedInitialFiles(paths: paths)
        try writeConfiguration(makeConfiguration(), to: paths)

        let store = ProfileStore(paths: paths)
        let backupService = BackupService(backupDirectoryURL: paths.backupDirectoryURL)
        let claudeTarget = ClaudeSettingsTarget(fileURL: paths.claudeSettingsURL)
        let writers: [any TargetWriter] = [
            ZshrcTarget(fileURL: paths.zshrcURL, envFileURL: paths.managedShellEnvironmentURL),
            JSONCEnvironmentTarget(target: .vscode, fileURL: paths.vscodeSettingsURL),
            claudeTarget
        ]
        let service = ApplyService(
            writers: writers,
            backupService: backupService,
            profileStore: store
        )

        let configuration = try store.loadConfiguration()
        let alpha = try requireProfile(id: "alpha", from: configuration)
        let beta = try requireProfile(id: "beta", from: configuration)

        let preview = service.preview(profile: alpha)

        XCTAssertEqual(preview.count, 3)
        XCTAssertTrue(preview.contains(where: { $0.target == .terminal && $0.changes.contains(where: { $0.key == "ANTHROPIC_BASE_URL" && $0.kind == .updated }) }))

        let firstReport = service.apply(profile: alpha)

        XCTAssertEqual(firstReport.failureCount, 0)
        XCTAssertEqual(store.loadState().lastAppliedProfileId, "alpha")
        XCTAssertEqual(service.detectCurrentProfile(in: configuration.profiles), alpha)
        XCTAssertEqual(try backupFileNames(in: paths.backupDirectoryURL).count, 3)

        let zshrcAfterAlpha = try String(contentsOf: paths.zshrcURL, encoding: .utf8)
        let managedEnvAfterAlpha = try String(contentsOf: paths.managedShellEnvironmentURL, encoding: .utf8)
        XCTAssertTrue(zshrcAfterAlpha.contains("export PATH=\"/usr/bin\""))
        XCTAssertTrue(zshrcAfterAlpha.contains("source ~/.config/cc-env-switcher/env.sh"))
        XCTAssertTrue(managedEnvAfterAlpha.contains("export API_TIMEOUT_MS=\"30000000\""))
        XCTAssertTrue(managedEnvAfterAlpha.contains("export ANTHROPIC_BASE_URL=\"https://alpha.example\""))
        XCTAssertTrue(managedEnvAfterAlpha.contains("export ANTHROPIC_MODEL=\"alpha-sonnet\""))
        XCTAssertTrue(managedEnvAfterAlpha.contains("export ANTHROPIC_ORGANIZATION_ID=\"old-org\""))

        let vscodeAfterAlpha = try String(contentsOf: paths.vscodeSettingsURL, encoding: .utf8)
        XCTAssertTrue(vscodeAfterAlpha.contains("\"editor.fontSize\": 13"))
        XCTAssertTrue(vscodeAfterAlpha.contains("\"UNMANAGED_KEEP\""))
        XCTAssertTrue(vscodeAfterAlpha.contains("https://alpha.example"))


        let claudeObjectAfterAlpha = try loadJSONObject(at: paths.claudeSettingsURL)
        let claudeEnvAfterAlpha = claudeObjectAfterAlpha["env"] as? [String: String]
        XCTAssertEqual(claudeEnvAfterAlpha?["ANTHROPIC_BASE_URL"], "https://alpha.example")
        XCTAssertEqual(claudeEnvAfterAlpha?["ANTHROPIC_MODEL"], "alpha-sonnet")
        XCTAssertEqual(claudeEnvAfterAlpha?["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")

        let secondReport = service.apply(profile: beta)

        XCTAssertEqual(secondReport.failureCount, 0)
        XCTAssertEqual(store.loadState().lastAppliedProfileId, "beta")
        XCTAssertEqual(service.detectCurrentProfile(in: configuration.profiles), beta)
        XCTAssertEqual(try backupFileNames(in: paths.backupDirectoryURL).count, 6)

        let zshrcAfterBeta = try String(contentsOf: paths.zshrcURL, encoding: .utf8)
        let managedEnvAfterBeta = try String(contentsOf: paths.managedShellEnvironmentURL, encoding: .utf8)
        XCTAssertTrue(zshrcAfterBeta.contains("source ~/.config/cc-env-switcher/env.sh"))
        XCTAssertTrue(managedEnvAfterBeta.contains("export API_TIMEOUT_MS=\"5000\""))
        XCTAssertTrue(managedEnvAfterBeta.contains("export ANTHROPIC_MODEL=\"beta-sonnet\""))
        XCTAssertTrue(managedEnvAfterBeta.contains("export ANTHROPIC_ORGANIZATION_ID=\"example-org\""))
        XCTAssertTrue(managedEnvAfterBeta.contains("export ANTHROPIC_BASE_URL=\"https://alpha.example\""))

        let vscodeAfterBeta = try String(contentsOf: paths.vscodeSettingsURL, encoding: .utf8)
        XCTAssertTrue(vscodeAfterBeta.contains("\"ANTHROPIC_ORGANIZATION_ID\""))
        XCTAssertTrue(vscodeAfterBeta.contains("https://alpha.example"))
        XCTAssertTrue(vscodeAfterBeta.contains("\"UNMANAGED_KEEP\""))


        let claudeObjectAfterBeta = try loadJSONObject(at: paths.claudeSettingsURL)
        let claudeEnvAfterBeta = claudeObjectAfterBeta["env"] as? [String: String]
        XCTAssertEqual(claudeEnvAfterBeta?["API_TIMEOUT_MS"], "5000")
        XCTAssertEqual(claudeEnvAfterBeta?["ANTHROPIC_ORGANIZATION_ID"], "example-org")
        XCTAssertEqual(claudeEnvAfterBeta?["ANTHROPIC_MODEL"], "beta-sonnet")
        XCTAssertEqual(claudeEnvAfterBeta?["ANTHROPIC_BASE_URL"], "https://alpha.example")
        XCTAssertEqual(claudeEnvAfterBeta?["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")
    }

    func testApplyServiceWritesBackupManifestForEachTargetStatus() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = makePaths(in: rootDirectory)
        try seedInitialFiles(paths: paths)
        try writeConfiguration(makeConfiguration(), to: paths)

        let store = ProfileStore(paths: paths)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backupService = BackupService(
            backupDirectoryURL: paths.backupDirectoryURL,
            dateProvider: { fixedDate }
        )
        let claudeTarget = ClaudeSettingsTarget(fileURL: paths.claudeSettingsURL)
        let writers: [any TargetWriter] = [
            ZshrcTarget(fileURL: paths.zshrcURL, envFileURL: paths.managedShellEnvironmentURL),
            JSONCEnvironmentTarget(target: .vscode, fileURL: paths.vscodeSettingsURL),
            claudeTarget
        ]
        let service = ApplyService(
            writers: writers,
            backupService: backupService,
            profileStore: store
        )

        let configuration = try store.loadConfiguration()
        let alpha = try requireProfile(id: "alpha", from: configuration)

        _ = service.apply(profile: alpha)

        let runDirectoryURL = paths.backupDirectoryURL.appendingPathComponent(timestampString(from: fixedDate), isDirectory: true)
        let manifestURL = runDirectoryURL.appendingPathComponent("manifest.json")

        XCTAssertTrue(FileManager.default.fileExists(atPath: manifestURL.path))
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        XCTAssertFalse(manifestText.contains(#"\/"#))

        let manifest = try loadJSONObject(at: manifestURL)
        XCTAssertEqual(manifest["createdAt"] as? String, timestampString(from: fixedDate))
        XCTAssertEqual(manifest["profileId"] as? String, "alpha")

        let targets = try XCTUnwrap(manifest["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 3)

        let targetsByID = Dictionary(
            uniqueKeysWithValues: try targets.map { target in
                (
                    try XCTUnwrap(target["target"] as? String),
                    target
                )
            }
        )

        XCTAssertEqual(targetsByID["terminal"]?["status"] as? String, "backed_up")
        XCTAssertEqual(targetsByID["vscode"]?["status"] as? String, "backed_up")
        XCTAssertEqual(targetsByID["claude"]?["status"] as? String, "backed_up")

        let backupFiles = try XCTUnwrap(targetsByID["terminal"]?["backupFiles"] as? [String])
        XCTAssertEqual(backupFiles, ["\(timestampString(from: fixedDate))-terminal.sh"])
    }

    func testLoadConfigurationIgnoresLegacyProfilesJSONAndBootstrapsProfilesDirectory() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = makePaths(in: rootDirectory)
        let legacyProfileConfigURL = paths.applicationSupportDirectory.appendingPathComponent("profiles.json")
        try writeLegacyConfiguration(makeConfiguration(), to: legacyProfileConfigURL)

        let store = ProfileStore(paths: paths)
        let configuration = try store.loadConfiguration()

        XCTAssertEqual(configuration.profiles.map(\.id), ["vercel-ai-gateway"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profilesDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profilesIndexURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.profilesDirectoryURL.appendingPathComponent("vercel-ai-gateway.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyProfileConfigURL.path))
    }

    func testLoadConfigurationNormalizesEscapedSlashInExistingBootstrapProfileFile() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let paths = makePaths(in: rootDirectory)
        try FileManager.default.createDirectory(at: paths.profilesDirectoryURL, withIntermediateDirectories: true)
        try write(
            """
            {
              "version": 1
            }
            """,
            to: paths.profilesIndexURL
        )
        try write(
            """
            {
              "id": "vercel-ai-gateway",
              "name": "Vercel AI Gateway",
              "description": "Sample remote Anthropic-compatible provider",
              "env": {
                "API_TIMEOUT_MS": "30000000",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "anthropic\\/claude-haiku-4.5"
              }
            }
            """,
            to: paths.profilesDirectoryURL.appendingPathComponent("vercel-ai-gateway.json")
        )

        let store = ProfileStore(paths: paths)
        _ = try store.loadConfiguration()

        let normalized = try String(
            contentsOf: paths.profilesDirectoryURL.appendingPathComponent("vercel-ai-gateway.json"),
            encoding: .utf8
        )
        XCTAssertFalse(normalized.contains("\\/"))
        XCTAssertTrue(normalized.contains("anthropic/claude-haiku-4.5"))
    }

    func testLoadConfigurationMigratesLegacyApplicationSupportDirectoryToConfigDirectory() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let homeDirectory = rootDirectory.appendingPathComponent("home", isDirectory: true)
        let legacyDirectory = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("cc-env-switcher", isDirectory: true)
        let configDirectory = homeDirectory.appendingPathComponent(".config/cc-env-switcher", isDirectory: true)

        let paths = AppPaths(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: configDirectory,
            profilesDirectoryURL: configDirectory.appendingPathComponent("profiles", isDirectory: true),
            profilesIndexURL: configDirectory.appendingPathComponent("profiles/index.json"),
            stateURL: configDirectory.appendingPathComponent("state.json"),
            backupDirectoryURL: configDirectory.appendingPathComponent("backups", isDirectory: true),
            zshrcURL: homeDirectory.appendingPathComponent(".zshrc"),
            managedShellEnvironmentURL: homeDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh"),
            vscodeSettingsURL: homeDirectory.appendingPathComponent("Library/Application Support/Code/User/settings.json"),
            claudeSettingsURL: homeDirectory.appendingPathComponent(".claude/settings.json")
        )

        try write(
            """
            {
              "version": 1
            }
            """,
            to: legacyDirectory.appendingPathComponent("profiles/index.json")
        )
        try write(
            """
            {
              "description": "Migrated profile",
              "env": {
                "ANTHROPIC_BASE_URL": "https://migrated.example"
              }
            }
            """,
            to: legacyDirectory.appendingPathComponent("profiles/migrated.json")
        )
        try write(
            """
            {
              "lastAppliedProfileId": "migrated"
            }
            """,
            to: legacyDirectory.appendingPathComponent("state.json")
        )
        try write("backup", to: legacyDirectory.appendingPathComponent("backups/old-backup.txt"))

        let store = ProfileStore(paths: paths)
        let configuration = try store.loadConfiguration()

        XCTAssertEqual(configuration.profiles.map(\.id), ["migrated"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent("profiles/migrated.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: configDirectory.appendingPathComponent("backups/old-backup.txt").path))
        XCTAssertEqual(store.loadState().lastAppliedProfileId, "migrated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectory.path))
    }

    func testMissingIndexDoesNotDeleteOrReplaceExistingProfiles() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = makePaths(in: root)
        let custom = #"{"env":{"API_TIMEOUT_MS":"42"}}"#
        let sample = #"{"env":{"API_TIMEOUT_MS":"99"}}"#
        let customURL = paths.profilesDirectoryURL.appendingPathComponent("custom.json")
        let sampleURL = paths.profilesDirectoryURL.appendingPathComponent("vercel-ai-gateway.json")
        try write(custom, to: customURL)
        try write(sample, to: sampleURL)
        let profiles = try ProfileStore(paths: paths).loadConfiguration().profiles
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(try String(contentsOf: customURL, encoding: .utf8), custom + "\n")
        XCTAssertEqual(try String(contentsOf: sampleURL, encoding: .utf8), sample + "\n")
    }

    private func makeTempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePaths(in rootDirectory: URL) -> AppPaths {
        let homeDirectory = rootDirectory.appendingPathComponent("home", isDirectory: true)
        let applicationSupportDirectory = rootDirectory
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("cc-env-switcher", isDirectory: true)

        return AppPaths(
            homeDirectory: homeDirectory,
            applicationSupportDirectory: applicationSupportDirectory,
            profilesDirectoryURL: applicationSupportDirectory.appendingPathComponent("profiles", isDirectory: true),
            profilesIndexURL: applicationSupportDirectory.appendingPathComponent("profiles/index.json"),
            stateURL: applicationSupportDirectory.appendingPathComponent("state.json"),
            backupDirectoryURL: applicationSupportDirectory.appendingPathComponent("backups", isDirectory: true),
            zshrcURL: homeDirectory.appendingPathComponent(".zshrc"),
            managedShellEnvironmentURL: homeDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh"),
            vscodeSettingsURL: homeDirectory.appendingPathComponent("Library/Application Support/Code/User/settings.json"),
            claudeSettingsURL: homeDirectory.appendingPathComponent(".claude/settings.json")
        )
    }

    private func seedInitialFiles(paths: AppPaths) throws {
        try write(
            """
            export PATH="/usr/bin"
            source ~/.config/cc-env-switcher/env.sh
            """,
            to: paths.zshrcURL
        )
        try write(
            """
            export API_TIMEOUT_MS="1"
            export ANTHROPIC_BASE_URL="https://old.example"
            export ANTHROPIC_ORGANIZATION_ID="old-org"
            """,
            to: paths.managedShellEnvironmentURL
        )

        try write(
            """
            {
              // "claudeCode.environmentVariables": [
              //   {
              //     "name": "ANTHROPIC_BASE_URL",
              //     "value": "https://commented.example"
              //   }
              // ],
              "editor.fontSize": 13,
              "claudeCode.environmentVariables": [
                {
                  "name": "API_TIMEOUT_MS",
                  "value": "1"
                },
                {
                  "name": "ANTHROPIC_BASE_URL",
                  "value": "https://old.example"
                },
                {
                  "name": "UNMANAGED_KEEP",
                  "value": "yes"
                }
              ]
            }
            """,
            to: paths.vscodeSettingsURL
        )

        try write(
            """
            {
              "enabledPlugins": {
                "yuque-personal:yuque": true
              },
              "env": {
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_BASE_URL": "https://old.example",
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
              }
            }
            """,
            to: paths.claudeSettingsURL
        )
    }

    private func makeConfiguration() -> ProfileConfiguration {
        ProfileConfiguration(
            version: 1,
            profiles: [
                ClaudeProfile(
                    id: "alpha",
                    description: "Remote provider",
                    env: [
                        "API_TIMEOUT_MS": "30000000",
                        "ANTHROPIC_BASE_URL": "https://alpha.example",
                        "ANTHROPIC_MODEL": "alpha-sonnet",
                        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
                    ]
                ),
                ClaudeProfile(
                    id: "beta",
                    description: "Local proxy",
                    env: [
                        "API_TIMEOUT_MS": "5000",
                        "ANTHROPIC_MODEL": "beta-sonnet",
                        "ANTHROPIC_ORGANIZATION_ID": "example-org"
                    ]
                )
            ]
        )
    }

    private func writeConfiguration(_ configuration: ProfileConfiguration, to paths: AppPaths) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let index = ProfileIndex(version: configuration.version)
        let indexData = try encoder.encode(index)
        try write(String(decoding: indexData, as: UTF8.self), to: paths.profilesIndexURL)

        for profile in configuration.profiles {
            let data = try encoder.encode(profile)
            let url = paths.profilesDirectoryURL.appendingPathComponent("\(profile.id).json")
            try write(String(decoding: data, as: UTF8.self), to: url)
        }
    }

    private func writeLegacyConfiguration(_ configuration: ProfileConfiguration, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try write(String(decoding: data, as: UTF8.self), to: url)
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let normalizedText = text.hasSuffix("\n") ? text : text + "\n"
        try Data(normalizedText.utf8).write(to: url, options: .atomic)
    }

    private func backupFileNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }

        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let directoryPath = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        return try enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && !url.lastPathComponent.hasPrefix("manifest")
            }
            .map { String($0.path.dropFirst(directoryPath.count)) }
            .sorted()
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    private func loadJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func requireProfile(id: String, from configuration: ProfileConfiguration) throws -> ClaudeProfile {
        try XCTUnwrap(configuration.profiles.first(where: { $0.id == id }))
    }
}
