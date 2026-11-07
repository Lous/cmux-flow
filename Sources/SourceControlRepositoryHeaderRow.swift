import CmuxFoundation
import SwiftUI

/// A repository's title row: name, branch, ahead/behind and change count.
///
/// Clicking toggles the file list. Hovering shows a button that opens every
/// working-tree change in the diff viewer; the context menu has the rest.
struct SourceControlRepositoryHeaderRow: View {
    let repository: SourceControlRepositorySnapshot
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onOpenDiff: (SourceControlDiffRequest.RepositorySource) -> Void
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            CmuxSystemSymbolImage(magnified: "chevron.down", pointSize: 9, weight: .semibold, tint: .secondary.opacity(0.7))
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                .frame(width: 10)
            Text(repository.name)
                .cmuxFont(size: 12, weight: .semibold)
                .foregroundColor(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(2)
            branchLabel
                .layoutPriority(1)
            syncLabel
            Spacer(minLength: 4)
            if isHovered, repository.changedPathCount > 0 {
                Button {
                    onOpenDiff(.workingTree)
                } label: {
                    CmuxSystemSymbolImage(magnified: "plus.forwardslash.minus", pointSize: 10, weight: .medium, tint: .secondary)
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "sourceControl.repository.openChanges", defaultValue: "Open Changes"))
            }
            statusBadge
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onToggle)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(String(localized: "sourceControl.repository.openChanges", defaultValue: "Open Changes"), action: { onOpenDiff(.workingTree) })
            Button(String(localized: "sourceControl.repository.openStagedChanges", defaultValue: "Open Staged Changes"), action: { onOpenDiff(.staged) })
            Button(String(localized: "sourceControl.repository.compareWithBase", defaultValue: "Compare Branch with Base"), action: { onOpenDiff(.branchBase) })
            Divider()
            Button(String(localized: "sourceControl.repository.revealInFinder", defaultValue: "Reveal in Finder"), action: onRevealInFinder)
            Button(String(localized: "sourceControl.repository.copyPath", defaultValue: "Copy Path"), action: onCopyPath)
            Divider()
            Button(String(localized: "sourceControl.repository.remove", defaultValue: "Remove from List"), action: onRemove)
        }
    }

    private var branchLabel: some View {
        HStack(spacing: 3) {
            CmuxSystemSymbolImage(
                magnified: repository.branch.isDetached ? "smallcircle.filled.circle" : "arrow.triangle.branch",
                pointSize: 9,
                weight: .medium,
                tint: .secondary
            )
            Text(repository.branch.displayName)
                .cmuxFont(size: 11)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var syncLabel: some View {
        let branch = repository.branch
        if branch.ahead > 0 || branch.behind > 0 {
            HStack(spacing: 2) {
                if branch.ahead > 0 {
                    Text("\u{2191}\(branch.ahead)")
                }
                if branch.behind > 0 {
                    Text("\u{2193}\(branch.behind)")
                }
            }
            .cmuxFont(size: 10, weight: .medium, monospacedDigit: true)
            .foregroundStyle(.tertiary)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if repository.errorMessage != nil {
            CmuxSystemSymbolImage(magnified: "exclamationmark.triangle.fill", pointSize: 10, tint: Color(nsColor: .systemYellow))
        } else if repository.changedPathCount == 0 {
            CmuxSystemSymbolImage(magnified: "checkmark", pointSize: 9, weight: .semibold, tint: .secondary.opacity(0.6))
        } else {
            Text(repository.changedPathCount.description)
                .cmuxFont(size: 10, weight: .semibold, monospacedDigit: true)
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .fixedSize()
        }
    }

    private var helpText: String {
        var lines = [repository.root]
        if let upstream = repository.branch.upstream {
            lines.append(String(
                localized: "sourceControl.repository.tracking",
                defaultValue: "Tracking \(upstream)"
            ))
        }
        return lines.joined(separator: "\n")
    }
}
