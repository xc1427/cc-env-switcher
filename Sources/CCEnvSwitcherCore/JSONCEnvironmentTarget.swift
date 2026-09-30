import Foundation

package struct JSONCEnvironmentTarget: TargetWriter {
    package let target: TargetKind
    package let fileURL: URL

    private let propertyName = "claudeCode.environmentVariables"

    package init(target: TargetKind, fileURL: URL) {
        self.target = target
        self.fileURL = fileURL
    }

    package func currentManagedEnvironment() throws -> [String: String] {
        let text = try readTextIfPresent(at: fileURL, fallback: "{\n}\n")
        let existingEntries = try currentEntries(in: text)
        return Dictionary(
            uniqueKeysWithValues: existingEntries
                .filter { ManagedEnvironment.isManagedKey($0.name) }
                .map { ($0.name, $0.value) }
        )
    }

    package func preview(for profile: ClaudeProfile) throws -> TargetPreview {
        let fileManager = FileManager.default
        let text = try readTextIfPresent(at: fileURL, fallback: "{\n}\n")
        let existingEntries = try currentEntries(in: text)
        let mergedEntries = merge(existingEntries: existingEntries, with: profile.managedEnvironment)
        let oldManaged = try currentManagedEnvironment()
        let newManaged = Dictionary(uniqueKeysWithValues: mergedEntries.filter { ManagedEnvironment.isManagedKey($0.name) }.map { ($0.name, $0.value) })
        let comparedKeyCount = comparisonKeyCount(old: oldManaged, new: newManaged)

        return TargetPreview(
            target: target,
            fileURL: fileURL,
            changes: makeChanges(old: oldManaged, new: newManaged),
            currentEnvironment: oldManaged,
            declaredEnvironment: profile.managedEnvironment,
            desiredEnvironment: newManaged,
            comparedKeyCount: comparedKeyCount,
            willCreateFile: !fileManager.fileExists(atPath: fileURL.path),
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: nil,
            applied: false
        )
    }

    package func apply(profile: ClaudeProfile, backupService: BackupService, backupRun: BackupRun) throws -> TargetPreview {
        let fileManager = FileManager.default
        let text = try readTextIfPresent(at: fileURL, fallback: "{\n}\n")
        let existingEntries = try currentEntries(in: text)
        let mergedEntries = merge(existingEntries: existingEntries, with: profile.managedEnvironment)
        let oldManaged = try currentManagedEnvironment()
        let newManaged = Dictionary(uniqueKeysWithValues: mergedEntries.filter { ManagedEnvironment.isManagedKey($0.name) }.map { ($0.name, $0.value) })
        let changes = makeChanges(old: oldManaged, new: newManaged)
        let comparedKeyCount = comparisonKeyCount(old: oldManaged, new: newManaged)
        let propertyExists = try JSONCDocument(text).range(of: propertyName) != nil

        var preview = TargetPreview(
            target: target,
            fileURL: fileURL,
            changes: changes,
            currentEnvironment: oldManaged,
            declaredEnvironment: profile.managedEnvironment,
            desiredEnvironment: newManaged,
            comparedKeyCount: comparedKeyCount,
            willCreateFile: !fileManager.fileExists(atPath: fileURL.path),
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: nil,
            applied: false
        )

        guard !changes.isEmpty || !propertyExists else {
            return preview
        }

        let backupURL = try backupService.backupIfNeeded(for: target, sourceURL: fileURL, in: backupRun)
        let updatedText = try update(text: text, entries: mergedEntries)
        try write(text: updatedText, to: fileURL)

        preview.backupURL = backupURL
        preview.backupURLs = backupURL.map { [$0] } ?? []
        preview.applied = true
        return preview
    }

    private func currentEntries(in text: String) throws -> [EnvironmentEntry] {
        let document = try JSONCDocument(text)
        guard try document.range(of: propertyName) != nil else { return [] }
        guard let rawEntries = document.object[propertyName] as? [[String: Any]] else {
            throw ValidationError(message: "VSCode environmentVariables must be an array of name/value objects.")
        }
        var seen = Set<String>()
        return try rawEntries.map { item in
            guard let name = item["name"] as? String, let value = item["value"] as? String else {
                throw ValidationError(message: "VSCode environment entries require string name and value fields.")
            }
            guard seen.insert(name).inserted else {
                throw ValidationError(message: "Duplicate VSCode environment variable: \(name)")
            }
            return EnvironmentEntry(name: name, value: value)
        }
    }

    private func merge(existingEntries: [EnvironmentEntry], with managedEnvironment: [String: String]) -> [EnvironmentEntry] {
        var result: [EnvironmentEntry] = []
        var seenManagedKeys = Set<String>()

        for entry in existingEntries {
            if ManagedEnvironment.isManagedKey(entry.name) {
                if let replacement = managedEnvironment[entry.name] {
                    result.append(EnvironmentEntry(name: entry.name, value: replacement))
                    seenManagedKeys.insert(entry.name)
                } else {
                    result.append(entry)
                }
            } else {
                result.append(entry)
            }
        }

        for entry in ManagedEnvironment.orderedEntries(from: managedEnvironment) where !seenManagedKeys.contains(entry.name) {
            result.append(entry)
        }

        return result
    }

    private func update(text: String, entries: [EnvironmentEntry]) throws -> String {
        let data = try JSONEncoder().encode(entries)
        let objects = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return try JSONCDocument(text).replacing(propertyName, with: String(decoding: pretty, as: UTF8.self))
    }

    private func write(text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
