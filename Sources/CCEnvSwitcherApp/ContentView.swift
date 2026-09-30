import CCEnvSwitcherCore
import SwiftUI

package struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isProfileEnvironmentExpanded = false
    @State private var isCurrentStatusHelpPresented = false
    @State private var isTokenVisible = true

    private let codeFont = Font.system(.body, design: .monospaced)
    private let metadataFont = Font.callout
    private let sectionLabelFont = Font.callout.weight(.semibold)
    private let primaryValueFont = Font.headline.weight(.semibold)
    private let supportingCopyFont = Font.callout
    private let currentStatusHelpText = """
Current profile: this is the most specific profile whose tracked keys all match the current values.
Suboptimal match: this profile also matches, but another matching profile defines more tracked keys.
Unmatched: the current tracked values do not resolve to a single matching profile.
"""
    private let columns = [
        GridItem(.flexible(minimum: 260), spacing: 12, alignment: .topLeading),
        GridItem(.flexible(minimum: 260), spacing: 12, alignment: .topLeading)
    ]
    private var debugModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isDebugModeEnabled },
            set: { viewModel.setDebugModeEnabled($0) }
        )
    }

    package init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var activeCurrentStateHelpKind: CurrentStateHelpKind {
        switch viewModel.currentProfileStatus {
        case .matched:
            return .currentProfile
        case .unmatched:
            return .unmatched
        }
    }

    private var currentStateDefinitions: [CurrentStateDefinition] {
        [
            CurrentStateDefinition(
                kind: .currentProfile,
                title: "Current profile",
                description: "This is the most specific profile whose tracked keys all match the current values.",
                symbolName: "checkmark.circle",
                tint: .green
            ),
            CurrentStateDefinition(
                kind: .suboptimalMatch,
                title: "Suboptimal match",
                description: "This profile also matches, but another matching profile defines more tracked keys.",
                symbolName: "arrow.down.circle",
                tint: .orange
            ),
            CurrentStateDefinition(
                kind: .unmatched,
                title: "Unmatched",
                description: "The current tracked values do not resolve to a single matching profile.",
                symbolName: "questionmark.circle",
                tint: .red
            )
        ]
    }

    package var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    overviewSection
                    changeSummarySection
                }
                .padding(18)
            }
            .navigationTitle("cc-env-switcher")
            .sheet(isPresented: $viewModel.isShowingApplyConfirmation) {
                ApplyConfirmationSheet(viewModel: viewModel, codeFont: codeFont, metadataFont: metadataFont)
            }
        }
        .onAppear {
            viewModel.load()
        }
        .onChange(of: viewModel.selectedProfileID) { _ in
            isProfileEnvironmentExpanded = false
            viewModel.refreshPreview()
        }
    }

    private var sidebar: some View {
        List(selection: $viewModel.selectedProfileID) {
            ForEach(viewModel.profiles) { profile in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.id)
                            .font(primaryValueFont)

                        if let description = profile.description, !description.isEmpty {
                            Text(description)
                                .font(supportingCopyFont)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    if viewModel.currentMatchedProfileID == profile.id {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.14), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                .tag(profile.id)
                .padding(.vertical, 4)
            }
        }
        .font(.body)
        .navigationTitle("Profiles")
        .navigationSplitViewColumnWidth(
            min: AppLayout.sidebarMinWidth,
            ideal: AppLayout.sidebarIdealWidth,
            max: AppLayout.sidebarMaxWidth
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            actionButtonsRow
            debugModeSection

            if let statusMessage = viewModel.statusMessage {
                MessageBanner(text: statusMessage, tint: .green)
            }

            if let warningMessage = viewModel.warningMessage {
                MessageBanner(text: warningMessage, tint: .orange)
            }

            if let errorMessage = viewModel.errorMessage {
                MessageBanner(text: errorMessage, tint: .red)
            }
        }
    }

    private var actionButtonsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Button("Refresh Profiles") {
                viewModel.reloadProfiles()
            }

            Button("Edit Profile") {
                viewModel.editProfilesDirectory()
            }

            Button("Reveal Profile in Finder...") {
                viewModel.revealProfilesFile()
            }

            Spacer(minLength: 12)

            Button("Apply...") {
                viewModel.prepareApplySelectedProfile()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedProfile == nil)
        }
        .controlSize(.regular)
    }

    private var debugModeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Debug Mode", isOn: debugModeBinding)
                .toggleStyle(.switch)

            Text(viewModel.targetModeDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if viewModel.isDebugModeEnabled {
                Text(viewModel.debugTargetFileNamesDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Button("Generate Baseline Targets") {
                    viewModel.generateDebugBaselineTargets()
                }
                .controlSize(.small)
            }
        }
        .controlSize(.small)
    }

    private var overviewSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                compactCurrentStatusCard
                    .frame(width: 280, alignment: .topLeading)

                targetProfileCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                currentStatusCard
                targetProfileCard
            }
        }
    }

    private var currentStatusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                currentStatusHeader
                currentStatusDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }

    private var compactCurrentStatusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                currentStatusHeader
                currentStatusDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
        }
    }

    private var targetProfileCard: some View {
        GroupBox {
            if let profile = viewModel.selectedProfile {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Selected")
                        .font(sectionLabelFont)
                        .foregroundStyle(.secondary)

                    Text(profile.id)
                        .font(primaryValueFont)

                    if let description = profile.description, !description.isEmpty {
                        Text(description)
                            .font(supportingCopyFont)
                            .foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        SummaryMetric(title: "Base URL", value: profile.managedEnvironment["ANTHROPIC_BASE_URL"] ?? "Not set")
                        SummaryMetric(
                            title: "ANTHROPIC_AUTH_TOKEN",
                            value: SensitiveValueDisplay.displayValue(
                                for: profile.managedEnvironment["ANTHROPIC_AUTH_TOKEN"],
                                isRevealed: isTokenVisible
                            ),
                            trailingSystemImage: isTokenVisible ? "eye.slash" : "eye"
                        ) {
                            isTokenVisible.toggle()
                        }
                    }

                    ExpandableSection(
                        title: "Environment details",
                        subtitle: "\(profile.managedEnvironment.count) tracked keys in this profile",
                        isExpanded: $isProfileEnvironmentExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.selectedProfileEnvironmentDetailsRows.contains(where: { $0.isStruckThrough }) {
                                Text("Struck-through keys are not actively tracked by this selected profile.")
                                    .font(supportingCopyFont)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(viewModel.selectedProfileEnvironmentDetailsRows, id: \.id) { row in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(row.name)
                                        .font(codeFont)
                                        .foregroundStyle(.secondary)
                                        .strikethrough(row.isStruckThrough)
                                        .frame(width: 250, alignment: .leading)

                                    Text(row.value.isEmpty ? "\"\"" : row.value)
                                        .font(codeFont)
                                        .foregroundStyle(row.isStruckThrough ? .secondary : .primary)
                                        .textSelection(.enabled)

                                    Spacer(minLength: 0)

                                    if let badgeText = row.kind.badgeText {
                                        Text(badgeText)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.primary.opacity(0.06), in: Capsule())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected")
                        .font(sectionLabelFont)
                        .foregroundStyle(.secondary)

                    Text("Select a profile to continue.")
                        .font(supportingCopyFont)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
    }

    private var changeSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            let pathSummaries = buildDistinctPathSummaries(for: viewModel.previews)

            Text("Change summary")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Review what will happen in each target. A full key-level diff appears in the confirmation step.")
                .font(.body)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(viewModel.previews) { preview in
                    TargetSummaryCard(
                        preview: preview,
                        pathSummary: pathSummaries[preview.id] ?? ".../" + preview.fileURL.lastPathComponent,
                        codeFont: codeFont,
                        metadataFont: metadataFont
                    )
                }
            }
        }
    }

    private var currentStatusHeader: some View {
        HStack(spacing: 8) {
            Text("Current")
                .font(sectionLabelFont)
                .foregroundStyle(.secondary)

            Button {
                isCurrentStatusHelpPresented.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(currentStatusHelpText)
            .popover(isPresented: $isCurrentStatusHelpPresented, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current state definitions")
                        .font(.headline)

                    Text("These labels describe what the app is detecting right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(currentStateDefinitions) { definition in
                            CurrentStateDefinitionRow(
                                definition: definition,
                                isHighlighted: definition.kind == activeCurrentStateHelpKind
                            )
                        }
                    }
                }
                .padding(14)
                .frame(width: 520, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var currentStatusDetails: some View {
        switch viewModel.currentProfileStatus {
        case let .matched(profile):
            Text(profile.id)
                .font(primaryValueFont)

            Text("This is the most specific profile whose tracked keys all match the current values.")
                .font(supportingCopyFont)
                .foregroundStyle(.secondary)

        case .unmatched:
            Text("No matching profile")
                .font(primaryValueFont)

            Text("The current tracked values do not resolve to a single matching profile.")
                .font(supportingCopyFont)
                .foregroundStyle(.secondary)
        }
    }
}

private enum CurrentStateHelpKind: Hashable {
    case currentProfile
    case suboptimalMatch
    case unmatched
}

private struct CurrentStateDefinition: Identifiable {
    let kind: CurrentStateHelpKind
    let title: String
    let description: String
    let symbolName: String
    let tint: Color

    var id: CurrentStateHelpKind { kind }
}

private struct CurrentStateDefinitionRow: View {
    let definition: CurrentStateDefinition
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: definition.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(definition.tint)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(definition.title)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(definition.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if isHighlighted {
                Text("Current")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(definition.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(definition.tint)
            }
        }
        .padding(10)
        .background(
            (isHighlighted ? definition.tint.opacity(0.10) : Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isHighlighted ? definition.tint.opacity(0.35) : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        )
    }
}

private struct MessageBanner: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(tint.opacity(0.35), lineWidth: 1)
            )
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    var trailingSystemImage: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if let trailingSystemImage, let trailingAction {
                    Button(action: trailingAction) {
                        Image(systemName: trailingSystemImage)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(value)
                .font(.callout.weight(.semibold))
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum SensitiveValueDisplay {
    static func displayValue(for secret: String?, isRevealed: Bool) -> String {
        guard let secret, !secret.isEmpty else {
            return "Not set"
        }

        guard !isRevealed else {
            return secret
        }

        let visiblePrefixCount = min(4, secret.count)
        let prefix = String(secret.prefix(visiblePrefixCount))
        let maskedCount = max(secret.count - visiblePrefixCount, 0)
        return prefix + String(repeating: "•", count: maskedCount)
    }
}

private struct TargetSummaryCard: View {
    let preview: TargetPreview
    let pathSummary: String
    let codeFont: Font
    let metadataFont: Font
    @State private var isDetailsExpanded = false

    var body: some View {
        GroupBox(preview.target.title) {
            VStack(alignment: .leading, spacing: 10) {
                if let errorMessage = preview.errorMessage {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.red)
                } else {
                    HStack(spacing: 8) {
                        CountChip(title: "Added", count: preview.addedCount, tint: .green)
                        CountChip(title: "Updated", count: preview.updatedCount, tint: .blue)
                        CountChip(title: "Removed", count: preview.removedCount, tint: .orange)
                        CountChip(title: "Unchanged", count: preview.unchangedCount, tint: .secondary)
                        CountChip(title: "Untouched", count: preview.untouchedCount, tint: .secondary)
                    }

                    if preview.willCreateFile {
                        Text("Will create target file")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if preview.totalChangeCount == 0 {
                        Text("No changes needed")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    ExpandableSection(
                        title: "Details",
                        subtitle: pathSummary,
                        isExpanded: $isDetailsExpanded
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(preview.fileURL.path)
                                .font(metadataFont)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)

                            if preview.totalChangeCount == 0 {
                                Text(
                                    preview.untouchedCount == 0
                                        ? "This target already matches the selected profile."
                                        : "This target needs no tracked changes, but it still contains tracked keys that the selected profile does not declare."
                                )
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(preview.changes) { change in
                                    ChangeRow(change: change, codeFont: codeFont)
                                }
                            }

                            if !preview.unchangedEntries.isEmpty {
                                Text("Unchanged")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                ForEach(preview.unchangedEntries, id: \.name) { entry in
                                    UnchangedEntryRow(entry: entry, codeFont: codeFont)
                                }
                            }

                            if !preview.untouchedEntries.isEmpty {
                                Text("Untouched")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)

                                Text("These tracked keys exist in the target, but are not declared by the selected profile.")
                                    .font(metadataFont)
                                    .foregroundStyle(.secondary)

                                ForEach(preview.untouchedEntries, id: \.name) { entry in
                                    UnchangedEntryRow(entry: entry, codeFont: codeFont)
                                }
                            }

                            Text(preview.manualFollowUp)
                                .font(metadataFont)
                                .foregroundStyle(.secondary)

                            if let backupURL = preview.backupURL {
                                Text("Backup: \(backupURL.path)")
                                    .font(metadataFont)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CountChip: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct ExpandableSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text(isExpanded ? "Hide" : "Show")
                            .font(.callout)
                            .fontWeight(.semibold)

                        Image(systemName: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.leading, 4)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct ChangeRow: View {
    let change: TargetChange
    let codeFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch change.kind {
            case .added:
                Text("Added")
                    .font(.callout)
                    .foregroundStyle(.green)

                Text("\(change.key) -> \(displayOptionalEnvironmentValue(change.newValue))")
                    .font(codeFont)
                    .textSelection(.enabled)

            case .updated:
                Text("Updated")
                    .font(.callout)
                    .foregroundStyle(.blue)

                Text(
                    "\(change.key): \(displayOptionalEnvironmentValue(change.oldValue)) -> \(displayOptionalEnvironmentValue(change.newValue))"
                )
                    .font(codeFont)
                    .textSelection(.enabled)

            case .removed:
                Text("Removed")
                    .font(.callout)
                    .foregroundStyle(.orange)

                Text(change.key)
                    .font(codeFont)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct UnchangedEntryRow: View {
    let entry: EnvironmentEntry
    let codeFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.name): \(displayEnvironmentValue(entry.value))")
                .font(codeFont)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private func displayEnvironmentValue(_ value: String) -> String {
    value.isEmpty ? "\"\"" : value
}

private func displayOptionalEnvironmentValue(_ value: String?) -> String {
    guard let value else {
        return ""
    }

    return displayEnvironmentValue(value)
}

private struct ApplyConfirmationSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let codeFont: Font
    let metadataFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Confirm switch")
                .font(.title)
                .fontWeight(.bold)

            if let profile = viewModel.pendingApplyProfile {
                compactConfirmationSummary(profile: profile)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Change preview")
                        .font(.headline)

                    ConfirmationDiffPanel(
                        keyPreviews: buildConfirmationKeyPreviews(from: viewModel.pendingApplyPreviews),
                        codeFont: codeFont
                    )
                }

                Divider()

                HStack {
                    Spacer()

                    Button("Cancel") {
                        viewModel.cancelApplyConfirmation()
                    }

                    Button("Apply changes") {
                        viewModel.confirmApplySelectedProfile()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("No pending profile to confirm.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 520, idealHeight: 620)
    }

    private var currentStateLabel: String {
        switch viewModel.currentProfileStatus {
        case let .matched(profile):
            return profile.id
        case .unmatched:
            return "No matching profile"
        }
    }

    private var currentStateDescription: String {
        switch viewModel.currentProfileStatus {
        case .matched:
            return "This is the most specific profile whose tracked keys all match the current values."
        case .unmatched:
            return "The current tracked values do not resolve to a single matching profile."
        }
    }

    @ViewBuilder
    private func compactConfirmationSummary(profile: ClaudeProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ConfirmationStateCard(
                    title: "Current state",
                    value: currentStateLabel,
                    subtitle: currentStateDescription
                )

                Image(systemName: "arrow.right")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                ConfirmationStateCard(
                    title: "Will switch to",
                    value: profile.id,
                    subtitle: profile.description ?? "Selected profile"
                )
            }

        }
    }
}

private struct ConfirmationStateCard: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ConfirmationDiffPanel: View {
    let keyPreviews: [ConfirmationKeyPreview]
    let codeFont: Font

    var body: some View {
        GroupBox {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if keyPreviews.isEmpty {
                        Text("No changes needed")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(keyPreviews) { keyPreview in
                            ConfirmationKeySection(keyPreview: keyPreview, codeFont: codeFont)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .frame(minHeight: 220, idealHeight: 260, maxHeight: 300, alignment: .topLeading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ConfirmationKeySection: View {
    let keyPreview: ConfirmationKeyPreview
    let codeFont: Font

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(keyPreview.key)
                .font(codeFont.weight(.semibold))
                .textSelection(.enabled)

            ForEach(keyPreview.targetStates) { targetState in
                ConfirmationTargetStateRow(targetState: targetState, codeFont: codeFont)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct ConfirmationTargetStateRow: View {
    let targetState: ConfirmationTargetState
    let codeFont: Font

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(targetState.target.title)
                .font(.callout.weight(.semibold))
                .frame(width: 92, alignment: .leading)

            Text(stateLabel)
                .font(.callout)
                .foregroundStyle(stateColor)
                .frame(width: 82, alignment: .leading)

            Text(stateDetail)
                .font(codeFont)
                .foregroundStyle(targetState.displayState == .unchanged ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stateLabel: String {
        switch targetState.displayState {
        case .unchanged:
            return "Unchanged"
        case .added:
            return "Added"
        case .updated:
            return "Updated"
        case .removed:
            return "Removed"
        }
    }

    private var stateColor: Color {
        switch targetState.displayState {
        case .unchanged:
            return .secondary
        case .added:
            return .green
        case .updated:
            return .blue
        case .removed:
            return .orange
        }
    }

    private var stateDetail: String {
        let oldText = targetState.oldValue ?? "Not set"
        let newText = targetState.newValue ?? "Not set"

        switch targetState.displayState {
        case .unchanged:
            return targetState.newValue ?? targetState.oldValue ?? "Not set"
        case .added, .updated, .removed:
            return "\(oldText) -> \(newText)"
        }
    }
}
