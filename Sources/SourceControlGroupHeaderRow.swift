import CmuxFoundation
import SwiftUI

/// Collapsible section title inside a repository ("Staged Changes 3").
struct SourceControlGroupHeaderRow: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
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
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.top, 4)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
