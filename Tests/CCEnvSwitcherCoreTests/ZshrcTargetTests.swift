import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class ZshrcTargetTests: XCTestCase {
    func testCurrentManagedEnvironmentReadsManagedEnvFileWhenHookExists() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let zshrcURL = tempDirectory.appendingPathComponent(".zshrc")
        let envFileURL = tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        try Data(#"source ~/.config/cc-env-switcher/env.sh"#.utf8).write(to: zshrcURL)
        let initialText = """
        export API_TIMEOUT_MS="1"
        export ANTHROPIC_MODEL="claude-sonnet"
        """
        try FileManager.default.createDirectory(at: envFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(initialText.utf8).write(to: envFileURL)

        let target = ZshrcTarget(fileURL: zshrcURL, envFileURL: envFileURL)

        XCTAssertEqual(
            try target.currentManagedEnvironment(),
            [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_MODEL": "claude-sonnet"
            ]
        )
    }

    func testApplyWritesManagedEnvironmentWithoutTouchingOtherZshrcContent() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let zshrcURL = tempDirectory.appendingPathComponent(".zshrc")
        let envFileURL = tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        let initialText = """
        export PATH="/usr/bin"
        export API_TIMEOUT_MS="1"
        """
        try Data(initialText.utf8).write(to: zshrcURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "glink",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "3000000",
                "ANTHROPIC_BASE_URL": "http://127.0.0.1:9339"
            ]
        )

        let target = ZshrcTarget(fileURL: zshrcURL, envFileURL: envFileURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())
        let updated = try String(contentsOf: zshrcURL, encoding: .utf8)
        let managedEnv = try String(contentsOf: envFileURL, encoding: .utf8)

        XCTAssertTrue(updated.contains("export PATH=\"/usr/bin\""))
        XCTAssertTrue(updated.contains("source ~/.config/cc-env-switcher/env.sh"))
        XCTAssertTrue(managedEnv.contains("export API_TIMEOUT_MS=\"3000000\""))
        XCTAssertTrue(managedEnv.contains("export ANTHROPIC_BASE_URL=\"http://127.0.0.1:9339\""))
    }

    func testDetectTrackedVariableConflictsIgnoresCommentsAndHook() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let zshrcURL = tempDirectory.appendingPathComponent(".zshrc")
        let envFileURL = tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        let initialText = """
          # export ANTHROPIC_BASE_URL="commented"
        source ~/.config/cc-env-switcher/env.sh
        export ANTHROPIC_BASE_URL="https://old.example"
        API_TIMEOUT_MS="5000"
        """
        try Data(initialText.utf8).write(to: zshrcURL)

        XCTAssertEqual(
            try ZshrcTarget(fileURL: zshrcURL, envFileURL: envFileURL).detectedTrackedVariableConflicts(),
            ["ANTHROPIC_BASE_URL", "API_TIMEOUT_MS"]
        )
    }

    func testPreviewUsesManagedEnvFileInsteadOfInlineTrackedExports() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let zshrcURL = tempDirectory.appendingPathComponent(".zshrc")
        let envFileURL = tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        let initialText = """
        export PATH="/usr/bin"
        export ANTHROPIC_API_KEY="existing-key"
        source ~/.config/cc-env-switcher/env.sh
        """
        try Data(initialText.utf8).write(to: zshrcURL)
        try FileManager.default.createDirectory(at: envFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"export API_TIMEOUT_MS=\"7\""#.utf8).write(to: envFileURL)

        let profile = ClaudeProfile(
            id: "minimal",
            description: nil,
            env: ["API_TIMEOUT_MS": "8"]
        )

        let target = ZshrcTarget(fileURL: zshrcURL, envFileURL: envFileURL)
        let preview = try target.preview(for: profile)

        XCTAssertEqual(preview.totalChangeCount, 1)
        XCTAssertEqual(preview.changes.first?.key, "API_TIMEOUT_MS")
    }

    func testApplyKeepsExistingTrackedExportsThatProfileDoesNotOverride() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let zshrcURL = tempDirectory.appendingPathComponent(".zshrc")
        let envFileURL = tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh")
        let initialText = """
        export ANTHROPIC_BASE_URL="https://old.example"
        export CLAUDE_CODE_1M_CONTEXT="1"
        """
        try Data("source ~/.config/cc-env-switcher/env.sh\n".utf8).write(to: zshrcURL)
        try FileManager.default.createDirectory(at: envFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(initialText.utf8).write(to: envFileURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "partial",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://new.example"]
        )

        let target = ZshrcTarget(fileURL: zshrcURL, envFileURL: envFileURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())
        let updated = try String(contentsOf: envFileURL, encoding: .utf8)

        XCTAssertTrue(updated.contains("export ANTHROPIC_BASE_URL=\"https://new.example\""))
        XCTAssertTrue(updated.contains("export CLAUDE_CODE_1M_CONTEXT=\"1\""))
    }
}
