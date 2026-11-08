import Foundation

/// Remembers the diff tabs the Source Control panel opened.
///
/// - A file click reuses one preview tab per workspace, the way VS Code's
///   preview editor does: a new preview opens before the previous one closes,
///   so a split that only holds the preview never collapses between clicks.
/// - A diff viewer bakes the terminal theme's syntax colors in when it opens,
///   so after a theme change every tracked diff is reopened in place with the
///   new theme instead of keeping colors from the old one.
/// - A diff tab with unsaved edits is kept: it stops being the preview (the
///   next click opens a new one) and theme reloads skip it.
@MainActor
final class SourceControlDiffPreviewTracker {
    private struct OpenDiff {
        let request: SourceControlDiffRequest
        weak var workspace: Workspace?
    }

    private var previewPanelByWorkspace: [UUID: UUID] = [:]
    private var openDiffs: [UUID: OpenDiff] = [:]
    private var editingPanels: Set<UUID> = []
    private var themeObservation: Task<Void, Never>?
    private var pendingThemeReopen: Task<Void, Never>?
    /// Theme reloads arrive in bursts (one per surface); reopen once they settle.
    private let themeReopenDelay: Duration

    init(themeReopenDelay: Duration = .milliseconds(600)) {
        self.themeReopenDelay = themeReopenDelay
    }

    /// Records a diff tab the panel opened, closing the tab it supersedes: the
    /// workspace's previous preview for a preview request, or `replacedPanelId`.
    func didOpen(
        panelId: UUID,
        request: SourceControlDiffRequest,
        in workspace: Workspace,
        replacing replacedPanelId: UUID?
    ) {
        startObservingThemeChanges()
        if case .file(_, _, true) = request {
            if let previous = previewPanelByWorkspace[workspace.id], previous != panelId {
                close(previous, in: workspace)
            }
            previewPanelByWorkspace[workspace.id] = panelId
        }
        if let replacedPanelId, replacedPanelId != panelId {
            close(replacedPanelId, in: workspace)
        }
        openDiffs[panelId] = OpenDiff(request: request, workspace: workspace)
        pruneClosedDiffs()
    }

    /// The repository a tracked diff tab shows, for resolving its relative paths.
    func repositoryRoot(forPanel panelId: UUID) -> String? {
        switch openDiffs[panelId]?.request {
        case .file(_, let root, _): return root
        case .repository(let root, _): return root
        case nil: return nil
        }
    }

    /// The file a tracked single-file diff tab shows, as the panel opened it.
    func trackedFile(forPanel panelId: UUID) -> (change: SourceControlFileChange, root: String)? {
        guard case .file(let change, let root, _)? = openDiffs[panelId]?.request else { return nil }
        return (change, root)
    }

    /// Closes a tracked single-file diff tab whose file has nothing left to show.
    @discardableResult
    func closeFileTab(panelId: UUID) -> Bool {
        guard case .file? = openDiffs[panelId]?.request,
              let workspace = openDiffs[panelId]?.workspace else { return false }
        close(panelId, in: workspace)
        return true
    }

    /// Marks a diff tab as holding unsaved edits, or not.
    func setEditing(_ editing: Bool, panelId: UUID) {
        guard editing else {
            editingPanels.remove(panelId)
            return
        }
        editingPanels.insert(panelId)
        // Like VS Code, editing a preview pins it.
        previewPanelByWorkspace = previewPanelByWorkspace.filter { $0.value != panelId }
    }

    private func close(_ panelId: UUID, in workspace: Workspace) {
        openDiffs.removeValue(forKey: panelId)
        editingPanels.remove(panelId)
        guard Self.isDiffViewer(panelId, in: workspace) else { return }
        _ = workspace.closePanel(panelId, force: true)
    }

    private func pruneClosedDiffs() {
        openDiffs = openDiffs.filter { panelId, diff in
            guard let workspace = diff.workspace else { return false }
            return Self.isDiffViewer(panelId, in: workspace)
        }
        editingPanels = editingPanels.filter { openDiffs[$0] != nil }
    }

    private static func isDiffViewer(_ panelId: UUID, in workspace: Workspace) -> Bool {
        workspace.browserPanel(for: panelId)?.currentURL?.scheme == CmuxDiffViewerURLSchemeHandler.scheme
    }

    // MARK: - Theme changes

    private func startObservingThemeChanges() {
        guard themeObservation == nil else { return }
        themeObservation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .ghosttyConfigDidReload) {
                self?.scheduleThemeReopen()
            }
        }
    }

    private func scheduleThemeReopen() {
        pendingThemeReopen?.cancel()
        let delay = themeReopenDelay
        pendingThemeReopen = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reopenTrackedDiffs()
        }
    }

    private func reopenTrackedDiffs() {
        pruneClosedDiffs()
        let launcher = SourceControlDiffLauncher()
        for (panelId, diff) in openDiffs where !editingPanels.contains(panelId) {
            guard let workspace = diff.workspace else { continue }
            launcher.open(diff.request, in: workspace, replacing: panelId)
        }
    }

    /// The surface UUID `cmux --id-format uuids diff` prints as `OK surface=<UUID> pane=<UUID>`.
    nonisolated static func openedSurfaceId(fromCLIOutput output: String) -> UUID? {
        for token in output.split(whereSeparator: { $0 == " " || $0 == "\n" }) where token.hasPrefix("surface=") {
            if let id = UUID(uuidString: String(token.dropFirst("surface=".count))) {
                return id
            }
        }
        return nil
    }
}
