import Foundation

/// A live diff tab's file as it is now: what it is compared against, what it
/// holds, and whether the tab may write it.
struct DiffEditLoadedFile: Sendable, Equatable {
    let view: DiffEditView
    /// The left side: the index, `HEAD`, or empty for a file Git never recorded.
    let base: String
    /// The right side: the file on disk, or the index for ``DiffEditView/staged``.
    let content: String
    /// Set when the right side is the file on disk and it may be saved.
    let grant: DiffEditGrant?
    /// SHA-256 of the file's bytes on disk, echoed back on save; nil when it is not on disk.
    let sha256: String?
    /// The file was deleted in the working tree (or in the index, when staged).
    let deleted: Bool
}
