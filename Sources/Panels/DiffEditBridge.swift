import CmuxBrowser
import CmuxFoundation
import ObjectiveC
import WebKit

/// Turns a Source Control file tab into a live diff editor, the way VS Code's
/// diff editor behaves: editable by default, following the file's state.
///
/// - `edit.session`: whether this tab is a Source Control file tab. The file
///   comes from the panel's own record of the tab, never from the page. A live
///   tab gets a watcher on its repository that calls the page's
///   `window.__cmuxDiffEditRefresh()` when the file, the index or `HEAD` change.
/// - `edit.load`: the file as it is now (``DiffEditFileService/load``): the
///   comparison, both texts, and a grant when the file on disk is editable.
/// - `edit.save {grant, content, expectedSha256}`: writes the file, failing
///   with `conflict` when it changed on disk since it was read.
/// - `edit.dirty {dirty}`: whether the page holds unsaved edits; a dirty tab
///   stops being the preview, survives theme reloads and asks before closing.
/// - `edit.closeTab`: closes the tab once its file has nothing left to show.
///
/// Only main-frame pages served from a registered diff viewer session may call it.
@MainActor
final class DiffEditBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "cmuxDiffEdit"
    static let shared = DiffEditBridge()
    private static var handlerInstalledKey: UInt8 = 0
    private static let refreshScript = "window.__cmuxDiffEditRefresh && window.__cmuxDiffEditRefresh();"

    private final class PageState {
        weak var webView: WKWebView?
        var panelId: UUID?
        var scope: DiffEditScope?
        var change: SourceControlFileChange?
        var preferredView: DiffEditView = .workingTree
        var grantId: String?
        var grant: DiffEditGrant?
        var dirty = false
        var watcher: RecursivePathWatcher?
        var watchTask: Task<Void, Never>?

        init(webView: WKWebView) {
            self.webView = webView
        }

        func stopWatching() {
            watchTask?.cancel()
            watchTask = nil
            if let watcher {
                Task { await watcher.stop() }
            }
            watcher = nil
        }
    }

    private let service: DiffEditFileService
    private let git: SourceControlGitClient
    private var pages: [ObjectIdentifier: PageState] = [:]

    init(service: DiffEditFileService = DiffEditFileService(), git: SourceControlGitClient = SourceControlGitClient()) {
        self.service = service
        self.git = git
    }

    /// Whether `webView`'s page holds edits it has not saved yet.
    func hasUnsavedEdits(in webView: WKWebView) -> Bool {
        guard let page = pages[ObjectIdentifier(webView)], page.webView === webView else { return false }
        return page.dirty
    }

    static func installIfNeeded(on userContentController: WKUserContentController) {
        guard objc_getAssociatedObject(userContentController, &handlerInstalledKey) == nil else { return }
        userContentController.addScriptMessageHandler(shared, contentWorld: .page, name: handlerName)
        objc_setAssociatedObject(
            userContentController,
            &handlerInstalledKey,
            NSNumber(value: true),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping (Any?, String?) -> Void
    ) {
        guard DiffCommentsBridge.isTrustedDiffViewerFrame(message.frameInfo),
              let webView = message.webView else {
            replyHandler(Self.reply(error: .notAllowed), nil)
            return
        }
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            replyHandler(Self.reply(error: .invalidRequest("Malformed edit request")), nil)
            return
        }
        let params = body["params"] as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                let value = try await self.handle(method: method, params: params, webView: webView)
                replyHandler(["ok": true, "value": value], nil)
            } catch let error as DiffEditError {
                replyHandler(Self.reply(error: error), nil)
            } catch {
                replyHandler(Self.reply(error: .io(error.localizedDescription)), nil)
            }
        }
    }

    private func handle(method: String, params: [String: Any], webView: WKWebView) async throws -> [String: Any] {
        switch method {
        case "edit.session":
            return try await startSession(webView: webView)
        case "edit.load":
            let page = pageState(for: webView)
            guard let scope = page.scope, let change = page.change else { throw DiffEditError.notEditable }
            let loaded = try await service.load(
                relativePath: change.path,
                originalPath: change.originalPath,
                preferring: page.preferredView,
                in: scope
            )
            // The page may have started another session while the file was read.
            guard page.scope == scope, page.change == change else { throw DiffEditError.notEditable }
            if loaded.view != .clean {
                page.preferredView = loaded.view
            }
            var value: [String: Any] = [
                "view": loaded.view.rawValue,
                "base": loaded.base,
                "content": loaded.content,
                "deleted": loaded.deleted,
                "editable": loaded.grant != nil,
            ]
            if let grant = loaded.grant, let sha256 = loaded.sha256 {
                if page.grant != grant || page.grantId == nil {
                    page.grantId = UUID().uuidString
                    page.grant = grant
                }
                value["grant"] = page.grantId
                value["sha256"] = sha256
            }
            return value
        case "edit.save":
            guard let grantId = params["grant"] as? String,
                  let content = params["content"] as? String,
                  let expectedSHA256 = params["expectedSha256"] as? String else {
                throw DiffEditError.invalidRequest("Missing grant, content or expectedSha256")
            }
            let page = pageState(for: webView)
            guard let grant = page.grant, page.grantId == grantId else { throw DiffEditError.notAllowed }
            let sha256 = try await service.save(content, to: grant, expectedSHA256: expectedSHA256)
            return ["sha256": sha256]
        case "edit.dirty":
            guard let dirty = params["dirty"] as? Bool else { throw DiffEditError.invalidRequest("Missing dirty") }
            let page = pageState(for: webView)
            guard page.change != nil else { throw DiffEditError.notEditable }
            page.dirty = dirty
            if let panelId = page.panelId {
                AppDelegate.shared?.sourceControlDiffPreviewTracker.setEditing(dirty, panelId: panelId)
            }
            return [:]
        case "edit.closeTab":
            let page = pageState(for: webView)
            guard !page.dirty, let panelId = page.panelId else { return ["closed": false] }
            let closed = AppDelegate.shared?.sourceControlDiffPreviewTracker.closeFileTab(panelId: panelId) ?? false
            return ["closed": closed]
        default:
            throw DiffEditError.invalidRequest("Unsupported method '\(method)'")
        }
    }

    /// Binds the page to the file its Source Control tab shows, if it is one.
    private func startSession(webView: WKWebView) async throws -> [String: Any] {
        let page = pageState(for: webView)
        page.stopWatching()
        page.scope = nil
        page.change = nil
        page.grant = nil
        page.grantId = nil
        page.dirty = false
        guard let panelId = DiffCommentsBridge.associatedPanelId(of: webView),
              let tracked = AppDelegate.shared?.sourceControlDiffPreviewTracker.trackedFile(forPanel: panelId),
              let scope = await service.scope(forRepositoryRoot: tracked.root) else {
            return ["live": false]
        }
        page.panelId = panelId
        page.scope = scope
        page.change = tracked.change
        page.preferredView = tracked.change.group == .staged ? .staged : .workingTree
        await watch(page, scope: scope, relativePath: tracked.change.path)
        return ["live": true, "path": tracked.change.path]
    }

    /// Calls the page back when its file, the index, `HEAD` or the branch move.
    private func watch(_ page: PageState, scope: DiffEditScope, relativePath: String) async {
        var paths = [scope.repositoryRoot]
        if let gitDirectory = await git.gitDirectory(forRepositoryRoot: scope.repositoryRoot),
           !SourceControlStore.path(gitDirectory, isInside: scope.repositoryRoot) {
            paths.append(gitDirectory)
        }
        let filePath = (scope.repositoryRoot as NSString).appendingPathComponent(relativePath)
        guard let watcher = await RecursivePathWatcher(
            paths: paths,
            throttleInterval: .milliseconds(300),
            eventFilter: { change in
                change.requiresFullRescan || change.paths.contains { path in
                    path == filePath || (path.contains("/.git/") && SourceControlStore.isRelevantPath(path))
                }
            }
        ) else { return }
        page.watcher = watcher
        page.watchTask = Task { @MainActor [weak page] in
            for await _ in watcher.events {
                guard let page, let webView = page.webView else { break }
                webView.evaluateJavaScript(Self.refreshScript, completionHandler: nil)
            }
            page?.stopWatching()
        }
    }

    private func pageState(for webView: WKWebView) -> PageState {
        for (key, page) in pages where page.webView == nil {
            page.stopWatching()
            pages.removeValue(forKey: key)
        }
        let key = ObjectIdentifier(webView)
        if let page = pages[key], page.webView === webView {
            return page
        }
        let page = PageState(webView: webView)
        pages[key] = page
        return page
    }

    private static func reply(error: DiffEditError) -> [String: Any] {
        var detail: [String: Any] = ["code": error.code, "userMessage": error.userMessage]
        if case .conflict(let currentSHA256) = error {
            detail["currentSha256"] = currentSHA256
        }
        return ["ok": false, "error": detail]
    }
}
