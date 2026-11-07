import Foundation

/// Remembers each workspace's preview diff tab, so clicking through changed
/// files reuses one tab the way VS Code's preview editor does.
///
/// A new preview opens before the previous one closes, so a split that only
/// holds the preview never collapses and reopens between clicks.
@MainActor
final class SourceControlDiffPreviewTracker {
    private var previewPanelByWorkspace: [UUID: UUID] = [:]

    /// Makes `panelId` the workspace's preview and closes the previous preview
    /// when it is still a diff viewer tab.
    func replacePreview(in workspace: Workspace, with panelId: UUID) {
        if let previous = previewPanelByWorkspace[workspace.id],
           previous != panelId,
           workspace.browserPanel(for: previous)?.currentURL?.scheme == CmuxDiffViewerURLSchemeHandler.scheme {
            _ = workspace.closePanel(previous, force: true)
        }
        previewPanelByWorkspace[workspace.id] = panelId
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
