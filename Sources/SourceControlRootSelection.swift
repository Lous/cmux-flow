import Foundation

/// The repositories the Git tab lists: the ones the workspace's terminals are
/// in right now, so the list follows every `cd`.
///
/// A repository the user removed from the list stays hidden while a terminal
/// is still in it, and comes back once a terminal enters it again.
///
/// ```swift
/// var selection = SourceControlRootSelection()
/// selection.update(discovered: ["/src/wow"])   // added ["/src/wow"]
/// selection.update(discovered: ["/src/cmux"])  // added ["/src/cmux"], removed ["/src/wow"]
/// ```
struct SourceControlRootSelection: Equatable, Sendable {
    /// What one update added to and removed from the list.
    struct Change: Equatable, Sendable {
        var added: Set<String> = []
        var removed: Set<String> = []

        var isEmpty: Bool { added.isEmpty && removed.isEmpty }
    }

    /// Listed repository roots, in discovery order.
    private(set) var roots: [String] = []
    /// Removed by the user while a terminal is still in them.
    private var dismissed: Set<String> = []

    /// Every open terminal's current directory, or the workspace directory
    /// while no terminal has reported one. The workspace directory is left out
    /// otherwise: it only follows the focused terminal, so after that terminal
    /// closes it would keep a repository no terminal is in.
    static func candidateDirectories(
        currentDirectory: String,
        panelDirectories: [UUID: String]
    ) -> [String] {
        var seen = Set<String>()
        var directories: [String] = []
        for directory in panelDirectories.values.sorted() {
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            directories.append(trimmed)
        }
        let workspaceDirectory = currentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        if directories.isEmpty, !workspaceDirectory.isEmpty {
            directories.append(workspaceDirectory)
        }
        return directories
    }

    /// Replaces the list with the repositories the terminals are in now.
    ///
    /// - Parameter discovered: Repository roots found from the workspace's
    ///   current directories.
    /// - Returns: The roots that entered and left the list.
    @discardableResult
    mutating func update(discovered: [String]) -> Change {
        dismissed.formIntersection(discovered)
        var seen = Set<String>()
        let listed = discovered.filter { !dismissed.contains($0) && seen.insert($0).inserted }
        let change = Change(
            added: Set(listed).subtracting(roots),
            removed: Set(roots).subtracting(listed)
        )
        roots = listed
        return change
    }

    /// Hides `root` until no terminal is in it anymore.
    mutating func dismiss(_ root: String) {
        dismissed.insert(root)
        roots.removeAll { $0 == root }
    }

    /// Drops roots that stopped being repositories.
    mutating func remove(_ gone: some Sequence<String>) {
        let gone = Set(gone)
        roots.removeAll { gone.contains($0) }
    }
}
