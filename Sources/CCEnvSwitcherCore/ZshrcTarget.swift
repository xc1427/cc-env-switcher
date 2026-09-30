import Foundation

package struct ZshrcTarget: TargetWriter {
    package let target: TargetKind = .terminal
    package let fileURL: URL
    package let envFileURL: URL

    package init(fileURL: URL, envFileURL: URL) {
        self.fileURL = fileURL
        self.envFileURL = envFileURL
    }

    package func currentManagedEnvironment() throws -> [String: String] {
        let zshrcText = try readTextIfPresent(at: fileURL)
        guard hookExists(in: zshrcText),
              FileManager.default.fileExists(atPath: envFileURL.path) else {
            return [:]
        }

        let envText = try String(contentsOf: envFileURL, encoding: .utf8)
        return parseEnvironmentEntries(from: envText)
    }

    package func preview(for profile: ClaudeProfile) throws -> TargetPreview {
        let existingEnvironment = try currentManagedEnvironment()
        let desiredEnvironment = overlayEnvironment(
            existingEnvironment: existingEnvironment,
            overrides: profile.managedEnvironment
        )

        return TargetPreview(
            target: target,
            fileURL: envFileURL,
            changes: makeChanges(old: existingEnvironment, new: desiredEnvironment),
            currentEnvironment: existingEnvironment,
            declaredEnvironment: profile.managedEnvironment,
            desiredEnvironment: desiredEnvironment,
            comparedKeyCount: comparisonKeyCount(old: existingEnvironment, new: desiredEnvironment),
            willCreateFile: !FileManager.default.fileExists(atPath: envFileURL.path),
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: nil,
            applied: false
        )
    }

    package func apply(profile: ClaudeProfile, backupService: BackupService, backupRun: BackupRun) throws -> TargetPreview {
        let zshrcText = try readTextIfPresent(at: fileURL)
        let existingEnvironment = try currentManagedEnvironment()
        let desiredEnvironment = overlayEnvironment(
            existingEnvironment: existingEnvironment,
            overrides: profile.managedEnvironment
        )
        let updatedZshrcText = updateZshrc(text: zshrcText)
        let renderedEnv = renderManagedEnvironment(desiredEnvironment)

        var preview = TargetPreview(
            target: target,
            fileURL: envFileURL,
            changes: makeChanges(old: existingEnvironment, new: desiredEnvironment),
            currentEnvironment: existingEnvironment,
            declaredEnvironment: profile.managedEnvironment,
            desiredEnvironment: desiredEnvironment,
            comparedKeyCount: comparisonKeyCount(old: existingEnvironment, new: desiredEnvironment),
            willCreateFile: !FileManager.default.fileExists(atPath: envFileURL.path),
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: nil,
            applied: false
        )

        let envChanged = renderedEnv != (try readTextIfPresent(at: envFileURL))
        let zshrcChanged = updatedZshrcText != zshrcText
        guard envChanged || zshrcChanged else {
            return preview
        }

        var backupURLs: [URL] = []
        if zshrcChanged {
            if let backupURL = try backupService.backupIfNeeded(for: target, sourceURL: fileURL, in: backupRun) {
                backupURLs.append(backupURL)
            }
        }
        if envChanged {
            if let backupURL = try backupService.backupIfNeeded(for: target, sourceURL: envFileURL, in: backupRun) {
                backupURLs.append(backupURL)
            }
        }

        if zshrcChanged {
            try write(text: updatedZshrcText, to: fileURL)
        }
        if envChanged || !FileManager.default.fileExists(atPath: envFileURL.path) {
            try write(text: renderedEnv, to: envFileURL)
        }

        preview.backupURLs = backupURLs
        preview.backupURL = backupURLs.last
        preview.applied = true
        return preview
    }

    package func detectedTrackedVariableConflicts() throws -> [String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        var conflicts = Set<String>()

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  trimmed != hookLine else {
                continue
            }

            guard let key = assignmentKey(in: trimmed),
                  ManagedEnvironment.isManagedKey(key) else {
                continue
            }

            conflicts.insert(key)
        }

        return conflicts.sorted()
    }

    private var hookLine: String {
        let homeDirectory = fileURL.deletingLastPathComponent()
        let canonicalEnvURL = homeDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        if envFileURL.standardizedFileURL == canonicalEnvURL.standardizedFileURL {
            return "source ~/.config/cc-env-switcher/env.sh"
        }

        return "source \"\(shellEscape(envFileURL.path))\""
    }

    private func hookExists(in text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { rawLine in
            rawLine.trimmingCharacters(in: .whitespaces) == hookLine
        }
    }

    private func assignmentKey(in line: String) -> String? {
        let assignment: Substring
        if line.hasPrefix("export ") {
            assignment = line.dropFirst("export ".count)
        } else {
            assignment = Substring(line)
        }

        guard let equalsIndex = assignment.firstIndex(of: "="), equalsIndex != assignment.startIndex else {
            return nil
        }

        let key = assignment[..<equalsIndex].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty,
              key.first?.isLetter == true || key.first == "_" else {
            return nil
        }

        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } ? key : nil
    }

    private func parseEnvironmentEntries(from text: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("export "),
                  let key = assignmentKey(in: trimmed) else {
                continue
            }

            let assignment = trimmed.dropFirst("export ".count)
            let parts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            values[key] = unquote(parts[1])
        }

        return ManagedEnvironment.filtered(values)
    }

    private func overlayEnvironment(existingEnvironment: [String: String], overrides: [String: String]) -> [String: String] {
        var environment = existingEnvironment
        for (key, value) in overrides {
            environment[key] = value
        }
        return environment
    }

    private func renderManagedEnvironment(_ environment: [String: String]) -> String {
        let lines = ManagedEnvironment.orderedEntries(from: environment).map { entry in
            "export \(entry.name)=\"\(shellEscape(entry.value))\""
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func updateZshrc(text: String) -> String {
        if hookExists(in: text) {
            return text
        }

        var cleanedLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while cleanedLines.last?.isEmpty == true {
            cleanedLines.removeLast()
        }
        var updated = cleanedLines.joined(separator: "\n")

        if !updated.isEmpty && !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        if !updated.isEmpty {
            updated.append("\n")
        }

        updated.append(hookLine)
        updated.append("\n")
        return updated
    }

    private func shellEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    private func unquote(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        } else if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
        }

        return trimmed
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\`", with: "`")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func write(text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
