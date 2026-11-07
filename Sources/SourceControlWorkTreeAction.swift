import Foundation

/// A change the Source Control panel makes to a repository's index or work tree.
enum SourceControlWorkTreeAction: Hashable, Sendable {
    /// Adds the paths to the index (`git add -A`); for a conflict this marks it resolved.
    case stage
    /// Removes the paths from the index, keeping the work tree as is.
    case unstage
    /// Reverts tracked paths to the index and moves untracked files to the Trash.
    case discard
}
