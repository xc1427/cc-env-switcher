import Foundation
import XCTest

final class ContentViewCopyTests: XCTestCase {
    func testHeaderUsesShortenedRevealButtonLabels() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot.appendingPathComponent("Sources/CCEnvSwitcherApp/ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        XCTAssertTrue(source.contains("Button(\"Refresh Profiles\")"))
        XCTAssertTrue(source.contains("Button(\"Reveal Profile in Finder...\")"))
        XCTAssertTrue(source.contains("Button(\"Edit Profile\")"))
        XCTAssertLessThan(
            try XCTUnwrap(source.range(of: "Button(\"Edit Profile\")")?.lowerBound),
            try XCTUnwrap(source.range(of: "Button(\"Reveal Profile in Finder...\")")?.lowerBound)
        )
        XCTAssertFalse(source.contains("Button(\"Reveal Backups...\")"))
        XCTAssertFalse(source.contains("Button(\"Reveal Profiles File\")"))
        XCTAssertFalse(source.contains("Button(\"Reveal Backups\")"))
    }

    func testHeaderMovesDebugModeIntoSecondarySection() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("actionButtonsRow"))
        XCTAssertTrue(source.contains("debugModeSection"))
        XCTAssertTrue(source.contains("Toggle(\"Debug Mode\", isOn: debugModeBinding)"))
        XCTAssertTrue(source.contains("viewModel.targetModeDescription"))
        XCTAssertTrue(source.contains("viewModel.debugTargetFileNamesDescription"))
        XCTAssertTrue(source.contains("Button(\"Generate Baseline Targets\")"))
    }

    func testMainScreenUsesResponsiveOverviewSectionToReduceVerticalScroll() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("overviewSection"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("compactCurrentStatusCard"))
    }

    func testSampleProfileReplacementWarningIsRemoved() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot.appendingPathComponent("Sources/CCEnvSwitcherApp/ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        XCTAssertFalse(source.contains("profile.id == \"vercel-ai-gateway\""))
        XCTAssertFalse(source.contains("Sample profile only. Replace the placeholder values before applying it anywhere."))
    }

    func testMainScreenUsesCurrentAndSelectedLabels() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("Text(\"Current\")"))
        XCTAssertTrue(source.contains("Text(\"Selected\")"))
        XCTAssertTrue(source.contains("No matching profile"))
    }

    func testCurrentHelpTooltipTextExists() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("questionmark.circle"))
        XCTAssertTrue(source.contains("Current profile: this is the most specific profile whose tracked keys all match the current values"))
        XCTAssertTrue(source.contains("Suboptimal match: this profile also matches"))
        XCTAssertTrue(source.contains("Unmatched: the current tracked values do not resolve to a single matching profile"))
    }

    func testSidebarShowsCurrentBadgeMarker() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("Text(\"Current\")"))
        XCTAssertTrue(source.contains("viewModel.currentMatchedProfileID == profile.id"))
    }

    func testMainScreenDefinesQuietUtilityTypographyTokens() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("private let sectionLabelFont = Font.callout.weight(.semibold)"))
        XCTAssertTrue(source.contains("private let primaryValueFont = Font.headline.weight(.semibold)"))
        XCTAssertTrue(source.contains("private let supportingCopyFont = Font.callout"))
        XCTAssertFalse(source.contains("Text(profile.id)\n                            .font(.title2)"))
        XCTAssertFalse(source.contains("Text(profile.id)\n                        .font(.title)"))
    }

    func testSelectedProfileUsesTrackedTerminologyAndNoRedundantKeyCountMetric() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("tracked keys"))
        XCTAssertFalse(source.contains("SummaryMetric(title: \"Managed keys\""))
        XCTAssertFalse(source.contains("managed keys"))
    }

    func testSelectedEnvironmentDetailsExplainStruckThroughKeysAndBadges() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("viewModel.selectedProfileEnvironmentDetailsRows"))
        XCTAssertTrue(source.contains("Struck-through keys are not actively tracked by this selected profile."))
        XCTAssertTrue(source.contains("row.kind.badgeText"))
        XCTAssertTrue(source.contains(".strikethrough(row.isStruckThrough)"))
    }

    func testTargetDetailsRenderUnchangedEntriesInline() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("preview.unchangedEntries"))
        XCTAssertTrue(source.contains("preview.untouchedEntries"))
        XCTAssertTrue(source.contains("Text(\"Unchanged\")"))
        XCTAssertTrue(source.contains("Text(\"Untouched\")"))
        XCTAssertTrue(source.contains("private struct UnchangedEntryRow: View"))
    }

    func testConfirmationSheetUsesSingleChangePreviewSection() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("Change preview"))
        XCTAssertFalse(source.contains("Target overview"))
        XCTAssertFalse(source.contains("Selected target"))
        XCTAssertTrue(source.contains("buildConfirmationKeyPreviews(from: viewModel.pendingApplyPreviews)"))
    }

    func testConfirmationSheetDefinesKeyCentricDiffPanel() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains("private struct ConfirmationDiffPanel: View"))
        XCTAssertTrue(source.contains("ForEach(keyPreviews) { keyPreview in"))
        XCTAssertTrue(source.contains("private struct ConfirmationKeySection: View"))
        XCTAssertTrue(source.contains("private struct ConfirmationTargetStateRow: View"))
    }

    func testConfirmationSheetUsesBoundedWindowSize() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains(".frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 620)"))
        XCTAssertFalse(source.contains(".frame(minWidth: 760, minHeight: 620)"))
    }

    func testConfirmationDetailPanelReservesVisibleHeight() throws {
        let source = try contentViewSource()

        XCTAssertTrue(source.contains(".frame(minHeight: 220, idealHeight: 260, maxHeight: 300, alignment: .topLeading)"))
        XCTAssertFalse(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
    }

    func testAppUsesDefaultMainWindowSize() throws {
        let source = try appSource()

        XCTAssertTrue(source.contains(".defaultSize(width: 1220, height: 1160)"))
        XCTAssertTrue(source.contains(".frame(minWidth: 920, minHeight: 640)"))
    }

    private func contentViewSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let contentViewURL = repositoryRoot.appendingPathComponent("Sources/CCEnvSwitcherApp/ContentView.swift")
        return try String(contentsOf: contentViewURL, encoding: .utf8)
    }

    private func appSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appURL = repositoryRoot.appendingPathComponent("Sources/CCEnvSwitcherExecutable/CCEnvSwitcherApp.swift")
        return try String(contentsOf: appURL, encoding: .utf8)
    }
}
