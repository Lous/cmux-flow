/// How a browser panel (a diff viewer, for one) found its pane.
enum BrowserSplitPlacementStrategy: Sendable, Equatable {
    /// A new horizontal split to the right of the source pane.
    case splitRight
    /// A tab in the pane already to the right of the source pane.
    case reuseRightSibling
    /// A tab in the source pane itself.
    case samePane
    /// A tab in another open pane that is not to the right.
    case reuseExistingPane

    /// The `placement_strategy` value the socket API reports.
    var wireName: String {
        switch self {
        case .splitRight: return "split_right"
        case .reuseRightSibling: return "reuse_right_sibling"
        case .samePane: return "same_pane"
        case .reuseExistingPane: return "reuse_existing_pane"
        }
    }
}
