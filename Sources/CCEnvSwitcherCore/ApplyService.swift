import Foundation

package final class ApplyService {
    private let writers: [any TargetWriter]
    private let backupService: BackupService
    private let profileStore: ProfileStore
    private let stateURL: URL?

    package init(
        writers: [any TargetWriter],
        backupService: BackupService,
        profileStore: ProfileStore,
        stateURL: URL? = nil
    ) {
        self.writers = writers
        self.backupService = backupService
        self.profileStore = profileStore
        self.stateURL = stateURL
    }

    package func preview(profile: ClaudeProfile) -> [TargetPreview] {
        writers.map { writer in
            do {
                return try writer.preview(for: profile)
            } catch {
                return writer.makeErrorPreview(error)
            }
        }
    }

    package func apply(profile: ClaudeProfile) -> ApplyReport {
        let backupRun = backupService.makeRun()
        let previews = writers.map { writer in
            do {
                return try writer.apply(profile: profile, backupService: backupService, backupRun: backupRun)
            } catch {
                return writer.makeErrorPreview(error)
            }
        }

        _ = try? backupService.writeManifest(for: backupRun, profileID: profile.id, previews: previews)

        if previews.allSatisfy({ $0.errorMessage == nil }) {
            try? profileStore.saveState(
                AppState(lastAppliedProfileId: profile.id, lastAppliedAt: Date()),
                stateURL: stateURL
            )
        }

        return ApplyReport(previews: previews)
    }

    package func detectCurrentProfileStatus(in profiles: [ClaudeProfile]) -> CurrentProfileStatus {
        guard let currentEnvironments = currentManagedEnvironments() else {
            return .unmatched
        }

        if let profile = bestMatchingProfile(across: currentEnvironments, profiles: profiles) {
            return .matched(profile)
        }

        return .unmatched
    }

    package func coherentCurrentManagedEnvironment() -> [String: String]? {
        guard let currentEnvironments = currentManagedEnvironments() else {
            return nil
        }

        guard let unifiedEnvironment = currentEnvironments.first else {
            return nil
        }

        guard currentEnvironments.allSatisfy({ $0 == unifiedEnvironment }) else {
            return nil
        }

        return unifiedEnvironment
    }

    private func currentManagedEnvironments() -> [[String: String]]? {
        let environments = writers.map { writer in
            try? writer.currentManagedEnvironment()
        }

        guard environments.allSatisfy({ $0 != nil }) else {
            return nil
        }

        return environments.compactMap { $0 }
    }

    package func detectCurrentProfile(in profiles: [ClaudeProfile]) -> ClaudeProfile? {
        if case let .matched(profile) = detectCurrentProfileStatus(in: profiles) {
            return profile
        }

        return nil
    }

    private func bestMatchingProfile(
        across currentEnvironments: [[String: String]],
        profiles: [ClaudeProfile]
    ) -> ClaudeProfile? {
        profiles.enumerated()
            .filter { _, profile in
                currentEnvironments.allSatisfy { environment in
                    profile.managedEnvironment.allSatisfy { key, value in
                        environment[key] == value
                    }
                }
            }
            .sorted { lhs, rhs in
                let leftCount = lhs.element.managedEnvironment.count
                let rightCount = rhs.element.managedEnvironment.count

                if leftCount != rightCount {
                    return leftCount > rightCount
                }

                return lhs.offset < rhs.offset
            }
            .first?
            .element
    }
}
