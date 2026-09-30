import Foundation

package struct BackupRun {
    package let createdAt: Date
    package let timestamp: String
    package let directoryURL: URL
}

package final class BackupService {
    private let backupRetentionLimit = 20
    private let backupDirectoryURL: URL
    private let fileManager: FileManager
    private let dateProvider: () -> Date
    private let formatter: DateFormatter

    package init(
        backupDirectoryURL: URL,
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.backupDirectoryURL = backupDirectoryURL
        self.fileManager = fileManager
        self.dateProvider = dateProvider
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        self.formatter = formatter
    }

    package func makeRun() -> BackupRun {
        let now = dateProvider()
        let timestamp = formatter.string(from: now)
        return BackupRun(
            createdAt: now,
            timestamp: timestamp,
            directoryURL: backupDirectoryURL.appendingPathComponent(timestamp, isDirectory: true)
        )
    }

    package func backupIfNeeded(for target: TargetKind, sourceURL: URL) throws -> URL? {
        try backupIfNeeded(for: target, sourceURL: sourceURL, in: makeRun())
    }

    package func backupIfNeeded(for target: TargetKind, sourceURL: URL, in run: BackupRun) throws -> URL? {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        try fileManager.createDirectory(at: backupDirectoryURL, withIntermediateDirectories: true)

        let originalContents = try Data(contentsOf: sourceURL)
        let destinationURL = nextBackupURL(for: target, sourceURL: sourceURL, in: run)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalContents.write(to: destinationURL, options: .atomic)
        try pruneBackupsIfNeeded(for: target)
        return destinationURL
    }

    package func writeManifest(for run: BackupRun, profileID: String, previews: [TargetPreview]) throws -> URL {
        try fileManager.createDirectory(at: run.directoryURL, withIntermediateDirectories: true)

        let manifestObject: [String: Any] = [
            "createdAt": run.timestamp,
            "profileId": profileID,
            "targets": previews.map { preview in
                var targetObject: [String: Any] = [
                    "target": preview.target.rawValue,
                    "title": preview.target.title,
                    "status": status(for: preview).rawValue,
                    "path": preview.fileURL.path,
                    "backupFiles": preview.backupURLs.map(\.lastPathComponent).sorted()
                ]
                if let error = preview.errorMessage {
                    targetObject["error"] = error
                }
                return targetObject
            }
        ]

        let data = try JSONSerialization.data(
            withJSONObject: manifestObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let manifestURL = nextManifestURL(in: run.directoryURL)
        try data.write(to: manifestURL, options: .atomic)
        return manifestURL
    }

    private func pruneBackupsIfNeeded(for target: TargetKind) throws {
        let backups = try existingBackups(for: target)
        let excessCount = backups.count - backupRetentionLimit

        guard excessCount > 0 else {
            return
        }

        for backup in backups.prefix(excessCount) {
            try fileManager.removeItem(at: backup)
            try removeEmptyBackupDirectories(startingAt: backup.deletingLastPathComponent())
        }
    }

    private func existingBackups(for target: TargetKind) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: backupDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && isBackupFileName(url.lastPathComponent, for: target)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func backupExtension(for sourceURL: URL) -> String {
        if sourceURL.pathExtension.isEmpty {
            let fileName = sourceURL.lastPathComponent
            if fileName.hasPrefix(".") {
                return String(fileName.dropFirst())
            }

            return "backup"
        }

        return sourceURL.pathExtension
    }

    private func nextBackupURL(for target: TargetKind, sourceURL: URL, in run: BackupRun) -> URL {
        let fileExtension = backupExtension(for: sourceURL)
        let baseName = "\(run.timestamp)-\(target.rawValue)"
        let backupRunDirectoryURL = run.directoryURL
        let preferredURL = backupRunDirectoryURL.appendingPathComponent("\(baseName).\(fileExtension)")

        guard !fileManager.fileExists(atPath: preferredURL.path) else {
            var counter = 2
            while true {
                let candidateURL = backupRunDirectoryURL.appendingPathComponent("\(baseName)-\(counter).\(fileExtension)")
                if !fileManager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
                counter += 1
            }
        }

        return preferredURL
    }

    private func nextManifestURL(in directoryURL: URL) -> URL {
        let preferredURL = directoryURL.appendingPathComponent("manifest.json")
        guard !fileManager.fileExists(atPath: preferredURL.path) else {
            var counter = 2
            while true {
                let candidateURL = directoryURL.appendingPathComponent("manifest-\(counter).json")
                if !fileManager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
                counter += 1
            }
        }

        return preferredURL
    }

    private func status(for preview: TargetPreview) -> BackupTargetStatus {
        if preview.errorMessage != nil {
            return .failed
        }

        if !preview.backupURLs.isEmpty {
            return .backedUp
        }

        if preview.applied && preview.willCreateFile {
            return .createdWithoutBackup
        }

        return .unchanged
    }

    private func isBackupFileName(_ fileName: String, for target: TargetKind) -> Bool {
        let pattern = #"\d{4}-\d{2}-\d{2}-\d{6}-\#(target.rawValue)(?:-\d+)?\.[^.]+$"#
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }

    private func removeEmptyBackupDirectories(startingAt directoryURL: URL) throws {
        var currentDirectoryURL = directoryURL

        while currentDirectoryURL.path != backupDirectoryURL.path {
            let contents = try fileManager.contentsOfDirectory(at: currentDirectoryURL, includingPropertiesForKeys: nil)
            guard contents.isEmpty else {
                return
            }

            try fileManager.removeItem(at: currentDirectoryURL)
            currentDirectoryURL = currentDirectoryURL.deletingLastPathComponent()
        }
    }
}
