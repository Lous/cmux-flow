import Foundation

/// Decides which files and folders the Files tab hides, the way VS Code's
/// `files.exclude` does: VS Code's default patterns, overridden entry by entry
/// by the user's `fileExplorer.exclude`.
///
/// ```swift
/// let filter = FileExplorerExcludeFilter(userEntries: ["**/.git": .enabled(false), "build": .enabled(true)])
/// filter.excludes(relativePath: ".DS_Store", absolutePath: "/repo/.DS_Store", name: ".DS_Store", siblingNames: [])  // true
/// filter.excludes(relativePath: ".git", absolutePath: "/repo/.git", name: ".git", siblingNames: [])  // false
/// ```
struct FileExplorerExcludeFilter: Sendable, Equatable {
    /// VS Code's own `files.exclude` default.
    static let defaultPatterns = ["**/.git", "**/.svn", "**/.hg", "**/.DS_Store", "**/Thumbs.db"]

    /// The patterns in force, sorted by pattern text so equal settings compare equal.
    let rules: [FileExplorerExcludeRule]

    /// - Parameter userEntries: `fileExplorer.exclude` from cmux.json. An entry
    ///   replaces the default for the same pattern, so `false` shows what a
    ///   default hides; patterns that fail to parse are skipped.
    init(userEntries: [String: FileExplorerExcludeEntry] = [:]) {
        var merged: [String: FileExplorerExcludeEntry] = [:]
        for pattern in Self.defaultPatterns {
            merged[pattern] = .enabled(true)
        }
        merged.merge(userEntries) { _, user in user }
        rules = merged.keys.sorted().compactMap { source in
            guard let pattern = FileExplorerGlobPattern(source) else { return nil }
            switch merged[source] {
            case .enabled(true):
                return FileExplorerExcludeRule(pattern: pattern, siblingClause: nil)
            case .whenSibling(let clause):
                return FileExplorerExcludeRule(pattern: pattern, siblingClause: clause)
            case .enabled(false), nil:
                return nil
            }
        }
    }

    /// Whether the entry is hidden; see ``FileExplorerExcludeRule/excludes(relativePath:absolutePath:name:siblingNames:)``.
    func excludes(relativePath: String, absolutePath: String, name: String, siblingNames: Set<String>) -> Bool {
        rules.contains {
            $0.excludes(relativePath: relativePath, absolutePath: absolutePath, name: name, siblingNames: siblingNames)
        }
    }

    /// Whether some rule has a `when` clause, which ripgrep cannot express.
    var hasSiblingRules: Bool {
        rules.contains { $0.siblingClause != nil }
    }

    /// The rules without a `when` clause, as ripgrep `--glob` exclusions for a
    /// search of the absolute path `rootPath`.
    ///
    /// Like VS Code's search, a pattern not starting with `**` only names paths
    /// under the searched root (`build` → `!<root>/build`). ripgrep matches these
    /// against the absolute paths it prints, which holds when it runs from `/`;
    /// `when` rules are left to the result filter.
    func ripgrepExcludeGlobs(rootPath: String) -> [String] {
        var root = rootPath
        while root.count > 1, root.hasSuffix("/") {
            root.removeLast()
        }
        let rootPrefix = root == "/" ? "/" : escapingGlobCharacters(root) + "/"
        return rules.compactMap { rule in
            guard rule.siblingClause == nil else { return nil }
            var source = rule.pattern.source.trimmingCharacters(in: .whitespacesAndNewlines)
            if rule.pattern.isAbsolute || source.hasPrefix("**") {
                return "!" + source
            }
            guard root.hasPrefix("/") else { return nil }
            if source.hasPrefix("./") {
                source = String(source.dropFirst(2))
            }
            return "!" + rootPrefix + source
        }
    }

    /// Escapes the characters ripgrep's globs give meaning to, so a root such as
    /// `/src/app[1]` is matched literally.
    private func escapingGlobCharacters(_ text: String) -> String {
        var escaped = ""
        for character in text {
            if "*?[]{}\\".contains(character) {
                escaped.append("\\")
            }
            escaped.append(character)
        }
        return escaped
    }
}
