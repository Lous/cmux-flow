import Foundation

/// Why the diff viewer could not open or save a file for editing.
enum DiffEditError: Error, Equatable, Sendable {
    /// The page is not a trusted diff viewer, or its grant is not its own.
    case notAllowed
    /// The request was malformed.
    case invalidRequest(String)
    /// This page is not a Source Control file tab.
    case notEditable
    /// The path escapes the repository, names Git's own directory, or is not a regular file.
    case pathRejected
    /// The file is too large to edit in the viewer.
    case tooLarge
    /// The file is not UTF-8 text.
    case binary
    /// The file changed on disk since it was opened; `currentSHA256` is its new content's hash.
    case conflict(currentSHA256: String)
    /// Reading or writing the file failed.
    case io(String)

    var code: String {
        switch self {
        case .notAllowed: return "not_allowed"
        case .invalidRequest: return "invalid_request"
        case .notEditable: return "not_editable"
        case .pathRejected: return "path_rejected"
        case .tooLarge: return "too_large"
        case .binary: return "binary"
        case .conflict: return "conflict"
        case .io: return "io"
        }
    }

    var userMessage: String {
        switch self {
        case .notAllowed:
            return String(localized: "diffEdit.error.notAllowed", defaultValue: "This page cannot edit files.")
        case .invalidRequest(let detail):
            return detail
        case .notEditable:
            return String(
                localized: "diffEdit.error.notEditable",
                defaultValue: "Only working-tree changes can be edited."
            )
        case .pathRejected:
            return String(
                localized: "diffEdit.error.pathRejected",
                defaultValue: "This file is outside the repository and cannot be edited here."
            )
        case .tooLarge:
            return String(localized: "diffEdit.error.tooLarge", defaultValue: "This file is too large to edit here.")
        case .binary:
            return String(localized: "diffEdit.error.binary", defaultValue: "Binary files cannot be edited here.")
        case .conflict:
            return String(
                localized: "diffEdit.error.conflict",
                defaultValue: "The file changed on disk since you opened it."
            )
        case .io(let detail):
            return detail
        }
    }
}
