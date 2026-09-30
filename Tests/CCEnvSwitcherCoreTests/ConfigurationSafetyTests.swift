import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class ConfigurationSafetyTests: XCTestCase {
    func testJSONCHandlesCommentsReorderedFieldsEscapesAndNestedSettings() throws {
        let source = #"""
        {
          /* "claudeCode.environmentVariables": [] */
          "nested": { "claudeCode.environmentVariables": [] },
          "claudeCode.environmentVariables": [
            {"value": "a\tb\u4e2d", "name": "ANTHROPIC_TOKEN"},
          ], // keep this comment
        }
        """#
        try withTarget(source) { target, backup, url in
            XCTAssertEqual(try target.currentManagedEnvironment()["ANTHROPIC_TOKEN"], "a\tb中")
            let value = "quote\" backslash\\ tab\t newline\n"
            _ = try target.apply(profile: ClaudeProfile(id: "test", description: nil, env: ["ANTHROPIC_TOKEN": value]), backupService: backup, backupRun: backup.makeRun())
            XCTAssertEqual(try target.currentManagedEnvironment()["ANTHROPIC_TOKEN"], value)
            let updated = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(updated.contains("// keep this comment"))
            XCTAssertTrue(updated.contains(#""nested": { "claudeCode.environmentVariables": [] }"#))
        }
    }

    func testJSONCInsertsCommaBeforeTrailingLineComment() throws {
        try withTarget("{\n  \"editor.fontSize\": 14 // trailing comment with } and \"quotes\"\n}\n") { target, backup, url in
            _ = try target.apply(profile: ClaudeProfile(id: "test", description: nil, env: ["API_TIMEOUT_MS": "10"]), backupService: backup, backupRun: backup.makeRun())
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("14, // trailing comment"))
            XCTAssertEqual(try target.currentManagedEnvironment()["API_TIMEOUT_MS"], "10")
        }
    }

    func testMalformedAndDuplicateEntriesFailWithoutOverwriting() throws {
        for source in [
            "{bad json",
            #"{"claudeCode.environmentVariables": [{"name":"API_TIMEOUT_MS","value":"1"},{"name":"API_TIMEOUT_MS","value":"2"}]}"#,
            #"{"claudeCode.environmentVariables": [{"name":"API_TIMEOUT_MS","value":2}]}"#,
            #"{"claudeCode.environmentVariables": [], "claudeCode.environmentVariables": []}"#
        ] {
            try withTarget(source) { target, backup, url in
                XCTAssertThrowsError(try target.apply(profile: ClaudeProfile(id: "test", description: nil, env: ["API_TIMEOUT_MS":"3"]), backupService: backup, backupRun: backup.makeRun()))
                XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source)
            }
        }
    }

    func testClaudeApplyReportMatchesOverlayAndSecondApplyDoesNotWrite() throws {
        try withTarget(#"{"env":{"ANTHROPIC_MODEL":"keep","API_TIMEOUT_MS":"1"},"hooks":{}}"#) { _, backup, url in
            let target = ClaudeSettingsTarget(fileURL: url)
            let profile = ClaudeProfile(id: "test", description: nil, env: ["API_TIMEOUT_MS":"2"])
            let before = try target.preview(for: profile)
            let applied = try target.apply(profile: profile, backupService: backup, backupRun: backup.makeRun())
            XCTAssertEqual(before.desiredEnvironment, applied.desiredEnvironment)
            XCTAssertEqual(applied.removedCount, 0)
            XCTAssertEqual(applied.desiredEnvironment["ANTHROPIC_MODEL"], "keep")
            XCTAssertFalse(try target.apply(profile: profile, backupService: backup, backupRun: backup.makeRun()).applied)
        }
    }

    func testUnreadableFileIsNotTreatedAsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try JSONCEnvironmentTarget(target: .vscode, fileURL: directory).currentManagedEnvironment())
        XCTAssertThrowsError(try ZshrcTarget(fileURL: directory, envFileURL: directory.appendingPathComponent("env.sh")).currentManagedEnvironment())
    }

    func testMalformedClaudeEnvironmentDoesNotOverwriteSettings() throws {
        let source = #"{"env":{"API_TIMEOUT_MS":42},"hooks":{}}"#
        try withTarget(source) { _, backup, url in
            let target = ClaudeSettingsTarget(fileURL: url)
            XCTAssertThrowsError(try target.apply(profile: ClaudeProfile(id: "test", description: nil, env: ["API_TIMEOUT_MS":"10"]), backupService: backup, backupRun: backup.makeRun()))
            XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), source)
        }
    }

    private func withTarget(_ text: String, body: (JSONCEnvironmentTarget, BackupService, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("settings.json")
        try Data(text.utf8).write(to: url)
        try body(JSONCEnvironmentTarget(target: .vscode, fileURL: url), BackupService(backupDirectoryURL: directory.appendingPathComponent("backups")), url)
    }
}
