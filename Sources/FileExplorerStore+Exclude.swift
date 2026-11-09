import Foundation

extension FileExplorerStore {
    /// Drops what `fileExplorer.exclude` hides from one folder's listing, the way
    /// VS Code's explorer applies `files.exclude`.
    ///
    /// - Parameters:
    ///   - entries: One folder's listing; siblings for `when` clauses come from it.
    ///   - filter: The exclude rules in force.
    /// - Returns: The entries to show, in their original order.
    func visibleEntries(_ entries: [FileExplorerEntry], filter: FileExplorerExcludeFilter) -> [FileExplorerEntry] {
        guard !filter.rules.isEmpty else { return entries }
        let siblingNames: Set<String> = filter.hasSiblingRules ? Set(entries.map(\.name)) : []
        let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return entries.filter { entry in
            let relativePath = entry.path.hasPrefix(root) ? String(entry.path.dropFirst(root.count)) : entry.name
            return !filter.excludes(
                relativePath: relativePath,
                absolutePath: entry.path,
                name: entry.name,
                siblingNames: siblingNames
            )
        }
    }
}
