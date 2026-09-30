import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class ApplyServiceTests: XCTestCase {
    func testManagedEnvironmentIncludesAnthropicPrefixKeys() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_MODEL": "claude-sonnet",
                "ANTHROPIC_BASE_URL": "https://alpha.example"
            ]
        )

        XCTAssertEqual(
            profile.managedEnvironment,
            [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_MODEL": "claude-sonnet",
                "ANTHROPIC_BASE_URL": "https://alpha.example"
            ]
        )
    }

    func testManagedEnvironmentIncludesExplicitClaudeCodeManagedKeys() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: [
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                "CLAUDE_CODE_EXPERIMENTAL_FLAG": "on",
                "OTHER_FLAG": "off"
            ]
        )

        XCTAssertEqual(
            profile.managedEnvironment,
            [
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
                "CLAUDE_CODE_EXPERIMENTAL_FLAG": "on"
            ]
        )
    }

    func testManagedEnvironmentIncludesClaudeCodePrefixKeys() {
        let values = [
            "CLAUDE_CODE_1M_CONTEXT": "1",
            "CLAUDE_CODE_FOO": "bar",
            "UNRELATED_KEY": "keep"
        ]

        let filtered = ManagedEnvironment.filtered(values)

        XCTAssertEqual(filtered["CLAUDE_CODE_1M_CONTEXT"], "1")
        XCTAssertEqual(filtered["CLAUDE_CODE_FOO"], "bar")
        XCTAssertNil(filtered["UNRELATED_KEY"])
    }

    func testDetectCurrentProfileStatusReturnsUnmatchedWhenAllTargetsAreEmpty() {
        let service = makeService(environments: [[:], [:], [:]])
        let profile = ClaudeProfile(id: "alpha", description: nil, env: ["API_TIMEOUT_MS": "1"])

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .unmatched)
    }

    func testDetectCurrentProfileStatusReturnsMatchedWhenAllTargetsMatchSameProfile() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_BASE_URL": "https://alpha.example"
            ]
        )
        let service = makeService(environments: Array(repeating: profile.managedEnvironment, count: 3))

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .matched(profile))
    }

    func testDetectCurrentProfileStatusReturnsMatchedWhenOneTargetHasExtraManagedKeys() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_BASE_URL": "https://alpha.example"
            ]
        )
        let matchingEnvironment = profile.managedEnvironment
        let targetWithExtraManagedKey = matchingEnvironment.merging(
            [
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
            ],
            uniquingKeysWith: { _, newValue in newValue }
        )
        let service = makeService(
            environments: [
                matchingEnvironment,
                matchingEnvironment,
                targetWithExtraManagedKey
            ]
        )

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .matched(profile))
    }

    func testDetectCurrentProfileStatusReturnsMatchedWhenTargetsHaveDifferentExtraManagedKeys() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: [
                "API_TIMEOUT_MS": "1",
                "ANTHROPIC_BASE_URL": "https://alpha.example"
            ]
        )
        let service = makeService(
            environments: [
                profile.managedEnvironment.merging(
                    [
                        "ANTHROPIC_SMALL_FAST_MODEL": "fast"
                    ],
                    uniquingKeysWith: { _, newValue in newValue }
                ),
                profile.managedEnvironment.merging(
                    [
                        "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
                    ],
                    uniquingKeysWith: { _, newValue in newValue }
                ),
                profile.managedEnvironment.merging(
                    [
                        "ANTHROPIC_SMALL_FAST_MODEL": "fast",
                        "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
                    ],
                    uniquingKeysWith: { _, newValue in newValue }
                )
            ]
        )

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .matched(profile))
    }

    func testDetectCurrentProfileStatusReturnsUnmatchedWhenTargetsAlignButNoProfileMatches() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: ["API_TIMEOUT_MS": "1"]
        )
        let custom = ["API_TIMEOUT_MS": "999"]
        let service = makeService(environments: Array(repeating: custom, count: 3))

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .unmatched)
    }

    func testDetectCurrentProfileStatusReturnsUnmatchedWhenTargetsDisagree() {
        let alpha = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: ["API_TIMEOUT_MS": "1"]
        )
        let beta = ClaudeProfile(
            id: "beta",
            description: nil,
            env: ["API_TIMEOUT_MS": "2"]
        )
        let service = makeService(environments: [alpha.managedEnvironment, alpha.managedEnvironment, beta.managedEnvironment])

        let status = service.detectCurrentProfileStatus(in: [alpha, beta])

        XCTAssertEqual(status, .unmatched)
    }

    func testDetectCurrentProfilePrefersMostSpecificMatchingProfile() {
        let general = ClaudeProfile(
            id: "general",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://example.com"]
        )
        let specific = ClaudeProfile(
            id: "specific",
            description: nil,
            env: [
                "ANTHROPIC_BASE_URL": "https://example.com",
                "ANTHROPIC_AUTH_TOKEN": "token"
            ]
        )

        let environment = [
            "ANTHROPIC_BASE_URL": "https://example.com",
            "ANTHROPIC_AUTH_TOKEN": "token",
            "CLAUDE_CODE_1M_CONTEXT": "1"
        ]
        let service = makeService(environments: Array(repeating: environment, count: 3))

        XCTAssertEqual(service.detectCurrentProfile(in: [general, specific])?.id, "specific")
    }

    func testDetectCurrentProfilePrefersMostSpecificMatchingProfileWhenTargetsHaveDifferentExtraManagedKeys() {
        let general = ClaudeProfile(
            id: "general",
            description: nil,
            env: ["ANTHROPIC_BASE_URL": "https://example.com"]
        )
        let specific = ClaudeProfile(
            id: "specific",
            description: nil,
            env: [
                "ANTHROPIC_BASE_URL": "https://example.com",
                "ANTHROPIC_AUTH_TOKEN": "token"
            ]
        )

        let service = makeService(
            environments: [
                [
                    "ANTHROPIC_BASE_URL": "https://example.com",
                    "ANTHROPIC_AUTH_TOKEN": "token",
                    "ANTHROPIC_SMALL_FAST_MODEL": "fast"
                ],
                [
                    "ANTHROPIC_BASE_URL": "https://example.com",
                    "ANTHROPIC_AUTH_TOKEN": "token",
                    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
                ],
                [
                    "ANTHROPIC_BASE_URL": "https://example.com",
                    "ANTHROPIC_AUTH_TOKEN": "token",
                    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
                ]
            ]
        )

        XCTAssertEqual(service.detectCurrentProfile(in: [general, specific])?.id, "specific")
    }

    func testDetectCurrentProfileStatusReturnsUnmatchedWhenTargetsAlignButNoProfileMatchesWithExtraTrackedKeys() {
        let profile = ClaudeProfile(
            id: "alpha",
            description: nil,
            env: ["API_TIMEOUT_MS": "1"]
        )
        let custom = [
            "API_TIMEOUT_MS": "999",
            "CLAUDE_CODE_1M_CONTEXT": "1"
        ]
        let service = makeService(environments: Array(repeating: custom, count: 3))

        let status = service.detectCurrentProfileStatus(in: [profile])

        XCTAssertEqual(status, .unmatched)
    }

    private func makeService(environments: [[String: String]]) -> ApplyService {
        let writers = environments.enumerated().map { index, environment in
            StubTargetWriter(
                target: TargetKind.allCases[index],
                fileURL: URL(fileURLWithPath: "/tmp/\(index)"),
                environment: environment
            )
        }
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let paths = AppPaths(
            homeDirectory: tempDirectory,
            applicationSupportDirectory: tempDirectory.appendingPathComponent("support", isDirectory: true),
            profilesDirectoryURL: tempDirectory.appendingPathComponent("support/profiles", isDirectory: true),
            profilesIndexURL: tempDirectory.appendingPathComponent("support/profiles/index.json"),
            stateURL: tempDirectory.appendingPathComponent("support/state.json"),
            backupDirectoryURL: tempDirectory.appendingPathComponent("support/backups", isDirectory: true),
            zshrcURL: tempDirectory.appendingPathComponent(".zshrc"),
            managedShellEnvironmentURL: tempDirectory.appendingPathComponent(".config/cc-env-switcher/env.sh"),
            vscodeSettingsURL: tempDirectory.appendingPathComponent("Code/settings.json"),
            claudeSettingsURL: tempDirectory.appendingPathComponent(".claude/settings.json")
        )
        let store = ProfileStore(paths: paths)

        return ApplyService(
            writers: writers,
            backupService: BackupService(backupDirectoryURL: tempDirectory.appendingPathComponent("backups", isDirectory: true)),
            profileStore: store
        )
    }
}

private struct StubTargetWriter: TargetWriter {
    let target: TargetKind
    let fileURL: URL
    let environment: [String: String]

    func currentManagedEnvironment() throws -> [String: String] {
        environment
    }

    func preview(for profile: ClaudeProfile) throws -> TargetPreview {
        TargetPreview(
            target: target,
            fileURL: fileURL,
            changes: [],
            willCreateFile: false,
            manualFollowUp: target.manualFollowUp,
            backupURL: nil,
            errorMessage: nil
        )
    }

    func apply(profile: ClaudeProfile, backupService: BackupService, backupRun: BackupRun) throws -> TargetPreview {
        try preview(for: profile)
    }
}
