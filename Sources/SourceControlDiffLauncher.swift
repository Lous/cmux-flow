import AppKit
import CmuxSettings
import Foundation

/// Opens Source Control diffs in the diff viewer, through the same bundled
/// `cmux diff` process the Open Diff Viewer shortcut uses.
///
/// A file click renders a single-file patch; a repository action hands
/// `cmux diff` a git source so the viewer keeps its file tree and pickers.
/// Diffs open to the right without taking focus, so clicking through files
/// keeps the keyboard in the panel.
@MainActor
struct SourceControlDiffLauncher {
    private let client: SourceControlGitClient
    private let patchDirectory: URL

    /// - Parameters:
    ///   - client: Generates single-file patches.
    ///   - patchDirectory: Scratch folder for patch files. `cmux diff` reads a
    ///     patch into memory before it opens the viewer, so files are pruned
    ///     shortly after they are written.
    init(
        client: SourceControlGitClient = SourceControlGitClient(),
        patchDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-source-control", isDirectory: true)
    ) {
        self.client = client
        self.patchDirectory = patchDirectory
    }

    /// Opens `request`'s diff. `replacedPanelId` names a tracked diff tab this one
    /// supersedes (a theme change reopening it); it closes once the new one is up.
    func open(_ request: SourceControlDiffRequest, in workspace: Workspace, replacing replacedPanelId: UUID? = nil) {
        let track: @MainActor (UUID) -> Void = { [weak workspace] surfaceId in
            guard let workspace else { return }
            AppDelegate.shared?.sourceControlDiffPreviewTracker.didOpen(
                panelId: surfaceId,
                request: request,
                in: workspace,
                replacing: replacedPanelId
            )
        }
        switch request {
        case .repository(let root, let source):
            launch(sourceArguments: [source.cliFlag], cwd: root, workspace: workspace, onOpened: track)
        case .file(let change, let root, _):
            let client = self.client
            let directory = patchDirectory
            let title = "\((root as NSString).lastPathComponent): \(change.path)"
            Task { [weak workspace] in
                let patchURL = await Task.detached(priority: .userInitiated) { () -> URL? in
                    guard let patch = await client.patch(for: change, inRepositoryRoot: root) else { return nil }
                    return Self.writePatch(patch, to: directory)
                }.value
                // The workspace may have closed while the patch was being generated.
                guard let workspace else { return }
                guard let patchURL else {
                    NSSound.beep()
                    return
                }
                launch(
                    sourceArguments: [patchURL.path, "--title", title],
                    cwd: root,
                    workspace: workspace,
                    onOpened: track
                )
            }
        }
    }

    private func launch(
        sourceArguments: [String],
        cwd: String,
        workspace: Workspace,
        onOpened: @escaping @MainActor (UUID) -> Void
    ) {
        guard let appDelegate = AppDelegate.shared,
              let cliURL = Bundle.main.resourceURL?.appendingPathComponent("bin/cmux"),
              FileManager.default.isExecutableFile(atPath: cliURL.path) else {
            NSSound.beep()
            return
        }
        let socketPath = TerminalController.shared.activeSocketPath(
            preferredPath: SocketControlSettings.socketPath()
        )
        appDelegate.launchDiffViewerProcess(
            cliURL: cliURL,
            socketPath: socketPath,
            cwd: cwd,
            workspaceId: workspace.id,
            surfaceId: workspace.focusedPanelId,
            useLastTurnSource: false,
            sessionId: nil,
            focus: false,
            sourceArguments: sourceArguments,
            globalArguments: ["--id-format", "uuids"],
            onExit: { status, output in
                guard status == 0,
                      let surfaceId = SourceControlDiffPreviewTracker.openedSurfaceId(fromCLIOutput: output) else { return }
                onOpened(surfaceId)
            }
        )
    }

    private nonisolated static func writePatch(_ patch: String, to directory: URL) -> URL? {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        pruneStalePatches(in: directory, fileManager: fileManager)
        let url = directory.appendingPathComponent("\(UUID().uuidString).patch", isDirectory: false)
        do {
            try patch.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Removes patches older than a minute; the CLI has read them long before.
    private nonisolated static func pruneStalePatches(in directory: URL, fileManager: FileManager) {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-60)
        for entry in entries where entry.pathExtension == "patch" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }
}
