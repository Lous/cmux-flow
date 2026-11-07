import CmuxBrowser
import ObjectiveC
import WebKit

/// Receives "Show in Files" from a diff viewer page: `{path, repoRoot?}` for one
/// file of the diff. One-way and read-only: it only reveals the file in the
/// window's Files tab, and only for messages from a trusted diff viewer frame.
@MainActor
final class DiffRevealFileBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "cmuxDiffRevealFile"
    static let shared = DiffRevealFileBridge()
    private static var handlerInstalledKey: UInt8 = 0

    static func installIfNeeded(on userContentController: WKUserContentController) {
        guard objc_getAssociatedObject(userContentController, &handlerInstalledKey) == nil else { return }
        userContentController.add(shared, contentWorld: .page, name: handlerName)
        objc_setAssociatedObject(
            userContentController,
            &handlerInstalledKey,
            NSNumber(value: true),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard DiffCommentsBridge.isTrustedDiffViewerFrame(message.frameInfo),
              let webView = message.webView,
              let body = message.body as? [String: Any],
              let path = body["path"] as? String,
              !path.isEmpty,
              path.count <= 4096 else { return }
        let repoRoot = (body["repoRoot"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        AppDelegate.shared?.revealDiffFileInFiles(path: path, repoRoot: repoRoot, from: webView)
    }
}
