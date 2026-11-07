import SwiftUI

extension SourceControlFileChange {
    /// Status color following VS Code's git decorations: modified orange,
    /// added and untracked green, deleted red, renamed blue, conflicts purple.
    var badgeColor: Color {
        switch group {
        case .conflicts:
            return Color(nsColor: .systemPurple)
        case .untracked:
            return Color(nsColor: .systemGreen)
        case .staged, .unstaged:
            switch gitStatus {
            case "A", "C": return Color(nsColor: .systemGreen)
            case "D": return Color(nsColor: .systemRed)
            case "R": return Color(nsColor: .systemBlue)
            default: return Color(nsColor: .systemOrange)
            }
        }
    }

    /// Spoken and tooltip description of the badge letter.
    var statusDescription: String {
        switch group {
        case .conflicts:
            return String(localized: "sourceControl.status.conflict", defaultValue: "Conflict")
        case .untracked:
            return String(localized: "sourceControl.status.untracked", defaultValue: "Untracked")
        case .staged, .unstaged:
            switch gitStatus {
            case "A": return String(localized: "sourceControl.status.added", defaultValue: "Added")
            case "C": return String(localized: "sourceControl.status.copied", defaultValue: "Copied")
            case "D": return String(localized: "sourceControl.status.deleted", defaultValue: "Deleted")
            case "R": return String(localized: "sourceControl.status.renamed", defaultValue: "Renamed")
            case "T": return String(localized: "sourceControl.status.typeChanged", defaultValue: "Type changed")
            default: return String(localized: "sourceControl.status.modified", defaultValue: "Modified")
            }
        }
    }
}
