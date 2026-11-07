import CmuxFoundation
import SwiftUI

/// One changed file: name, dimmed folder, line counts and the status letter.
///
/// Hovering swaps the line counts for the row's actions (stage, unstage,
/// discard), as VS Code does; the context menu offers the same actions.
struct SourceControlFileRow: View {
    let change: SourceControlFileChange
    let isSelected: Bool
    let onOpenDiff: () -> Void
    let onOpenDiffInNewTab: () -> Void
    let onOpenFile: (() -> Void)?
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onCopyRelativePath: () -> Void
    let onStage: (() -> Void)?
    let onUnstage: (() -> Void)?
    let onDiscard: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(change.fileName)
                .cmuxFont(size: 12)
                .foregroundColor(.primary.opacity(change.isDeletion ? 0.55 : 0.92))
                .strikethrough(change.isDeletion)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            if !change.directory.isEmpty {
                Text(change.directory)
                    .cmuxFont(size: 11)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if isHovered && hasActions {
                actionButtons
            } else {
                lineCounts
            }
            Text(change.badge)
                .cmuxFont(size: 11, weight: .semibold, design: .monospaced)
                .foregroundColor(change.badgeColor)
                .frame(width: 12, alignment: .center)
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpenDiff)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(change.path), \(change.statusDescription)")
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            Button(String(localized: "sourceControl.file.openDiff", defaultValue: "Open Diff"), action: onOpenDiff)
            Button(String(localized: "sourceControl.file.openDiffInNewTab", defaultValue: "Open Diff in New Tab"), action: onOpenDiffInNewTab)
            if let onOpenFile {
                Button(String(localized: "sourceControl.file.openFile", defaultValue: "Open File"), action: onOpenFile)
            }
            if hasActions {
                Divider()
            }
            if let onStage {
                Button(stageLabel, action: onStage)
            }
            if let onUnstage {
                Button(String(localized: "sourceControl.file.unstage", defaultValue: "Unstage Changes"), action: onUnstage)
            }
            if let onDiscard {
                Button(String(localized: "sourceControl.file.discard", defaultValue: "Discard Changes…"), action: onDiscard)
            }
            Divider()
            Button(String(localized: "sourceControl.file.revealInFinder", defaultValue: "Reveal in Finder"), action: onRevealInFinder)
            Button(String(localized: "sourceControl.file.copyPath", defaultValue: "Copy Path"), action: onCopyPath)
            Button(String(localized: "sourceControl.file.copyRelativePath", defaultValue: "Copy Relative Path"), action: onCopyRelativePath)
        }
    }

    private var hasActions: Bool {
        onStage != nil || onUnstage != nil || onDiscard != nil
    }

    private var stageLabel: String {
        change.group == .conflicts
            ? String(localized: "sourceControl.file.markResolved", defaultValue: "Stage (Mark as Resolved)")
            : String(localized: "sourceControl.file.stage", defaultValue: "Stage Changes")
    }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            if let onDiscard {
                rowActionButton(
                    symbol: "arrow.uturn.backward",
                    help: String(localized: "sourceControl.file.discard", defaultValue: "Discard Changes…"),
                    action: onDiscard
                )
            }
            if let onStage {
                rowActionButton(symbol: "plus", help: stageLabel, action: onStage)
            }
            if let onUnstage {
                rowActionButton(
                    symbol: "minus",
                    help: String(localized: "sourceControl.file.unstage", defaultValue: "Unstage Changes"),
                    action: onUnstage
                )
            }
        }
    }

    private func rowActionButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CmuxSystemSymbolImage(magnified: symbol, pointSize: 10, weight: .semibold, tint: .secondary)
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private var lineCounts: some View {
        if let additions = change.additions, let deletions = change.deletions, additions + deletions > 0 {
            HStack(spacing: 3) {
                if additions > 0 {
                    Text("+\(additions)")
                        .foregroundColor(Color(nsColor: .systemGreen))
                }
                if deletions > 0 {
                    Text("\u{2212}\(deletions)")
                        .foregroundColor(Color(nsColor: .systemRed))
                }
            }
            .cmuxFont(size: 10, weight: .medium, monospacedDigit: true)
            .opacity(0.85)
            .fixedSize()
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.06 : 0))
            .padding(.horizontal, 6)
    }

    private var helpText: String {
        if let originalPath = change.originalPath {
            return "\(originalPath) \u{2192} \(change.path) \u{2014} \(change.statusDescription)"
        }
        return "\(change.path) \u{2014} \(change.statusDescription)"
    }
}
