import CmuxFoundation
import SwiftUI

/// One changed file: name, dimmed folder, line counts and the status letter.
struct SourceControlFileRow: View {
    let change: SourceControlFileChange
    let isSelected: Bool
    let onOpenDiff: () -> Void
    let onOpenDiffInNewTab: () -> Void
    let onOpenFile: (() -> Void)?
    let onRevealInFinder: () -> Void
    let onCopyPath: () -> Void
    let onCopyRelativePath: () -> Void

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
            lineCounts
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
            Divider()
            Button(String(localized: "sourceControl.file.revealInFinder", defaultValue: "Reveal in Finder"), action: onRevealInFinder)
            Button(String(localized: "sourceControl.file.copyPath", defaultValue: "Copy Path"), action: onCopyPath)
            Button(String(localized: "sourceControl.file.copyRelativePath", defaultValue: "Copy Relative Path"), action: onCopyRelativePath)
        }
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
