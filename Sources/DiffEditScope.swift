import Foundation

/// The repository a diff viewer page may edit files in, decided by the app
/// from what the page shows rather than from a path the page supplies.
struct DiffEditScope: Sendable, Equatable {
    /// Repository root, symlinks resolved.
    let repositoryRoot: String
}
