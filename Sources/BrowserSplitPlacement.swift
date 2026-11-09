/// The result of placing a browser beside a source surface.
@MainActor
struct BrowserSplitPlacement {
    let panel: BrowserPanel
    let strategy: BrowserSplitPlacementStrategy

    var createdSplit: Bool { strategy == .splitRight }
}
