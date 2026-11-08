import Foundation

/// Which comparison a live diff tab shows for its file, like VS Code's
/// "(Working Tree)" and "(Index)" diff editors.
enum DiffEditView: String, Sendable {
    /// The index (or `HEAD`, or nothing) against the file on disk; editable.
    case workingTree
    /// `HEAD` against the index; read-only.
    case staged
    /// The file has no changes left.
    case clean
}
