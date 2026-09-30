import XCTest
@testable import CCEnvSwitcherApp
@testable import CCEnvSwitcherCore

final class ApplyConfirmationPreviewTests: XCTestCase {
    func testBuildConfirmationKeyPreviewsGroupsTargetsUnderTheSameKeyUsingManagedKeyOrder() {
        let previews = [
            makePreview(target: .terminal, changes: [
                makeChange(key: "ANTHROPIC_BASE_URL", oldValue: "old-url", newValue: "new-url", kind: .updated),
                makeChange(key: "API_TIMEOUT_MS", oldValue: "300000", newValue: "3000000", kind: .updated)
            ]),
            makePreview(target: .vscode, changes: [
                makeChange(key: "ANTHROPIC_BASE_URL", oldValue: "old-url", newValue: "new-url", kind: .updated)
            ]),
            makePreview(target: .claude, changes: [
                makeChange(key: "ANTHROPIC_ORGANIZATION_ID", oldValue: "old-org", newValue: nil, kind: .removed)
            ])
        ]

        let keyPreviews = buildConfirmationKeyPreviews(from: previews)

        XCTAssertEqual(
            keyPreviews.map(\.key),
            ["API_TIMEOUT_MS", "ANTHROPIC_BASE_URL", "ANTHROPIC_ORGANIZATION_ID"]
        )
        XCTAssertEqual(
            keyPreviews.first?.targetStates.map(\.target),
            [.terminal, .vscode, .claude]
        )
    }

    func testBuildConfirmationKeyPreviewsShowsDistinctPerTargetValuesForTheSameKey() throws {
        let previews = [
            makePreview(target: .terminal, changes: [
                makeChange(key: "ANTHROPIC_BASE_URL", oldValue: "old-a", newValue: "new-value", kind: .updated)
            ]),
            makePreview(target: .vscode, changes: [
                makeChange(key: "ANTHROPIC_BASE_URL", oldValue: "old-b", newValue: "new-value", kind: .updated)
            ]),
            makePreview(target: .claude, changes: [
                makeChange(key: "ANTHROPIC_BASE_URL", oldValue: nil, newValue: "new-value", kind: .added)
            ])
        ]

        let keyPreview = try XCTUnwrap(buildConfirmationKeyPreviews(from: previews).first)

        XCTAssertEqual(keyPreview.targetStates[0].displayState, .updated)
        XCTAssertEqual(keyPreview.targetStates[0].oldValue, "old-a")
        XCTAssertEqual(keyPreview.targetStates[1].displayState, .updated)
        XCTAssertEqual(keyPreview.targetStates[1].oldValue, "old-b")
        XCTAssertEqual(keyPreview.targetStates[2].displayState, .added)
        XCTAssertNil(keyPreview.targetStates[2].oldValue)
    }

    func testBuildConfirmationKeyPreviewsMarksTargetsWithoutTheKeyAsNotSetWhenOthersWillChange() throws {
        let previews = [
            makePreview(target: .terminal, changes: [
                makeChange(key: "ANTHROPIC_ORGANIZATION_ID", oldValue: "old-org", newValue: "example-org", kind: .updated)
            ], desiredEnvironment: ["ANTHROPIC_ORGANIZATION_ID": "example-org"]),
            makePreview(target: .vscode, changes: [], desiredEnvironment: ["ANTHROPIC_ORGANIZATION_ID": "example-org"]),
            makePreview(target: .claude, changes: [
                makeChange(key: "ANTHROPIC_ORGANIZATION_ID", oldValue: "old-org", newValue: "example-org", kind: .updated)
            ], desiredEnvironment: ["ANTHROPIC_ORGANIZATION_ID": "example-org"])
        ]

        let keyPreview = try XCTUnwrap(buildConfirmationKeyPreviews(from: previews).first)

        XCTAssertEqual(keyPreview.targetStates[1].displayState, .added)
        XCTAssertNil(keyPreview.targetStates[1].oldValue)
        XCTAssertEqual(keyPreview.targetStates[1].newValue, "example-org")
        XCTAssertEqual(keyPreview.targetStates[2].displayState, .updated)
        XCTAssertEqual(keyPreview.targetStates[2].oldValue, "old-org")
        XCTAssertEqual(keyPreview.targetStates[2].newValue, "example-org")
    }

    func testBuildConfirmationKeyPreviewsReturnsEmptyForEmptyPreviews() {
        XCTAssertEqual(buildConfirmationKeyPreviews(from: []), [])
    }

    private func makePreview(
        target: TargetKind,
        changes: [TargetChange],
        desiredEnvironment: [String: String]? = nil
    ) -> TargetPreview {
        let currentEnvironment = Dictionary(uniqueKeysWithValues: changes.compactMap { change in
            change.oldValue.map { (change.key, $0) }
        })
        let resolvedDesiredEnvironment = desiredEnvironment ?? Dictionary(uniqueKeysWithValues: changes.compactMap { change in
            change.newValue.map { (change.key, $0) }
        })

        return TargetPreview(
            target: target,
            fileURL: URL(fileURLWithPath: "/tmp/\(target.rawValue).json"),
            changes: changes,
            currentEnvironment: currentEnvironment,
            desiredEnvironment: resolvedDesiredEnvironment,
            willCreateFile: false,
            manualFollowUp: "Follow up",
            backupURL: nil,
            errorMessage: nil
        )
    }

    private func makeChange(
        key: String,
        oldValue: String?,
        newValue: String?,
        kind: ChangeKind
    ) -> TargetChange {
        TargetChange(key: key, oldValue: oldValue, newValue: newValue, kind: kind)
    }
}
