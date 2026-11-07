import AppKit
import WebKit

extension AppDelegate {
    /// "Show in Files" from a diff viewer: opens the window's Files tab on the
    /// file. A repository-relative `path` resolves against the repository the
    /// Source Control panel opened the diff for, else the page's own `repoRoot`.
    func revealDiffFileInFiles(path: String, repoRoot: String?, from webView: WKWebView) {
        let window = webView.window
        guard let context = contextForMainWindow(window) ?? preferredRegisteredMainWindowContext(preferredWindow: window) else {
            NSSound.beep()
            return
        }
        let panelId = context.tabManager.tabs.lazy.compactMap { workspace -> UUID? in
            workspace.panels.first { _, panel in (panel as? BrowserPanel)?.webView === webView }?.key
        }.first
        let trackedRoot = panelId.flatMap { sourceControlDiffPreviewTracker.repositoryRoot(forPanel: $0) }
        let absolutePath: String
        if path.hasPrefix("/") {
            absolutePath = path
        } else if let root = trackedRoot ?? repoRoot {
            absolutePath = (root as NSString).appendingPathComponent(path)
        } else {
            NSSound.beep()
            return
        }
        _ = focusRightSidebarInActiveMainWindow(mode: .files, focusFirstItem: false, preferredWindow: window)
        // Let the Files tab sync its root for the new mode before asking it to reveal.
        Task { @MainActor in
            await Task.yield()
            context.fileExplorerState?.revealRequest = FileExplorerRevealRequest(path: absolutePath)
        }
    }
}
