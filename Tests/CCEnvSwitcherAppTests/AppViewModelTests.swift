import Foundation
import XCTest
@testable import CCEnvSwitcherApp
@testable import CCEnvSwitcherCore

final class AppViewModelTests: XCTestCase {
    @MainActor
    func testLoadPrefersMatchedCurrentProfileOverLastAppliedProfile() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        try context.store.saveState(AppState(lastAppliedProfileId: "beta", lastAppliedAt: Date()))
        try seedAllTargets(with: try requireProfile(id: "alpha", from: context.configuration), paths: context.paths)

        context.viewModel.load()

        XCTAssertEqual(context.viewModel.selectedProfileID, "alpha")
        XCTAssertEqual(
            context.viewModel.currentProfileStatus,
            .matched(try requireProfile(id: "alpha", from: context.configuration))
        )
    }

    @MainActor
    func testLoadTreatsCurrentProfileAsMatchedWhenTargetsOnlyDifferByExtraManagedKeys() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        let alpha = try requireProfile(id: "alpha", from: context.configuration)
        try seedAllTargets(with: alpha, paths: context.paths)
        try write(
            """
            {
              "env": {
                "API_TIMEOUT_MS": "30000000",
                "ANTHROPIC_BASE_URL": "https://alpha.example",
                "ANTHROPIC_MODEL": "alpha-sonnet",
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
              }
            }
            """,
            to: context.paths.claudeSettingsURL
        )

        context.viewModel.load()

        XCTAssertEqual(context.viewModel.currentProfileStatus, .matched(alpha))
        XCTAssertEqual(context.viewModel.selectedProfileID, "alpha")
    }

    @MainActor
    func testLoadFallsBackToLastAppliedWhenCurrentIsUnmatched() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        try context.store.saveState(AppState(lastAppliedProfileId: "beta", lastAppliedAt: Date()))

        let customEnvironment = [
            "API_TIMEOUT_MS": "7777",
            "ANTHROPIC_BASE_URL": "https://custom.example"
        ]
        try seedAllTargets(
            with: ClaudeProfile(id: "seed", description: nil, env: customEnvironment),
            paths: context.paths
        )

        context.viewModel.load()

        XCTAssertEqual(context.viewModel.currentProfileStatus, .unmatched)
        XCTAssertEqual(context.viewModel.selectedProfileID, "beta")
    }

    @MainActor
    func testLoadShowsWarningWhenProfilesShareIdenticalTrackedValues() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let duplicateConfiguration = ProfileConfiguration(
            version: 1,
            profiles: [
                ClaudeProfile(
                    id: "alpha",
                    description: "First",
                    env: ["ANTHROPIC_BASE_URL": "https://same.example"]
                ),
                ClaudeProfile(
                    id: "beta",
                    description: "Second",
                    env: ["ANTHROPIC_BASE_URL": "https://same.example"]
                )
            ]
        )

        let context = try makeContext(in: rootDirectory, configuration: duplicateConfiguration)

        context.viewModel.load()

        XCTAssertEqual(
            context.viewModel.warningMessage,
            "Some profiles define identical tracked values. Current matching uses the first one."
        )
    }

    @MainActor
    func testLoadShowsWarningWhenZshrcStillDefinesTrackedVariables() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        try write(
            """
            export PATH="/usr/bin"
            source ~/.config/cc-env-switcher/env.sh
            export ANTHROPIC_BASE_URL="https://manual.example"
            API_TIMEOUT_MS="5"
            """,
            to: context.paths.zshrcURL
        )

        context.viewModel.load()

        XCTAssertNotNil(context.viewModel.warningMessage)
        XCTAssertTrue(context.viewModel.warningMessage?.contains("Tracked variables are still defined in ~/.zshrc") == true)
        XCTAssertTrue(context.viewModel.warningMessage?.contains("ANTHROPIC_BASE_URL") == true)
        XCTAssertTrue(context.viewModel.warningMessage?.contains("API_TIMEOUT_MS") == true)
    }

    @MainActor
    func testReloadKeepsZshrcConflictWarningUntilManualCleanup() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        context.viewModel.load()
        context.viewModel.selectedProfileID = "alpha"

        try write(
            """
            export PATH="/usr/bin"
            export ANTHROPIC_MODEL="manual-sonnet"
            """,
            to: context.paths.zshrcURL
        )

        context.viewModel.reloadProfiles()
        let warningBeforeApply = context.viewModel.warningMessage

        context.viewModel.refreshPreview()
        context.viewModel.prepareApplySelectedProfile()
        context.viewModel.confirmApplySelectedProfile()

        XCTAssertEqual(context.viewModel.warningMessage, warningBeforeApply)

        try write(
            """
            export PATH="/usr/bin"
            source ~/.config/cc-env-switcher/env.sh
            """,
            to: context.paths.zshrcURL
        )

        context.viewModel.reloadProfiles()

        XCTAssertFalse(context.viewModel.warningMessage?.contains("ANTHROPIC_MODEL") == true)
    }

    @MainActor
    func testPrepareApplyShowsConfirmationWithoutWritingFiles() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        let zshrcBefore = try String(contentsOf: context.paths.zshrcURL, encoding: .utf8)

        context.viewModel.load()
        context.viewModel.selectedProfileID = "alpha"
        context.viewModel.refreshPreview()
        context.viewModel.prepareApplySelectedProfile()

        XCTAssertTrue(context.viewModel.isShowingApplyConfirmation)
        XCTAssertEqual(context.viewModel.pendingApplyProfile?.id, "alpha")
        XCTAssertEqual(context.viewModel.pendingApplyPreviews.count, 3)
        XCTAssertEqual(try String(contentsOf: context.paths.zshrcURL, encoding: .utf8), zshrcBefore)
    }

    @MainActor
    func testConfirmApplyRefreshesCurrentStatusAfterMixedState() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)

        context.viewModel.load()
        XCTAssertEqual(context.viewModel.currentProfileStatus, .unmatched)

        context.viewModel.selectedProfileID = "alpha"
        context.viewModel.refreshPreview()
        context.viewModel.prepareApplySelectedProfile()
        context.viewModel.confirmApplySelectedProfile()

        XCTAssertFalse(context.viewModel.isShowingApplyConfirmation)
        XCTAssertEqual(context.viewModel.pendingApplyProfileID, nil)
        XCTAssertEqual(context.viewModel.pendingApplyPreviews.count, 0)
        XCTAssertEqual(context.viewModel.currentProfileStatus, .matched(try requireProfile(id: "alpha", from: context.configuration)))
        XCTAssertEqual(context.store.loadState().lastAppliedProfileId, "alpha")
    }

    @MainActor
    func testSelectedProfileEnvironmentDetailsRowsIncludeProfileUntrackedKeysAndCurrentTrackedExtras() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        var configuration = makeConfiguration()
        configuration.profiles[0].env["NON_SENSE_VAR"] = "haha"

        let context = try makeContext(in: rootDirectory, configuration: configuration)
        let alpha = try requireProfile(id: "alpha", from: configuration)
        let seededCurrentEnvironment = alpha.env.merging(
            [
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
            ],
            uniquingKeysWith: { _, newValue in newValue }
        )

        try seedAllTargets(
            with: ClaudeProfile(id: "seed", description: nil, env: seededCurrentEnvironment),
            paths: context.paths
        )

        try write(
            """
            {
              "env": {
                "ANTHROPIC_BASE_URL": "https://alpha.example",
                "ANTHROPIC_MODEL": "alpha-sonnet",
                "API_TIMEOUT_MS": "30000000",
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                "UNRELATED_KEY": "ignore-me"
              }
            }
            """,
            to: context.paths.claudeSettingsURL
        )

        context.viewModel.load()

        XCTAssertEqual(context.viewModel.currentProfileStatus, .matched(alpha))
        XCTAssertEqual(
            context.viewModel.selectedProfileEnvironmentDetailsRows,
            [
                EnvironmentDetailsRow(
                    name: "API_TIMEOUT_MS",
                    value: "30000000",
                    kind: .trackedInProfile,
                    id: "API_TIMEOUT_MS-trackedInProfile"
                ),
                EnvironmentDetailsRow(
                    name: "ANTHROPIC_BASE_URL",
                    value: "https://alpha.example",
                    kind: .trackedInProfile,
                    id: "ANTHROPIC_BASE_URL-trackedInProfile"
                ),
                EnvironmentDetailsRow(
                    name: "ANTHROPIC_MODEL",
                    value: "alpha-sonnet",
                    kind: .trackedInProfile,
                    id: "ANTHROPIC_MODEL-trackedInProfile"
                ),
                EnvironmentDetailsRow(
                    name: "NON_SENSE_VAR",
                    value: "haha",
                    kind: .notTrackedBySwitcher,
                    id: "NON_SENSE_VAR-notTrackedBySwitcher"
                ),
                EnvironmentDetailsRow(
                    name: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
                    value: "1",
                    kind: .notTrackedHere,
                    id: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-notTrackedHere"
                )
            ]
        )
        XCTAssertFalse(context.viewModel.selectedProfileEnvironmentDetailsRows.contains(where: { $0.name == "UNRELATED_KEY" }))
    }

    @MainActor
    func testSwitchingToDebugModeRedirectsTargetsToDebugFiles() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        context.viewModel.load()
        context.viewModel.selectedProfileID = "beta"

        context.viewModel.setDebugModeEnabled(true)

        XCTAssertTrue(context.viewModel.isDebugModeEnabled)
        XCTAssertTrue(context.viewModel.previews.allSatisfy { preview in
            preview.fileURL.deletingLastPathComponent().path == context.paths.debugTargetsDirectoryURL.path
        })
        XCTAssertEqual(
            Set(context.viewModel.previews.map { $0.fileURL.lastPathComponent }),
            Set([
                "debug.env.sh",
                "debug.vscode.settings.json",
                "debug.claude.settings.json"
            ])
        )

        context.viewModel.prepareApplySelectedProfile()
        context.viewModel.confirmApplySelectedProfile()

        let debugPaths = context.paths.withTargetFilesInDebugDirectory()
        let defaultState = context.store.loadState(stateURL: context.paths.stateURL)
        let debugState = context.store.loadState(stateURL: debugPaths.stateURL)

        XCTAssertNil(defaultState.lastAppliedProfileId)
        XCTAssertEqual(debugState.lastAppliedProfileId, "beta")
        XCTAssertTrue(FileManager.default.fileExists(atPath: debugPaths.zshrcURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: debugPaths.managedShellEnvironmentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: debugPaths.vscodeSettingsURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: debugPaths.claudeSettingsURL.path))

        let systemZshrc = try String(contentsOf: context.paths.zshrcURL, encoding: .utf8)
        XCTAssertTrue(systemZshrc.contains("source ~/.config/cc-env-switcher/env.sh"))

        let debugZshrc = try String(contentsOf: debugPaths.zshrcURL, encoding: .utf8)
        XCTAssertTrue(debugZshrc.contains("debug.env.sh"))

        let debugManagedEnv = try String(contentsOf: debugPaths.managedShellEnvironmentURL, encoding: .utf8)
        XCTAssertTrue(debugManagedEnv.contains("export API_TIMEOUT_MS=\"5000\""))
        XCTAssertTrue(debugManagedEnv.contains("export ANTHROPIC_ORGANIZATION_ID=\"example-org\""))
    }

    @MainActor
    func testDebugModeWarningUsesDebugZshrcInsteadOfSystemZshrc() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        try write(
            """
            export PATH="/usr/bin"
            source ~/.config/cc-env-switcher/env.sh
            export ANTHROPIC_BASE_URL="https://system-conflict.example"
            """,
            to: context.paths.zshrcURL
        )

        let debugPaths = context.paths.withTargetFilesInDebugDirectory()
        try write(
            """
            export PATH="/usr/bin"
            source "\(debugPaths.managedShellEnvironmentURL.path)"
            """,
            to: debugPaths.zshrcURL
        )

        context.viewModel.load()
        XCTAssertTrue(context.viewModel.warningMessage?.contains("ANTHROPIC_BASE_URL") == true)

        context.viewModel.setDebugModeEnabled(true)
        XCTAssertFalse(context.viewModel.warningMessage?.contains("ANTHROPIC_BASE_URL") == true)
    }

    @MainActor
    func testDebugModeWarningPicksUpTrackedConflictsInDebugZshrc() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        let debugPaths = context.paths.withTargetFilesInDebugDirectory()
        try write(
            """
            export PATH="/usr/bin"
            source "\(debugPaths.managedShellEnvironmentURL.path)"
            export ANTHROPIC_AUTH_TOKEN="debug-conflict-token"
            """,
            to: debugPaths.zshrcURL
        )

        context.viewModel.setDebugModeEnabled(true)
        XCTAssertTrue(context.viewModel.warningMessage?.contains("ANTHROPIC_AUTH_TOKEN") == true)
    }

    @MainActor
    func testGenerateDebugBaselineTargetsWritesRepresentativeFiles() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        let debugPaths = context.paths.withTargetFilesInDebugDirectory()

        context.viewModel.load()
        context.viewModel.setDebugModeEnabled(true)
        context.viewModel.generateDebugBaselineTargets()

        XCTAssertEqual(context.viewModel.statusMessage, "Generated baseline debug targets.")
        XCTAssertNil(context.viewModel.errorMessage)

        let debugZshrc = try String(contentsOf: debugPaths.zshrcURL, encoding: .utf8)
        XCTAssertTrue(debugZshrc.contains("alias ll=\"ls -lah\""))
        XCTAssertTrue(debugZshrc.contains("source \"\(debugPaths.managedShellEnvironmentURL.path)\""))

        let debugEnv = try String(contentsOf: debugPaths.managedShellEnvironmentURL, encoding: .utf8)
        XCTAssertTrue(debugEnv.contains("# Baseline debug environment for backup verification."))
        XCTAssertTrue(debugEnv.contains("export DEBUG_BASELINE_MARKER=\"keep-me\""))
        XCTAssertTrue(debugEnv.contains("export ANTHROPIC_BASE_URL=\"https://ai-gateway.vercel.sh\""))

        let debugVSCode = try String(contentsOf: debugPaths.vscodeSettingsURL, encoding: .utf8)
        XCTAssertTrue(debugVSCode.contains("\"editor.fontSize\""))
        XCTAssertTrue(debugVSCode.contains("\"files.autoSave\""))
        XCTAssertTrue(debugVSCode.contains("\"workbench.colorTheme\""))
        XCTAssertTrue(debugVSCode.contains("\"claudeCode.environmentVariables\""))


        let debugClaude = try String(contentsOf: debugPaths.claudeSettingsURL, encoding: .utf8)
        XCTAssertTrue(debugClaude.contains("\"model\""))
        XCTAssertTrue(debugClaude.contains("\"permissions\""))
        XCTAssertTrue(debugClaude.contains("\"hooks\""))
        XCTAssertTrue(debugClaude.contains("\"env\""))
    }

    @MainActor
    func testReloadProfilesPicksUpNewProfileAddedOnDisk() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory)
        context.viewModel.load()
        XCTAssertEqual(context.viewModel.profiles.map(\.id), ["alpha", "beta"])

        try write(
            """
            {
              "description": "Manually added in Finder",
              "env": {
                "API_TIMEOUT_MS": "9000",
                "ANTHROPIC_DEFAULT_HAIKU_MODEL": "anthropic/claude-haiku-4.5"
              }
            }
            """,
            to: context.paths.profilesDirectoryURL.appendingPathComponent("gamma.json")
        )

        context.viewModel.reloadProfiles()

        XCTAssertEqual(context.viewModel.profiles.map(\.id), ["alpha", "beta", "gamma"])
        XCTAssertEqual(context.viewModel.errorMessage, nil)
    }

    @MainActor
    func testEditProfileShowsFriendlyMessageWhenVSCodeIsUnavailable() throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(
            in: rootDirectory,
            isVSCodeInstalled: { false },
            openProfileDirectoryInVSCode: { _ in
                XCTFail("Edit Profile should not try to launch VS Code when it is unavailable.")
            }
        )
        context.viewModel.load()

        context.viewModel.editProfilesDirectory()

        XCTAssertEqual(context.viewModel.errorMessage, "Install Visual Studio Code to edit profiles.")
        XCTAssertNil(context.viewModel.statusMessage)
    }

    @MainActor
    func testReloadSuccessMessageAutoClearsAfterDelay() async throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory, successMessageAutoClearDelay: .milliseconds(20))
        context.viewModel.load()

        context.viewModel.reloadProfiles()
        XCTAssertEqual(context.viewModel.statusMessage, "Refreshed profiles from disk.")

        try await Task.sleep(for: .milliseconds(60))

        XCTAssertNil(context.viewModel.statusMessage)
    }

    @MainActor
    func testApplySuccessMessageAutoClearsAfterDelay() async throws {
        let rootDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let context = try makeContext(in: rootDirectory, successMessageAutoClearDelay: .milliseconds(20))
        context.viewModel.load()
        context.viewModel.selectedProfileID = "alpha"
        context.viewModel.refreshPreview()
        context.viewModel.prepareApplySelectedProfile()

        context.viewModel.confirmApplySelectedProfile()
        XCTAssertEqual(context.viewModel.statusMessage, "Applied 'alpha' to 3 targets.")

        try await Task.sleep(for: .milliseconds(60))

        XCTAssertNil(context.viewModel.statusMessage)
    }

    @MainActor
    private func makeContext(
        in rootDirectory: URL,
        configuration: ProfileConfiguration? = nil,
        successMessageAutoClearDelay: Duration = .seconds(5),
        isVSCodeInstalled: @escaping () -> Bool = { true },
        openProfileDirectoryInVSCode: @escaping (URL) -> Void = { _ in }
    ) throws -> (viewModel: AppViewModel, store: ProfileStore, paths: AppPaths, configuration: ProfileConfiguration) {
        let paths = makePaths(in: rootDirectory)
        try seedInitialFiles(paths: paths)
        let resolvedConfiguration = configuration ?? makeConfiguration()
        try writeConfiguration(resolvedConfiguration, to: paths)

        let store = ProfileStore(paths: paths)
        let backupService = BackupService(backupDirectoryURL: paths.backupDirectoryURL)
        let serviceFactory = makeApplyServiceFactory(profileStore: store, backupService: backupService)
        let service = serviceFactory(paths)
        let viewModel = AppViewModel(
            paths: paths,
            profileStore: store,
            applyService: service,
            activeTargetPaths: paths,
            applyServiceFactory: serviceFactory,
            successMessageAutoClearDelay: successMessageAutoClearDelay,
            isVSCodeInstalled: isVSCodeInstalled,
            openProfileDirectoryInVSCode: openProfileDirectoryInVSCode
        )

        return (viewModel, store, paths, resolvedConfiguration)
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
        try write(#"export API_TIMEOUT_MS=\"1\""#, to: paths.managedShellEnvironmentURL)

        try write(
            """
            {
              "claudeCode.environmentVariables": [
                {
                  "name": "API_TIMEOUT_MS",
                  "value": "2"
                }
              ]
            }
            """,
            to: paths.vscodeSettingsURL
        )



        try write(
            """
            {
              "env": {
                "API_TIMEOUT_MS": "4"
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
                        "ANTHROPIC_MODEL": "alpha-sonnet"
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

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let normalized = text.hasSuffix("\n") ? text : text + "\n"
        try Data(normalized.utf8).write(to: url, options: .atomic)
    }

    private func seedAllTargets(with profile: ClaudeProfile, paths: AppPaths) throws {
        let writers = makeWriters(for: paths)
        let backupService = BackupService(backupDirectoryURL: paths.backupDirectoryURL)
        let backupRun = backupService.makeRun()
        for writer in writers {
            _ = try writer.apply(profile: profile, backupService: backupService, backupRun: backupRun)
        }
    }

    private func makeApplyServiceFactory(
        profileStore: ProfileStore,
        backupService: BackupService
    ) -> (AppPaths) -> ApplyService {
        { paths in
            ApplyService(
                writers: self.makeWriters(for: paths),
                backupService: backupService,
                profileStore: profileStore,
                stateURL: paths.stateURL
            )
        }
    }

    private func makeWriters(for paths: AppPaths) -> [any TargetWriter] {
        [
            ZshrcTarget(fileURL: paths.zshrcURL, envFileURL: paths.managedShellEnvironmentURL),
            JSONCEnvironmentTarget(target: .vscode, fileURL: paths.vscodeSettingsURL),
            ClaudeSettingsTarget(fileURL: paths.claudeSettingsURL)
        ]
    }

    private func requireProfile(id: String, from configuration: ProfileConfiguration) throws -> ClaudeProfile {
        try XCTUnwrap(configuration.profiles.first(where: { $0.id == id }))
    }
}
