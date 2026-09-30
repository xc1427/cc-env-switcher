import Foundation

package enum ManagedEnvironment {
    package static let explicitOrderedKeys: [String] = [
        "API_TIMEOUT_MS"
    ]

    package static let explicitManagedKeys: [String] = [
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"
    ]

    package static let managedPrefixes: [String] = [
        "ANTHROPIC_",
        "CLAUDE_CODE_"
    ]

    private static let explicitKeySet = Set(explicitOrderedKeys + explicitManagedKeys)

    package static func isManagedKey(_ key: String) -> Bool {
        if explicitKeySet.contains(key) {
            return true
        }

        return managedPrefixes.contains(where: { key.hasPrefix($0) })
    }

    package static func filtered(_ values: [String: String]) -> [String: String] {
        values.filter { isManagedKey($0.key) }
    }

    package static func orderedKeys(from values: [String: String]) -> [String] {
        let managedValues = filtered(values)
        var ordered: [String] = []
        var seen = Set<String>()

        for key in explicitOrderedKeys where managedValues[key] != nil {
            ordered.append(key)
            seen.insert(key)
        }

        let remainingKeys = managedValues.keys
            .filter { !seen.contains($0) }
            .sorted()
        ordered.append(contentsOf: remainingKeys)

        return ordered
    }

    package static func orderedEntries(from values: [String: String]) -> [EnvironmentEntry] {
        orderedKeys(from: values).compactMap { key in
            values[key].map { EnvironmentEntry(name: key, value: $0) }
        }
    }

    package static func environmentDetailsRows(
        profileEnvironment: [String: String],
        extraCurrentEnvironment: [String: String]
    ) -> [EnvironmentDetailsRow] {
        var rows: [EnvironmentDetailsRow] = []
        let trackedInProfile = filtered(profileEnvironment)

        for key in orderedKeys(from: trackedInProfile) {
            guard let value = trackedInProfile[key] else {
                continue
            }

            rows.append(
                EnvironmentDetailsRow(
                    name: key,
                    value: value,
                    kind: .trackedInProfile,
                    id: "\(key)-trackedInProfile"
                )
            )
        }

        let untrackedProfileKeys = profileEnvironment.keys
            .filter { !isManagedKey($0) }
            .sorted()
        for key in untrackedProfileKeys {
            guard let value = profileEnvironment[key] else {
                continue
            }

            rows.append(
                EnvironmentDetailsRow(
                    name: key,
                    value: value,
                    kind: .notTrackedBySwitcher,
                    id: "\(key)-notTrackedBySwitcher"
                )
            )
        }

        for key in orderedKeys(from: extraCurrentEnvironment) {
            guard trackedInProfile[key] == nil,
                  let value = extraCurrentEnvironment[key] else {
                continue
            }

            rows.append(
                EnvironmentDetailsRow(
                    name: key,
                    value: value,
                    kind: .notTrackedHere,
                    id: "\(key)-notTrackedHere"
                )
            )
        }

        return rows
    }
}

package struct ProfileConfiguration: Codable {
    package var version: Int
    package var profiles: [ClaudeProfile]
}

package struct ProfileIndex: Codable {
    package var version: Int
}

package struct ClaudeProfile: Codable, Identifiable, Hashable {
    package var id: String
    package var description: String?
    package var env: [String: String]

    enum CodingKeys: String, CodingKey {
        case description
        case env
    }

    package init(id: String, description: String?, env: [String: String]) {
        self.id = id
        self.description = description
        self.env = env
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = ""
        description = try container.decodeIfPresent(String.self, forKey: .description)
        env = try container.decode([String: String].self, forKey: .env)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(env, forKey: .env)
    }

    package var managedEnvironment: [String: String] {
        ManagedEnvironment.filtered(env)
    }
}

package struct EnvironmentEntry: Codable, Hashable {
    package var name: String
    package var value: String
}

package enum EnvironmentDetailsRowKind: Hashable {
    case trackedInProfile
    case notTrackedBySwitcher
    case notTrackedHere

    package var isStruckThrough: Bool {
        switch self {
        case .trackedInProfile:
            return false
        case .notTrackedBySwitcher, .notTrackedHere:
            return true
        }
    }

    package var badgeText: String? {
        switch self {
        case .trackedInProfile:
            return nil
        case .notTrackedBySwitcher:
            return "Not tracked"
        case .notTrackedHere:
            return "Not tracked here"
        }
    }
}

package struct EnvironmentDetailsRow: Hashable {
    package var name: String
    package var value: String
    package var kind: EnvironmentDetailsRowKind
    package var id: String

    package var isStruckThrough: Bool {
        kind.isStruckThrough
    }

    package init(name: String, value: String, kind: EnvironmentDetailsRowKind, id: String) {
        self.name = name
        self.value = value
        self.kind = kind
        self.id = id
    }
}

package struct AppState: Codable {
    package var lastAppliedProfileId: String?
    package var lastAppliedAt: Date?
}

package enum CurrentProfileStatus: Equatable {
    case matched(ClaudeProfile)
    case unmatched
}

package enum ChangeKind: String {
    case added
    case updated
    case removed
}

package struct TargetChange: Identifiable, Hashable {
    package var id: String { key }
    package var key: String
    package var oldValue: String?
    package var newValue: String?
    package var kind: ChangeKind
}

package enum TargetKind: String, CaseIterable, Identifiable {
    case terminal
    case vscode
    case claude

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .vscode: return "VSCode"
        case .claude: return "Claude Code"
        }
    }

    package var manualFollowUp: String {
        switch self {
        case .terminal:
            return "Open a new shell session after applying."
        case .vscode:
            return "Reload or restart the editor if it keeps stale values."
        case .claude:
            return "Restart Claude Code if the current session does not pick up the new env."
        }
    }
}

package struct TargetPreview: Identifiable {
    package var id: String { target.id }
    package var target: TargetKind
    package var fileURL: URL
    package var changes: [TargetChange]
    package var currentEnvironment: [String: String] = [:]
    package var declaredEnvironment: [String: String] = [:]
    package var desiredEnvironment: [String: String] = [:]
    package var comparedKeyCount: Int = 0
    package var willCreateFile: Bool
    package var manualFollowUp: String
    package var backupURL: URL?
    package var backupURLs: [URL] = []
    package var errorMessage: String?
    package var applied: Bool = false
}

extension TargetPreview {
    package var addedCount: Int {
        changes.filter { $0.kind == .added }.count
    }

    package var updatedCount: Int {
        changes.filter { $0.kind == .updated }.count
    }

    package var removedCount: Int {
        changes.filter { $0.kind == .removed }.count
    }

    package var unchangedCount: Int {
        unchangedEntries.count
    }

    package var untouchedCount: Int {
        untouchedEntries.count
    }

    package var unchangedEntries: [EnvironmentEntry] {
        ManagedEnvironment.orderedKeys(from: declaredEnvironment).compactMap { key in
            guard let currentValue = currentEnvironment[key],
                  let declaredValue = declaredEnvironment[key],
                  let desiredValue = desiredEnvironment[key],
                  currentValue == declaredValue,
                  declaredValue == desiredValue else {
                return nil
            }

            return EnvironmentEntry(name: key, value: currentValue)
        }
    }

    package var untouchedEntries: [EnvironmentEntry] {
        let untouchedEnvironment = currentEnvironment.filter { key, currentValue in
            guard declaredEnvironment[key] == nil,
                  let desiredValue = desiredEnvironment[key] else {
                return false
            }

            return currentValue == desiredValue
        }

        return ManagedEnvironment.orderedKeys(from: untouchedEnvironment).compactMap { key in
            untouchedEnvironment[key].map { EnvironmentEntry(name: key, value: $0) }
        }
    }

    package var totalChangeCount: Int {
        changes.count
    }
}

package struct ApplyReport {
    package var previews: [TargetPreview]

    package var failureCount: Int {
        previews.filter { $0.errorMessage != nil }.count
    }
}

package enum BackupTargetStatus: String, Codable {
    case backedUp = "backed_up"
    case createdWithoutBackup = "created_without_backup"
    case unchanged
    case failed
}

package struct BackupManifestTarget: Codable {
    package var target: String
    package var title: String
    package var status: BackupTargetStatus
    package var path: String
    package var backupFiles: [String]
    package var error: String?
}

package struct BackupManifest: Codable {
    package var createdAt: String
    package var profileId: String
    package var targets: [BackupManifestTarget]
}

package func buildDistinctPathSummaries(for previews: [TargetPreview]) -> [String: String] {
    let componentsByID = Dictionary(uniqueKeysWithValues: previews.map { preview in
        (
            preview.id,
            preview.fileURL.pathComponents.filter { $0 != "/" }
        )
    })

    return Dictionary(uniqueKeysWithValues: previews.map { preview in
        let components = componentsByID[preview.id] ?? [preview.fileURL.lastPathComponent]
        let suffixLength = shortestDistinctSuffixLength(
            for: preview.id,
            among: componentsByID
        )
        let suffix = components.suffix(suffixLength).joined(separator: "/")
        return (preview.id, ".../" + suffix)
    })
}

private func shortestDistinctSuffixLength(
    for previewID: String,
    among componentsByID: [String: [String]]
) -> Int {
    guard let targetComponents = componentsByID[previewID], !targetComponents.isEmpty else {
        return 1
    }

    for suffixLength in 1...targetComponents.count {
        let targetSuffix = targetComponents.suffix(suffixLength)
        let isDistinct = componentsByID.allSatisfy { otherID, otherComponents in
            guard otherID != previewID else {
                return true
            }

            return otherComponents.suffix(suffixLength) != targetSuffix
        }

        if isDistinct {
            return suffixLength
        }
    }

    return targetComponents.count
}
