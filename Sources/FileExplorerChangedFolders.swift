import Darwin
import Foundation

/// The folders a batch of file-system events touched, as Files-tree paths.
///
/// FSEvents reports the files that changed; the folder whose listing may have
/// changed is each one's parent. Events arrive with symlinks resolved
/// (`/private/var/…` for `/var/…`), so they are mapped back onto the root the
/// tree was opened with. Paths outside the root are dropped.
///
/// ```swift
/// let changed = FileExplorerChangedFolders(
///     eventPaths: ["/repo/docs/notes.md", "/repo/new.txt"],
///     rootPath: "/repo",
///     resolvedRootPath: "/repo"
/// )
/// changed.folders  // ["/repo/docs", "/repo"]
/// ```
struct FileExplorerChangedFolders: Equatable, Sendable {
    /// Folders whose listing may have changed, the root included.
    let folders: Set<String>

    /// - Parameters:
    ///   - eventPaths: Absolute paths FSEvents reported.
    ///   - rootPath: The tree's root, as its nodes spell it.
    ///   - resolvedRootPath: `rootPath` with symlinks resolved; see ``resolvedPath(_:)``.
    init(eventPaths: [String], rootPath: String, resolvedRootPath: String) {
        let root = Self.trimmingTrailingSlashes(rootPath)
        let resolvedRoot = Self.trimmingTrailingSlashes(resolvedRootPath)
        var folders = Set<String>()
        for eventPath in eventPaths {
            let path = Self.trimmingTrailingSlashes(eventPath)
            guard let treePath = Self.treePath(path, root: root, resolvedRoot: resolvedRoot),
                  treePath != root else { continue }
            folders.insert((treePath as NSString).deletingLastPathComponent)
        }
        self.folders = folders
    }

    /// Whether a batch can change what the tree lists. Git's own bookkeeping
    /// under `.git/` (index, refs, locks) cannot, and it changes on every
    /// status refresh.
    static func isListingChange(_ paths: [String]) -> Bool {
        paths.contains { !$0.contains("/.git/") }
    }

    /// `path` with symlinks resolved, the way FSEvents reports it; `path` itself
    /// when it cannot be resolved.
    static func resolvedPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func treePath(_ path: String, root: String, resolvedRoot: String) -> String? {
        if path == root || path.hasPrefix(root + "/") {
            return path
        }
        if path == resolvedRoot || path.hasPrefix(resolvedRoot + "/") {
            return root + path.dropFirst(resolvedRoot.count)
        }
        return nil
    }

    private static func trimmingTrailingSlashes(_ path: String) -> String {
        var path = path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }
}
