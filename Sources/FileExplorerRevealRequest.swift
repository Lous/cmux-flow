import Foundation

/// A file the Files tab should expand to, select and scroll into view
/// ("Show in Files" from a diff). Each request is distinct, so asking for the
/// same file twice reveals it twice.
struct FileExplorerRevealRequest: Equatable {
    let id = UUID()
    let path: String
}
