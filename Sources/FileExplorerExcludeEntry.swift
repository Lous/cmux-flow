import Foundation

/// One value in `fileExplorer.exclude`, as in VS Code's `files.exclude`.
enum FileExplorerExcludeEntry: Sendable, Equatable {
    /// `true` hides what the pattern matches; `false` turns off a default pattern.
    case enabled(Bool)
    /// `{ "when": "$(basename).ts" }`: hides a match only when a sibling with
    /// that name exists, where `$(basename)` is the match's name without its
    /// last extension.
    case whenSibling(String)

    /// Reads a cmux.json value; nil for anything else (a number, a string, an
    /// object without a string `when`).
    init?(json value: Any) {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            self = .enabled(number.boolValue)
        } else if let object = value as? [String: Any], let clause = object["when"] as? String, !clause.isEmpty {
            self = .whenSibling(clause)
        } else {
            return nil
        }
    }

    /// The value written back as JSON.
    var json: Any {
        switch self {
        case .enabled(let enabled):
            return enabled
        case .whenSibling(let clause):
            return ["when": clause]
        }
    }
}
