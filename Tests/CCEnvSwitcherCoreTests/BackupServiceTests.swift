import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class BackupServiceTests: XCTestCase {
    func testBackupIfNeededKeepsLatestTwentyBackupsPerTarget() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent(".zshrc")
        let backupDirectoryURL = tempDirectory.appendingPathComponent("backups", isDirectory: true)
        var nextDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backupService = BackupService(
            backupDirectoryURL: backupDirectoryURL,
            dateProvider: {
                defer { nextDate.addTimeInterval(1) }
                return nextDate
            }
        )

        var createdBackupPaths: [String] = []

        for revision in 1...22 {
            try Data("revision-\(revision)\n".utf8).write(to: sourceURL, options: .atomic)
            let backupURL = try XCTUnwrap(backupService.backupIfNeeded(for: .terminal, sourceURL: sourceURL))
            createdBackupPaths.append(relativeBackupPath(for: backupURL, under: backupDirectoryURL))
        }

        let savedBackupPaths = try backupPaths(in: backupDirectoryURL)

        XCTAssertEqual(savedBackupPaths.count, 20)
        XCTAssertEqual(savedBackupPaths, Array(createdBackupPaths.suffix(20)).sorted())
        XCTAssertFalse(savedBackupPaths.contains(createdBackupPaths[0]))
        XCTAssertFalse(savedBackupPaths.contains(createdBackupPaths[1]))
        XCTAssertEqual(
            savedBackupPaths.first,
            expectedBackupPath(
                date: Date(timeIntervalSince1970: 1_700_000_002),
                identifier: "terminal",
                sourceURL: sourceURL
            )
        )
        XCTAssertEqual(
            savedBackupPaths.last,
            expectedBackupPath(
                date: Date(timeIntervalSince1970: 1_700_000_021),
                identifier: "terminal",
                sourceURL: sourceURL
            )
        )
    }

    func testBackupIfNeededRotatesTargetsIndependently() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("settings.json")
        let backupDirectoryURL = tempDirectory.appendingPathComponent("backups", isDirectory: true)
        var nextDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backupService = BackupService(
            backupDirectoryURL: backupDirectoryURL,
            dateProvider: {
                defer { nextDate.addTimeInterval(1) }
                return nextDate
            }
        )

        for revision in 1...21 {
            try Data("vscode-\(revision)\n".utf8).write(to: sourceURL, options: .atomic)
            _ = try backupService.backupIfNeeded(for: .vscode, sourceURL: sourceURL)
        }

        for revision in 1...3 {
            try Data("claude-\(revision)\n".utf8).write(to: sourceURL, options: .atomic)
            _ = try backupService.backupIfNeeded(for: .claude, sourceURL: sourceURL)
        }

        let backupPaths = try backupPaths(in: backupDirectoryURL)
        let vscodeBackupPaths = backupPaths.filter { isBackupFileName(URL(fileURLWithPath: $0).lastPathComponent, identifier: "vscode") }
        let claudeBackupPaths = backupPaths.filter { isBackupFileName(URL(fileURLWithPath: $0).lastPathComponent, identifier: "claude") }

        XCTAssertEqual(vscodeBackupPaths.count, 20)
        XCTAssertEqual(claudeBackupPaths.count, 3)
    }

    func testBackupIfNeededStoresFullOriginalFileContents() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("settings.json")
        let backupDirectoryURL = tempDirectory.appendingPathComponent("backups", isDirectory: true)
        let backupService = BackupService(
            backupDirectoryURL: backupDirectoryURL,
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let originalContents = """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://before.example",
            "API_TIMEOUT_MS": "3000"
          },
          "hooks": {
            "enabled": true
          }
        }
        """
        try originalContents.write(to: sourceURL, atomically: true, encoding: .utf8)

        let backupURL = try XCTUnwrap(backupService.backupIfNeeded(for: .claude, sourceURL: sourceURL))

        try """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://after.example"
          }
        }
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            relativeBackupPath(for: backupURL, under: backupDirectoryURL),
            expectedBackupPath(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                identifier: "claude",
                sourceURL: sourceURL
            )
        )
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), originalContents)
    }

    func testBackupIfNeededDoesNotOverwriteWhenTwoBackupsShareSameSecond() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let sourceURL = tempDirectory.appendingPathComponent("settings.json")
        let backupDirectoryURL = tempDirectory.appendingPathComponent("backups", isDirectory: true)
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backupService = BackupService(
            backupDirectoryURL: backupDirectoryURL,
            dateProvider: { fixedDate }
        )

        try "first".write(to: sourceURL, atomically: true, encoding: .utf8)
        let firstBackupURL = try XCTUnwrap(backupService.backupIfNeeded(for: .vscode, sourceURL: sourceURL))

        try "second".write(to: sourceURL, atomically: true, encoding: .utf8)
        let secondBackupURL = try XCTUnwrap(backupService.backupIfNeeded(for: .vscode, sourceURL: sourceURL))

        let backupPaths = try backupPaths(in: backupDirectoryURL)
        let expectedTimestamp = timestampString(from: fixedDate)

        XCTAssertEqual(backupPaths.count, 2)
        XCTAssertNotEqual(firstBackupURL.lastPathComponent, secondBackupURL.lastPathComponent)
        XCTAssertEqual(firstBackupURL.deletingLastPathComponent().lastPathComponent, expectedTimestamp)
        XCTAssertEqual(secondBackupURL.deletingLastPathComponent().lastPathComponent, expectedTimestamp)
        XCTAssertEqual(try String(contentsOf: firstBackupURL, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: secondBackupURL, encoding: .utf8), "second")
    }

    private func backupPaths(in directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true
            }
            .map { relativeBackupPath(for: $0, under: directory) }
            .sorted()
    }

    private func expectedBackupPath(date: Date, identifier: String, sourceURL: URL) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"

        let timestamp = formatter.string(from: date)
        return "\(timestamp)/\(timestamp)-\(identifier).\(backupExtension(for: sourceURL))"
    }

    private func backupExtension(for sourceURL: URL) -> String {
        if sourceURL.pathExtension.isEmpty {
            let name = sourceURL.lastPathComponent
            if name.hasPrefix(".") {
                return String(name.dropFirst())
            }
            return "backup"
        }

        return sourceURL.pathExtension
    }

    private func isBackupFileName(_ fileName: String, identifier: String) -> Bool {
        let pattern = #"\d{4}-\d{2}-\d{2}-\d{6}-\#(identifier)(?:-\d+)?\.[^.]+$"#
        return fileName.range(of: pattern, options: .regularExpression) != nil
    }

    private func relativeBackupPath(for backupURL: URL, under directory: URL) -> String {
        let directoryComponents = directory.standardizedFileURL.pathComponents
        let backupComponents = backupURL.standardizedFileURL.pathComponents

        if backupComponents.starts(with: directoryComponents) {
            return backupComponents.dropFirst(directoryComponents.count).joined(separator: "/")
        }

        if backupComponents.first == directory.lastPathComponent {
            return backupComponents.dropFirst().joined(separator: "/")
        }

        return backupURL.lastPathComponent
    }

    private func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
