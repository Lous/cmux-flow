import Foundation

/// The section of a repository's status an entry is listed under.
enum SourceControlChangeGroup: String, CaseIterable, Hashable, Sendable {
    /// Unmerged paths left by a merge, rebase or cherry-pick.
    case conflicts
    /// Changes recorded in the index.
    case staged
    /// Changes to tracked files that are not in the index yet.
    case unstaged
    /// Files Git does not track and does not ignore.
    case untracked
}
