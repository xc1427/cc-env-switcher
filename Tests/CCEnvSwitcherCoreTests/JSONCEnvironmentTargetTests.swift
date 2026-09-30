import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class JSONCEnvironmentTargetTests: XCTestCase {
    func testApplyUpdatesOnlyActiveEnvironmentVariablesArray() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let source = """
        {
          // "claudeCode.environmentVariables": [
          //   {
          //     "name": "ANTHROPIC_BASE_URL",
          //     "value": "https://example.com"
          //   }
          // ],
          "editor.fontSize": 13,
          "claudeCode.environmentVariables": [
            {
              "name": "API_TIMEOUT_MS",
              "value": "1"
            },
            {
              "name": "UNMANAGED_KEEP",
              "value": "yes"
            }
          ]
        }
        """
        try Data(source.utf8).write(to: settingsURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "vercel-ai-gateway",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "30000000",
                "ANTHROPIC_BASE_URL": "https://ai-gateway.vercel.sh"
            ]
        )

        let target = JSONCEnvironmentTarget(target: .vscode, fileURL: settingsURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())
        let updated = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertTrue(updated.contains("\"editor.fontSize\": 13"))
        XCTAssertTrue(updated.contains("\"UNMANAGED_KEEP\""))
        XCTAssertTrue(updated.contains("\"ANTHROPIC_BASE_URL\""))
        XCTAssertFalse(updated.contains("\"value\": \"1\""))
    }

    func testApplyKeepsExistingTrackedEntriesThatProfileDoesNotOverride() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("settings.json")
        let source = """
        {
          "claudeCode.environmentVariables": [
            {
              "name": "ANTHROPIC_BASE_URL",
              "value": "https://old.example"
            },
            {
              "name": "CLAUDE_CODE_1M_CONTEXT",
              "value": "1"
            }
          ]
        }
        """
        try Data(source.utf8).write(to: settingsURL)

        let backupService = BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups"))
        let profile = ClaudeProfile(
            id: "partial",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://new.example"]
        )

        let target = JSONCEnvironmentTarget(target: .vscode, fileURL: settingsURL)
        _ = try target.apply(profile: profile, backupService: backupService, backupRun: backupService.makeRun())
        let updated = try String(contentsOf: settingsURL, encoding: .utf8)

        XCTAssertTrue(updated.contains("\"ANTHROPIC_BASE_URL\""))
        XCTAssertTrue(updated.contains("\"https://new.example\""))
        XCTAssertTrue(updated.contains("\"CLAUDE_CODE_1M_CONTEXT\""))
        XCTAssertEqual(try target.currentManagedEnvironment()["CLAUDE_CODE_1M_CONTEXT"], "1")
    }
}
