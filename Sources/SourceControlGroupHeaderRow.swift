import CmuxFoundation
import SwiftUI

/// Collapsible section title inside a repository ("Staged Changes 3"),
/// with the section's bulk actions on hover and in its context menu.
struct SourceControlGroupHeaderRow: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void
    var onStageAll: (() -> Void)?
    var onUnstageAll: (() -> Void)?
    var onDiscardAll: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 4) {
            CmuxSystemSymbolImage(magnified: "chevron.down", pointSize: 8, weight: .semibold, tint: .secondary.opacity(0.6))
                .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                .frame(width: 10)
            Text(title)
                .cmuxFont(size: 11, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(count.description)
                .cmuxFont(size: 10, weight: .medium, monospacedDigit: true)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if isHovered {
                if let onDiscardAll {
                    headerButton("arrow.uturn.backward", help: discardAllLabel, action: onDiscardAll)
                }
                if let onStageAll {
                    headerButton("plus", help: stageAllLabel, action: onStageAll)
                }
                if let onUnstageAll {
                    headerButton("minus", help: unstageAllLabel, action: onUnstageAll)
                }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onToggle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            if let onStageAll {
                Button(stageAllLabel, action: onStageAll)
            }
            if let onUnstageAll {
                Button(unstageAllLabel, action: onUnstageAll)
            }
            if let onDiscardAll {
                Button(discardAllLabel, action: onDiscardAll)
            }
        }
    }

    private var stageAllLabel: String {
        String(localized: "sourceControl.section.stageAll", defaultValue: "Stage All Changes")
    }

    private var unstageAllLabel: String {
        String(localized: "sourceControl.section.unstageAll", defaultValue: "Unstage All Changes")
    }

    private var discardAllLabel: String {
        String(localized: "sourceControl.section.discardAll", defaultValue: "Discard All Changes…")
    }

    private func headerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CmuxSystemSymbolImage(magnified: symbol, pointSize: 10, weight: .semibold, tint: .secondary)
                .frame(width: 18, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
