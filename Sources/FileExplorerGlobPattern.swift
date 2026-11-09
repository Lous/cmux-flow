import Foundation

/// A glob in VS Code's `files.exclude` syntax, matched against a `/`-separated path.
///
/// - `**` matches any number of folders, including none: `**/.git` matches
///   `.git` and `a/b/.git`.
/// - `*` and `?` match within one path part; `[a-z]` and `[!0-9]` match one
///   character from (or outside) a set.
/// - `{a,b}` matches either alternative and may hold `/`: `{**/*.html,**/*.txt}`.
/// - A pattern starting with `/` is matched against absolute paths; any other
///   against the path relative to the explorer's root, so `build` only names the
///   root's `build` folder.
///
/// Matching is case-sensitive, like VS Code's.
struct FileExplorerGlobPattern: Sendable, Equatable {
    /// The pattern as written in cmux.json.
    let source: String
    /// Matched against absolute paths rather than root-relative ones.
    let isAbsolute: Bool
    private let alternatives: [[FileExplorerGlobSegment]]

    /// Braces past this many alternatives are left unexpanded, so a hostile
    /// pattern cannot make matching explode.
    private static let maximumAlternatives = 64

    init?(_ source: String) {
        var text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("./") {
            text.removeFirst(2)
        }
        while text.count > 1, text.hasSuffix("/") {
            text.removeLast()
        }
        guard !text.isEmpty else { return nil }
        self.source = source
        isAbsolute = text.hasPrefix("/")
        alternatives = Self.expandingBraces(text).map { alternative in
            var segments: [FileExplorerGlobSegment] = []
            for part in alternative.split(separator: "/", omittingEmptySubsequences: true) {
                let segment = FileExplorerGlobSegment(String(part))
                // Repeated `**` adds nothing but backtracking.
                if segment.isGlobstar, segments.last?.isGlobstar == true {
                    continue
                }
                segments.append(segment)
            }
            return segments
        }.filter { !$0.isEmpty }
        guard !alternatives.isEmpty else { return nil }
    }

    /// Whether `path` (`/`-separated; root-relative unless ``isAbsolute``) matches.
    func matches(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        return alternatives.contains { Self.matches($0[...], parts[...]) }
    }

    private static func matches(
        _ segments: ArraySlice<FileExplorerGlobSegment>,
        _ parts: ArraySlice<String>
    ) -> Bool {
        guard let segment = segments.first else { return parts.isEmpty }
        if segment.isGlobstar {
            let rest = segments.dropFirst()
            var remaining = parts
            while true {
                if matches(rest, remaining) { return true }
                guard !remaining.isEmpty else { return false }
                remaining = remaining.dropFirst()
            }
        }
        guard let part = parts.first, segment.matches(part) else { return false }
        return matches(segments.dropFirst(), parts.dropFirst())
    }

    /// `a{b,c}d` → `abd`, `acd`; nested braces expand too.
    private static func expandingBraces(_ text: String) -> [String] {
        var results: [String] = []
        var pending = [text]
        while let next = pending.popLast() {
            guard let (prefix, options, suffix) = firstBraceGroup(in: next),
                  results.count + pending.count + options.count <= maximumAlternatives else {
                results.append(next)
                continue
            }
            pending.append(contentsOf: options.reversed().map { prefix + $0 + suffix })
        }
        return results
    }

    private static func firstBraceGroup(in text: String) -> (String, [String], String)? {
        let characters = Array(text)
        var depth = 0
        var open = 0
        for (index, character) in characters.enumerated() {
            if character == "{" {
                if depth == 0 { open = index }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                guard depth == 0 else { continue }
                var options: [String] = []
                var current = ""
                var innerDepth = 0
                for inner in characters[(open + 1)..<index] {
                    if inner == "{" { innerDepth += 1 }
                    if inner == "}" { innerDepth -= 1 }
                    if inner == ",", innerDepth == 0 {
                        options.append(current)
                        current = ""
                    } else {
                        current.append(inner)
                    }
                }
                options.append(current)
                return (String(characters[..<open]), options, String(characters[(index + 1)...]))
            }
        }
        return nil
    }
}
