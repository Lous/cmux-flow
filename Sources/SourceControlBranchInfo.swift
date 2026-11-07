import Foundation

/// Branch facts from the `# branch.*` headers of `git status --porcelain=v2 --branch`.
struct SourceControlBranchInfo: Hashable, Sendable {
    /// Checked-out branch name; nil when HEAD is detached.
    var head: String?
    /// HEAD commit; nil for an unborn branch with no commits yet.
    var oid: String?
    var upstream: String?
    var ahead: Int = 0
    var behind: Int = 0

    var isDetached: Bool {
        head == nil
    }

    /// Branch name, or the short commit for a detached HEAD.
    var displayName: String {
        if let head {
            return head
        }
        if let oid {
            return String(oid.prefix(8))
        }
        return "HEAD"
    }
}
