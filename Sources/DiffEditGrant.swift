import Foundation

/// One file a diff viewer page opened for editing.
///
/// `open` validates the path once and hands the page an opaque grant id; a
/// save names that id instead of a path, so a page can only write files the
/// app already checked and opened for it.
struct DiffEditGrant: Sendable, Equatable {
    /// The repository root the file was validated against (symlinks resolved).
    let repositoryRoot: String
    /// Repository-relative path, as the diff names it.
    let relativePath: String
    /// The file's absolute path before symlink resolution.
    let absolutePath: String
    /// The file's absolute path after symlink resolution; the path that is written.
    let resolvedPath: String
}
