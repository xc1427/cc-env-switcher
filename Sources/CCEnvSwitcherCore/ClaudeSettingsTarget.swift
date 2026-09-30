import Foundation

package struct ClaudeSettingsTarget: TargetWriter {
    package let target: TargetKind = .claude
    package let fileURL: URL

    package init(fileURL: URL) {
        self.fileURL = fileURL
    }

    package func preview(for profile: ClaudeProfile) throws -> TargetPreview {
        let fileManager = FileManager.default
        let oldEnvironment = try currentManagedEnvironment()
        var newEnvironment = oldEnvironment
        for (key, value) in profile.managedEnvironment {
            newEnvironment[key] = value
        }
        let comparedKeyCount = comparisonKeyCount(old: oldEnvironment, new: newEnvironment)

        return TargetPreview(
            target: target,
            fileURL: fileURL,
            changes: makeChanges(old: oldEnvironment, new: newEnvironment),
            currentEnvironment: oldEnvironment,
            declaredEnvironment: profile.managedEnvironment,
            desiredEnvironment: newEnvironment,
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
        let object = try loadObject()
        let existingEnv = (object["env"] as? [String: String]) ?? [:]
        let oldManaged = ManagedEnvironment.filtered(existingEnv)
        var newManaged = oldManaged
        newManaged.merge(profile.managedEnvironment) { _, new in new }
        let changes = makeChanges(old: oldManaged, new: newManaged)
        let comparedKeyCount = comparisonKeyCount(old: oldManaged, new: newManaged)

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

        guard !changes.isEmpty || !fileManager.fileExists(atPath: fileURL.path) else {
            return preview
        }

        let backupURL = try backupService.backupIfNeeded(for: target, sourceURL: fileURL, in: backupRun)
        var updatedObject = object
        var updatedEnv = existingEnv

        for (key, value) in newManaged {
            updatedEnv[key] = value
        }

        updatedObject["env"] = updatedEnv
        let data = try JSONSerialization.data(
            withJSONObject: updatedObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try write(data: data, to: fileURL)

        preview.backupURL = backupURL
        preview.backupURLs = backupURL.map { [$0] } ?? []
        preview.applied = true
        return preview
    }

    package func currentManagedEnvironment() throws -> [String: String] {
        let object = try loadObject()
        let env = object["env"] as? [String: String] ?? [:]
        return ManagedEnvironment.filtered(env)
    }

    private func loadObject() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = object as? [String: Any] else {
            throw ValidationError(message: "Claude settings must be a JSON object.")
        }
        if let env = dictionary["env"], !(env is [String: String]) {
            throw ValidationError(message: "Claude settings env must contain string values.")
        }
        return dictionary
    }

    private func write(data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var text = String(decoding: data, as: UTF8.self)
        if !text.hasSuffix("\n") {
            text.append("\n")
        }

        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
