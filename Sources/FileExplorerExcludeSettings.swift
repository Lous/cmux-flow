import Foundation

/// `fileExplorer.exclude` in cmux.json: VS Code's `files.exclude` for the Files tab.
///
/// cmux.json's value reaches `UserDefaults` as a JSON string under ``key``; the
/// settings file store posts ``didChangeNotification`` when it changes.
struct FileExplorerExcludeSettings {
    static let key = "fileExplorer.exclude"
    static let didChangeNotification = Notification.Name("cmux.fileExplorerExcludeDidChange")

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The filter for the current setting; VS Code's defaults when it is unset or unreadable.
    func filter() -> FileExplorerExcludeFilter {
        guard let stored = defaults.string(forKey: Self.key),
              let data = stored.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FileExplorerExcludeFilter()
        }
        return FileExplorerExcludeFilter(userEntries: object.compactMapValues { FileExplorerExcludeEntry(json: $0) })
    }

    /// Reads cmux.json's `fileExplorer.exclude` value for storage.
    ///
    /// - Parameter value: The parsed JSON value.
    /// - Returns: The JSON string to store and the patterns whose values were
    ///   skipped (neither a boolean nor `{ "when": "..." }`), or nil when the
    ///   value is not an object.
    static func storedValue(fromJSON value: Any) -> (stored: String, skippedPatterns: [String])? {
        guard let object = value as? [String: Any] else { return nil }
        var entries: [String: Any] = [:]
        var skipped: [String] = []
        for (pattern, raw) in object {
            if let entry = FileExplorerExcludeEntry(json: raw), FileExplorerGlobPattern(pattern) != nil {
                entries[pattern] = entry.json
            } else {
                skipped.append(pattern)
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys]),
              let stored = String(data: data, encoding: .utf8) else {
            return nil
        }
        return (stored, skipped.sorted())
    }
}
