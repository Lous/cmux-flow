import Foundation

/// What the Source Control panel asks the diff viewer to show.
enum SourceControlDiffRequest: Hashable, Sendable {
    /// Which `cmux diff` git source a repository-wide request uses.
    enum RepositorySource: Hashable, Sendable {
        /// Unstaged and untracked changes (`--unstaged`).
        case workingTree
        /// The index against HEAD (`--staged`).
        case staged
        /// HEAD against its merge base with the default branch (`--branch`).
        case branchBase

        var cliFlag: String {
            switch self {
            case .workingTree: return "--unstaged"
            case .staged: return "--staged"
            case .branchBase: return "--branch"
            }
        }
    }

    /// One file's change, shown as a single-file patch. A preview reuses the
    /// workspace's preview tab; otherwise the diff gets a tab of its own.
    case file(SourceControlFileChange, repositoryRoot: String, opensAsPreview: Bool)
    /// Every change in a repository, with the viewer's own file tree and pickers.
    case repository(root: String, source: RepositorySource)
}
