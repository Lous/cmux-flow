import Foundation

/// A `fileExplorer.exclude` pattern that is turned on, with its optional sibling condition.
struct FileExplorerExcludeRule: Sendable, Equatable {
    let pattern: FileExplorerGlobPattern
    /// VS Code's `when` clause, such as `$(basename).ts`; nil hides every match.
    let siblingClause: String?

    /// Whether this rule hides the entry named `name`.
    ///
    /// - Parameters:
    ///   - relativePath: The entry's path relative to the explorer root.
    ///   - absolutePath: The entry's full path, for patterns starting with `/`.
    ///   - name: The entry's own name.
    ///   - siblingNames: The names in the entry's folder, for the `when` clause.
    func excludes(relativePath: String, absolutePath: String, name: String, siblingNames: Set<String>) -> Bool {
        guard pattern.matches(pattern.isAbsolute ? absolutePath : relativePath) else { return false }
        guard let siblingClause else { return true }
        return siblingNames.contains(siblingClause.replacingOccurrences(of: "$(basename)", with: basename(of: name)))
    }

    /// The name without its last extension; a leading dot is not an extension.
    private func basename(of name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
