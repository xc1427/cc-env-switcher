import AppKit
import CCEnvSwitcherCore
import Foundation

@MainActor
package final class AppViewModel: ObservableObject {
    @Published var configuration: ProfileConfiguration?
    @Published var selectedProfileID: String?
    @Published var previews: [TargetPreview] = []
    @Published var currentProfileStatus: CurrentProfileStatus = .unmatched
    @Published var isDebugModeEnabled = false
    @Published var statusMessage: String?
    @Published var warningMessage: String?
    @Published var errorMessage: String?
    @Published var isShowingApplyConfirmation = false
    @Published var pendingApplyProfileID: String?
    @Published var pendingApplyPreviews: [TargetPreview] = []
    @Published private(set) var activeTargetPaths: AppPaths

    let paths: AppPaths

    private let profileStore: ProfileStore
    private let applyServiceFactory: (AppPaths) -> ApplyService
    private let successMessageAutoClearDelay: Duration
    private let isVSCodeInstalled: () -> Bool
    private let openProfileDirectoryInVSCode: (URL) -> Void
    private var applyService: ApplyService
    private var clearStatusMessageTask: Task<Void, Never>?

    init(
        paths: AppPaths,
        profileStore: ProfileStore,
        applyService: ApplyService,
        activeTargetPaths: AppPaths? = nil,
        applyServiceFactory: ((AppPaths) -> ApplyService)? = nil,
        successMessageAutoClearDelay: Duration = .seconds(5),
        isVSCodeInstalled: (() -> Bool)? = nil,
        openProfileDirectoryInVSCode: ((URL) -> Void)? = nil
    ) {
        self.paths = paths
        self.profileStore = profileStore
        self.activeTargetPaths = activeTargetPaths ?? paths
        self.successMessageAutoClearDelay = successMessageAutoClearDelay
        self.isVSCodeInstalled = isVSCodeInstalled ?? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") != nil
        }
        self.openProfileDirectoryInVSCode = openProfileDirectoryInVSCode ?? { url in
            guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode") else {
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, _ in }
        }
        if let applyServiceFactory {
            self.applyServiceFactory = applyServiceFactory
        } else {
            self.applyServiceFactory = { _ in applyService }
        }
        self.applyService = applyService
    }

    package static func live() -> AppViewModel {
        let paths = AppPaths.live()
        let profileStore = ProfileStore(paths: paths)
        let backupService = BackupService(backupDirectoryURL: paths.backupDirectoryURL)
        let applyServiceFactory: (AppPaths) -> ApplyService = { targetPaths in
            let claudeTarget = ClaudeSettingsTarget(fileURL: targetPaths.claudeSettingsURL)
            let writers: [any TargetWriter] = [
                ZshrcTarget(fileURL: targetPaths.zshrcURL, envFileURL: targetPaths.managedShellEnvironmentURL),
                JSONCEnvironmentTarget(target: .vscode, fileURL: targetPaths.vscodeSettingsURL),
                claudeTarget
            ]
            return ApplyService(
                writers: writers,
                backupService: backupService,
                profileStore: profileStore,
                stateURL: targetPaths.stateURL
            )
        }
        let applyService = applyServiceFactory(paths)

        return AppViewModel(
            paths: paths,
            profileStore: profileStore,
            applyService: applyService,
            activeTargetPaths: paths,
            applyServiceFactory: applyServiceFactory
        )
    }

    var profiles: [ClaudeProfile] {
        configuration?.profiles ?? []
    }

    var selectedProfile: ClaudeProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }

    var selectedProfileEnvironmentDetailsRows: [EnvironmentDetailsRow] {
        guard let profile = selectedProfile else {
            return []
        }

        let currentTrackedEnvironment = applyService.coherentCurrentManagedEnvironment() ?? [:]
        return ManagedEnvironment.environmentDetailsRows(
            profileEnvironment: profile.env,
            extraCurrentEnvironment: currentTrackedEnvironment
        )
    }

    var pendingApplyProfile: ClaudeProfile? {
        profiles.first(where: { $0.id == pendingApplyProfileID })
    }

    var currentMatchedProfileID: String? {
        if case let .matched(profile) = currentProfileStatus {
            return profile.id
        }
        return nil
    }

    var targetModeDescription: String {
        if isDebugModeEnabled {
            return "Using debug targets in \(activeTargetPaths.debugTargetsDirectoryURL.path)."
        }
        return "Using system targets (~/.zshrc source line, ~/.config/cc-env-switcher/env.sh, VSCode settings, ~/.claude/settings.json)."
    }

    var debugTargetFileNamesDescription: String {
        "debug.zshrc, debug.env.sh, debug.vscode.settings.json, debug.claude.settings.json"
    }

    func load() {
        do {
            let configuration = try profileStore.loadConfiguration()
            self.configuration = configuration
            let state = profileStore.loadState(stateURL: activeTargetPaths.stateURL)

            let detectedStatus = applyService.detectCurrentProfileStatus(in: configuration.profiles)
            currentProfileStatus = detectedStatus
            warningMessage = combinedWarningMessage(in: configuration.profiles)

            if selectedProfileID == nil || !configuration.profiles.contains(where: { $0.id == selectedProfileID }) {
                selectedProfileID = initialSelectedProfileID(
                    status: detectedStatus,
                    lastAppliedProfileID: state.lastAppliedProfileId,
                    profiles: configuration.profiles
                )
            }

            refreshPreview()
            errorMessage = nil
        } catch {
            warningMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func reloadProfiles() {
        load()
        if errorMessage == nil {
            showSuccessMessage("Refreshed profiles from disk.")
        }
    }

    func setDebugModeEnabled(_ enabled: Bool) {
        guard isDebugModeEnabled != enabled else { return }

        isDebugModeEnabled = enabled
        applyModeConfiguration()
        load()
    }

    func generateDebugBaselineTargets() {
        guard isDebugModeEnabled else {
            errorMessage = "Enable Debug Mode before generating baseline targets."
            return
        }

        do {
            try DebugTargetSeeder().seed(at: activeTargetPaths)
            load()
            errorMessage = nil
            showSuccessMessage("Generated baseline debug targets.")
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func refreshPreview() {
        guard let profile = selectedProfile else {
            previews = []
            return
        }

        statusMessage = nil
        previews = applyService.preview(profile: profile)
    }

    func prepareApplySelectedProfile() {
        guard let profile = selectedProfile else { return }

        pendingApplyProfileID = profile.id
        pendingApplyPreviews = applyService.preview(profile: profile)
        isShowingApplyConfirmation = true
    }

    func cancelApplyConfirmation() {
        isShowingApplyConfirmation = false
        pendingApplyProfileID = nil
        pendingApplyPreviews = []
    }

    func confirmApplySelectedProfile() {
        guard let profile = pendingApplyProfile else { return }

        let report = applyService.apply(profile: profile)
        currentProfileStatus = applyService.detectCurrentProfileStatus(in: profiles)
        warningMessage = combinedWarningMessage(in: profiles)
        isShowingApplyConfirmation = false
        pendingApplyProfileID = nil
        pendingApplyPreviews = []

        if report.failureCount == 0 {
            refreshPreview()
            showSuccessMessage("Applied '\(profile.id)' to \(report.previews.count) targets.")
            errorMessage = nil
        } else {
            previews = report.previews
            clearStatusMessageTask?.cancel()
            statusMessage = nil
            errorMessage = "Apply finished with \(report.failureCount) failed target(s)."
        }
    }

    func revealProfilesFile() {
        reveal(url: paths.profilesDirectoryURL)
    }

    func revealBackupsFolder() {
        reveal(url: paths.backupDirectoryURL)
    }

    func editProfilesDirectory() {
        clearStatusMessageTask?.cancel()
        statusMessage = nil

        guard isVSCodeInstalled() else {
            errorMessage = "Install Visual Studio Code to edit profiles."
            return
        }

        errorMessage = nil
        openProfileDirectoryInVSCode(paths.profilesDirectoryURL)
    }

    private func reveal(url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    private func initialSelectedProfileID(
        status: CurrentProfileStatus,
        lastAppliedProfileID: String?,
        profiles: [ClaudeProfile]
    ) -> String? {
        if case let .matched(profile) = status {
            return profile.id
        }

        if let lastAppliedProfileID,
           profiles.contains(where: { $0.id == lastAppliedProfileID }) {
            return lastAppliedProfileID
        }

        return profiles.first?.id
    }

    private func applyModeConfiguration() {
        cancelApplyConfirmation()

        let nextTargetPaths = isDebugModeEnabled
            ? paths.withTargetFilesInDebugDirectory()
            : paths
        activeTargetPaths = nextTargetPaths
        applyService = applyServiceFactory(nextTargetPaths)
    }

    private func showSuccessMessage(_ message: String) {
        clearStatusMessageTask?.cancel()
        statusMessage = message

        let delay = successMessageAutoClearDelay
        clearStatusMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
            self?.clearStatusMessageTask = nil
        }
    }

    private func duplicateTrackedProfilesWarning(in profiles: [ClaudeProfile]) -> String? {
        let hasDuplicates = Dictionary(grouping: profiles) { profile in
            profile.managedEnvironment.keys.sorted().map { key in
                "\(key)=\(profile.managedEnvironment[key] ?? "")"
            }.joined(separator: "\u{1F}")
        }
        .values
        .contains { $0.count > 1 }

        guard hasDuplicates else {
            return nil
        }

        return "Some profiles define identical tracked values. Current matching uses the first one."
    }

    private func zshrcConflictWarning() -> String? {
        let conflicts = (try? ZshrcTarget(
            fileURL: activeTargetPaths.zshrcURL,
            envFileURL: activeTargetPaths.managedShellEnvironmentURL
        ).detectedTrackedVariableConflicts()) ?? []

        guard !conflicts.isEmpty else {
            return nil
        }

        let joinedConflicts = conflicts.joined(separator: ", ")
        return "Tracked variables are still defined in ~/.zshrc: \(joinedConflicts). Remove them and keep only the cc-env-switcher source hook."
    }

    private func combinedWarningMessage(in profiles: [ClaudeProfile]) -> String? {
        [duplicateTrackedProfilesWarning(in: profiles), zshrcConflictWarning()]
            .compactMap { $0 }
            .joined(separator: "\n\n")
            .nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
