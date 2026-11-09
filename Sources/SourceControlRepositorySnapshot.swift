import Foundation

/// Everything the Source Control panel shows for one repository.
struct SourceControlRepositorySnapshot: Hashable, Sendable, Identifiable {
    /// Absolute repository root, as reported by `git rev-parse --show-toplevel`.
    let root: String
    var branch: SourceControlBranchInfo
    var changes: [SourceControlFileChange]
    /// True when the change list was cut at ``SourceControlStatusParser/maximumEntries``.
    var isTruncated: Bool = false
    /// Set when Git could not report status for this repository.
    var errorMessage: String?
    /// False once `root` stopped being a repository's top level: its `.git` was
    /// deleted, or the folder was folded into an enclosing repository. The panel
    /// then forgets it, the way VS Code closes a repository whose `.git` goes away.
    var isRepositoryRoot: Bool = true

    var id: String { root }

    var name: String {
        (root as NSString).lastPathComponent
    }

    /// Number of distinct paths with changes (a path staged and modified counts once).
    var changedPathCount: Int {
        Set(changes.map(\.path)).count
    }

    func changes(in group: SourceControlChangeGroup) -> [SourceControlFileChange] {
        changes.filter { $0.group == group }
    }
}
