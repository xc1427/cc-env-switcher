import Foundation
import XCTest
@testable import CCEnvSwitcherCore

final class TargetPreviewTests: XCTestCase {
    func testBuildDistinctPathSummariesUsesShortestDistinguishableSuffixWithEllipsis() {
        let previews = [
            makePreview(target: .terminal, path: "/Users/test/.zshrc"),
            makePreview(target: .vscode, path: "/Users/test/Library/Application Support/Code/User/settings.json"),
            makePreview(target: .claude, path: "/Users/test/.claude/settings.json")
        ]

        let summaries = buildDistinctPathSummaries(for: previews)

        XCTAssertEqual(summaries[TargetKind.terminal.id], ".../.zshrc")
        XCTAssertEqual(summaries[TargetKind.vscode.id], ".../User/settings.json")
        XCTAssertEqual(summaries[TargetKind.claude.id], ".../.claude/settings.json")
    }

    func testChangeCountsReflectAddedUpdatedAndRemovedKeys() {
        let preview = TargetPreview(
            target: .terminal,
            fileURL: URL(fileURLWithPath: "/tmp/.zshrc"),
            changes: [
                TargetChange(key: "ANTHROPIC_AUTH_TOKEN", oldValue: nil, newValue: "1", kind: .added),
                TargetChange(key: "ANTHROPIC_BASE_URL", oldValue: "1", newValue: "2", kind: .updated),
                TargetChange(key: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", oldValue: "3", newValue: nil, kind: .removed),
                TargetChange(key: "ANTHROPIC_DEFAULT_OPUS_MODEL", oldValue: "4", newValue: "5", kind: .updated)
            ],
            currentEnvironment: [
                "API_TIMEOUT_MS": "same-1",
                "ANTHROPIC_ORGANIZATION_ID": "same-2",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "preserved"
            ],
            declaredEnvironment: [
                "API_TIMEOUT_MS": "same-1",
                "ANTHROPIC_ORGANIZATION_ID": "same-2"
            ],
            desiredEnvironment: [
                "ANTHROPIC_AUTH_TOKEN": "1",
                "ANTHROPIC_BASE_URL": "2",
                "ANTHROPIC_DEFAULT_OPUS_MODEL": "5",
                "API_TIMEOUT_MS": "same-1",
                "ANTHROPIC_ORGANIZATION_ID": "same-2",
                "ANTHROPIC_DEFAULT_SONNET_MODEL": "preserved"
            ],
            comparedKeyCount: 6,
            willCreateFile: false,
            manualFollowUp: "Reload shell.",
            backupURL: nil,
            errorMessage: nil
        )

        XCTAssertEqual(preview.addedCount, 1)
        XCTAssertEqual(preview.updatedCount, 2)
        XCTAssertEqual(preview.removedCount, 1)
        XCTAssertEqual(preview.unchangedCount, 2)
        XCTAssertEqual(preview.untouchedCount, 1)
        XCTAssertEqual(preview.totalChangeCount, 4)
    }

    func testRemovedCountStaysTiedToActualDiff() {
        let preview = TargetPreview(
            target: .claude,
            fileURL: URL(fileURLWithPath: "/tmp/settings.json"),
            changes: [
                TargetChange(key: "CLAUDE_CODE_DISABLE_TERMINAL_TITLE", oldValue: "1", newValue: nil, kind: .removed)
            ],
            comparedKeyCount: 1,
            willCreateFile: false,
            manualFollowUp: "Restart Claude Code.",
            backupURL: nil,
            errorMessage: nil
        )

        XCTAssertEqual(preview.removedCount, 1)
    }

    func testEnvironmentDetailsRowsReturnProfileRowsBeforeExtraCurrentRows() {
        let rows = ManagedEnvironment.environmentDetailsRows(
            profileEnvironment: [
                "API_TIMEOUT_MS": "3000000",
                "ANTHROPIC_ORGANIZATION_ID": "old-org",
                "NON_SENSE_VAR": "haha"
            ],
            extraCurrentEnvironment: [
                "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
            ]
        )

        XCTAssertEqual(
            rows,
            [
                EnvironmentDetailsRow(
                    name: "API_TIMEOUT_MS",
                    value: "3000000",
                    kind: .trackedInProfile,
                    id: "API_TIMEOUT_MS-trackedInProfile"
                ),
                EnvironmentDetailsRow(
                    name: "ANTHROPIC_ORGANIZATION_ID",
                    value: "old-org",
                    kind: .trackedInProfile,
                    id: "ANTHROPIC_ORGANIZATION_ID-trackedInProfile"
                ),
                EnvironmentDetailsRow(
                    name: "NON_SENSE_VAR",
                    value: "haha",
                    kind: .notTrackedBySwitcher,
                    id: "NON_SENSE_VAR-notTrackedBySwitcher"
                ),
                EnvironmentDetailsRow(
                    name: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
                    value: "1",
                    kind: .notTrackedHere,
                    id: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-notTrackedHere"
                )
            ]
        )
    }

    func testEnvironmentDetailsRowStrikeThroughFollowsKind() {
        var row = EnvironmentDetailsRow(
            name: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
            value: "1",
            kind: .trackedInProfile,
            id: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-trackedInProfile"
        )

        XCTAssertFalse(row.isStruckThrough)

        row.kind = .notTrackedHere

        XCTAssertTrue(row.isStruckThrough)
    }

    func testUnchangedEntriesExposeStableDetailedRows() {
        let preview = TargetPreview(
            target: .claude,
            fileURL: URL(fileURLWithPath: "/tmp/settings.json"),
            changes: [
                TargetChange(key: "ANTHROPIC_AUTH_TOKEN", oldValue: "old", newValue: "new", kind: .updated)
            ],
            currentEnvironment: [
                "API_TIMEOUT_MS": "3000000",
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
                "ANTHROPIC_AUTH_TOKEN": "old",
                "ANTHROPIC_BASE_URL": "https://proxy.example"
            ],
            declaredEnvironment: [
                "API_TIMEOUT_MS": "3000000",
                "ANTHROPIC_AUTH_TOKEN": "new"
            ],
            desiredEnvironment: [
                "API_TIMEOUT_MS": "3000000",
                "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1",
                "ANTHROPIC_AUTH_TOKEN": "new",
                "ANTHROPIC_BASE_URL": "https://proxy.example"
            ],
            comparedKeyCount: 4,
            willCreateFile: false,
            manualFollowUp: "Restart Claude Code.",
            backupURL: nil,
            errorMessage: nil
        )

        XCTAssertEqual(
            preview.unchangedEntries,
            [
                EnvironmentEntry(name: "API_TIMEOUT_MS", value: "3000000")
            ]
        )
        XCTAssertEqual(
            preview.untouchedEntries,
            [
                EnvironmentEntry(name: "ANTHROPIC_BASE_URL", value: "https://proxy.example"),
                EnvironmentEntry(name: "CLAUDE_CODE_DISABLE_TERMINAL_TITLE", value: "1")
            ]
        )
    }

    private func makePreview(target: TargetKind, path: String) -> TargetPreview {
        TargetPreview(
            target: target,
            fileURL: URL(fileURLWithPath: path),
            changes: [],
            comparedKeyCount: 0,
            willCreateFile: false,
            manualFollowUp: "Follow up",
            backupURL: nil,
            errorMessage: nil
        )
    }
}
