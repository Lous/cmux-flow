import Foundation

/// One changed path in a repository, parsed from `git status --porcelain=v2`.
///
/// A path that is both staged and modified in the working tree produces two
/// entries, one per group, matching how Git (and VS Code) present it.
struct SourceControlFileChange: Hashable, Sendable, Identifiable {
    let group: SourceControlChangeGroup
    /// Repository-relative path; the destination path for a rename or copy.
    let path: String
    /// Repository-relative source path of a staged rename or copy.
    let originalPath: String?
    /// Git's status letter for this side of the change (M, T, A, D, R, C), or
    /// `U` for an unmerged path and `?` for an untracked one.
    let gitStatus: Character
    var additions: Int?
    var deletions: Int?

    var id: String { "\(group.rawValue):\(path)" }

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    /// Parent directory, relative to the repository root ("" at the root).
    var directory: String {
        (path as NSString).deletingLastPathComponent
    }

    var isDeletion: Bool {
        gitStatus == "D"
    }

    /// The letter shown next to the file, following VS Code's convention:
    /// untracked files show `U` and conflicts show `!`.
    var badge: String {
        switch group {
        case .conflicts: return "!"
        case .untracked: return "U"
        case .staged, .unstaged: return String(gitStatus)
        }
    }
}
