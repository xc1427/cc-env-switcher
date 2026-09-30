import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class ClaudeSettingsTargetTests: XCTestCase {
    func testApplyPreservesUnrelatedClaudeSettings() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let source = """
        {
          "enabledPlugins": {
            "yuque-personal:yuque": true
          },
          "env": {
            "API_TIMEOUT_MS": "1",
            "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
          }
        }
        """
        try Data(source.utf8).write(to: settingsURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "glink",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "3000000",
                "ANTHROPIC_BASE_URL": "http://127.0.0.1:9339"
            ]
        )

        let target = ClaudeSettingsTarget(fileURL: settingsURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())

        let data = try Data(contentsOf: settingsURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let env = object?["env"] as? [String: String]
        let plugins = object?["enabledPlugins"] as? [String: Bool]

        XCTAssertEqual(env?["API_TIMEOUT_MS"], "3000000")
        XCTAssertEqual(env?["ANTHROPIC_BASE_URL"], "http://127.0.0.1:9339")
        XCTAssertEqual(env?["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")
        XCTAssertEqual(plugins?["yuque-personal:yuque"], true)
    }

    func testApplyKeepsExistingTrackedEnvKeysThatProfileDoesNotOverride() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let source = """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://old.example",
            "CLAUDE_CODE_1M_CONTEXT": "1"
          }
        }
        """
        try Data(source.utf8).write(to: settingsURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "partial",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://new.example"]
        )

        let target = ClaudeSettingsTarget(fileURL: settingsURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())

        let data = try Data(contentsOf: settingsURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let env = try XCTUnwrap(object["env"] as? [String: String])

        XCTAssertEqual(env["ANTHROPIC_BASE_URL"], "https://new.example")
        XCTAssertEqual(env["CLAUDE_CODE_1M_CONTEXT"], "1")
    }

    func testPreviewKeepsExistingTrackedEnvKeysThatProfileDoesNotOverride() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let source = """
        {
          "env": {
            "ANTHROPIC_BASE_URL": "https://old.example",
            "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
          }
        }
        """
        try Data(source.utf8).write(to: settingsURL)

        let profile = ClaudeProfile(
            id: "partial",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://new.example"]
        )

        let target = ClaudeSettingsTarget(fileURL: settingsURL)
        let preview = try target.preview(for: profile)

        XCTAssertEqual(preview.removedCount, 0)
        XCTAssertEqual(preview.updatedCount, 1)
        XCTAssertEqual(preview.desiredEnvironment["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"], "1")
    }

    func testApplyDoesNotEscapeForwardSlashesInWrittenJSON() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        try Data("{\"env\":{}}\n".utf8).write(to: settingsURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "slash-check",
            description: nil,
            env: [
                "ANTHROPIC_BASE_URL": "https://ai-gateway.vercel.sh",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "anthropic/claude-sonnet-4.6"
            ]
        )

        let target = ClaudeSettingsTarget(fileURL: settingsURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())

        let updated = try String(contentsOf: settingsURL, encoding: .utf8)
        XCTAssertFalse(updated.contains(#"\/"#))
    }
}
