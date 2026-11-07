import AppKit
import CmuxFoundation
import SwiftUI

/// Right-sidebar Source Control mode: every Git repository the selected
/// workspace touches, each with its branch and changed files.
///
/// Clicking a file opens its diff to the right; the repository header opens
/// the whole repository in the diff viewer.
struct SourceControlPanelView: View {
    /// Display sections; untracked files are listed with the other changes,
    /// as VS Code does, while keeping their own group for diff generation.
    private enum Section: String, CaseIterable {
        case conflicts
        case staged
        case changes

        var title: String {
            switch self {
            case .conflicts:
                return String(localized: "sourceControl.section.conflicts", defaultValue: "Merge Changes")
            case .staged:
                return String(localized: "sourceControl.section.staged", defaultValue: "Staged Changes")
            case .changes:
                return String(localized: "sourceControl.section.changes", defaultValue: "Changes")
            }
        }

        func changes(in repository: SourceControlRepositorySnapshot) -> [SourceControlFileChange] {
            switch self {
            case .conflicts:
                return repository.changes(in: .conflicts)
            case .staged:
                return repository.changes(in: .staged)
            case .changes:
                return (repository.changes(in: .unstaged) + repository.changes(in: .untracked))
                    .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            }
        }
    }

    let workspace: Workspace?
    let onOpenDiff: (SourceControlDiffRequest) -> Void
    let onOpenFile: (String) -> Void

    @State private var store: SourceControlStore
    @State private var collapsedRepositories: Set<String> = []
    @State private var collapsedSections: Set<String> = []
    @State private var selectedChangeKey: String?

    init(
        workspace: Workspace?,
        memory: SourceControlRepositoryMemory,
        onOpenDiff: @escaping (SourceControlDiffRequest) -> Void,
        onOpenFile: @escaping (String) -> Void
    ) {
        self.workspace = workspace
        self.onOpenDiff = onOpenDiff
        self.onOpenFile = onOpenFile
        _store = State(initialValue: SourceControlStore(memory: memory))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: workspace?.id) {
            store.bind(to: workspace)
        }
        .onDisappear {
            store.unbind()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            Text(repositoryCountLabel)
                .cmuxFont(size: 11, weight: .medium)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            }
            Spacer(minLength: 0)
            toolbarButton(
                symbol: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical",
                help: allCollapsed
                    ? String(localized: "sourceControl.toolbar.expandAll", defaultValue: "Expand All")
                    : String(localized: "sourceControl.toolbar.collapseAll", defaultValue: "Collapse All")
            ) {
                if allCollapsed {
                    collapsedRepositories.removeAll()
                } else {
                    collapsedRepositories = Set(store.repositories.map(\.root))
                }
            }
            .disabled(store.repositories.isEmpty)
            toolbarButton(
                symbol: "arrow.clockwise",
                help: String(localized: "sourceControl.toolbar.refresh", defaultValue: "Refresh")
            ) {
                store.refreshAll()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 26)
    }

    private func toolbarButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CmuxSystemSymbolImage(magnified: symbol, pointSize: 11, weight: .medium, tint: .secondary)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var repositoryCountLabel: String {
        let repositories = store.repositories
        let changed = repositories.filter { $0.changedPathCount > 0 }.count
        if repositories.isEmpty {
            return String(localized: "sourceControl.toolbar.title", defaultValue: "Source Control")
        }
        return String(
            localized: "sourceControl.toolbar.summary",
            defaultValue: "\(repositories.count) repositories, \(changed) with changes"
        )
    }

    private var allCollapsed: Bool {
        !store.repositories.isEmpty && store.repositories.allSatisfy { collapsedRepositories.contains($0.root) }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let reason = store.unsupportedReason {
            message(reason, symbol: "network")
        } else if !store.hasCompletedInitialLoad && store.repositories.isEmpty {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
        } else if store.repositories.isEmpty {
            message(
                String(
                    localized: "sourceControl.empty",
                    defaultValue: "No Git repositories in this workspace yet. Open the workspace on a project folder, or cd into a repository in one of its terminals."
                ),
                symbol: "arrow.triangle.branch"
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.repositories) { repository in
                        repositorySection(repository)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func repositorySection(_ repository: SourceControlRepositorySnapshot) -> some View {
        let isCollapsed = collapsedRepositories.contains(repository.root)
        SourceControlRepositoryHeaderRow(
            repository: repository,
            isCollapsed: isCollapsed,
            onToggle: { toggle(&collapsedRepositories, repository.root) },
            onOpenDiff: { source in onOpenDiff(.repository(root: repository.root, source: source)) },
            onRevealInFinder: { reveal(repository.root) },
            onCopyPath: { copy(repository.root) },
            onRemove: { store.removeRepository(repository.root) },
            onStageAll: workingTreeChanges(repository).isEmpty ? nil : {
                perform(.stage, workingTreeChanges(repository), in: repository)
            },
            onUnstageAll: repository.changes(in: .staged).isEmpty ? nil : {
                perform(.unstage, repository.changes(in: .staged), in: repository)
            },
            onDiscardAll: workingTreeChanges(repository).isEmpty ? nil : {
                perform(.discard, workingTreeChanges(repository), in: repository)
            }
        )
        if !isCollapsed {
            if let errorMessage = repository.errorMessage {
                detailText(errorMessage)
            } else {
                ForEach(Section.allCases, id: \.self) { section in
                    sectionRows(section, in: repository)
                }
                if repository.isTruncated {
                    detailText(String(
                        localized: "sourceControl.truncated",
                        defaultValue: "Showing the first \(SourceControlStatusParser.maximumEntries) changes."
                    ))
                }
            }
        }
    }

    @ViewBuilder
    private func sectionRows(_ section: Section, in repository: SourceControlRepositorySnapshot) -> some View {
        let changes = section.changes(in: repository)
        if !changes.isEmpty {
            let sectionKey = "\(repository.root)|\(section.rawValue)"
            let isCollapsed = collapsedSections.contains(sectionKey)
            SourceControlGroupHeaderRow(
                title: section.title,
                count: changes.count,
                isCollapsed: isCollapsed,
                onToggle: { toggle(&collapsedSections, sectionKey) },
                onStageAll: section == .staged ? nil : { perform(.stage, changes, in: repository) },
                onUnstageAll: section == .staged ? { perform(.unstage, changes, in: repository) } : nil,
                onDiscardAll: section == .changes ? { perform(.discard, changes, in: repository) } : nil
            )
            if !isCollapsed {
                ForEach(changes) { change in
                    fileRow(change, in: repository)
                }
            }
        }
    }

    private func fileRow(_ change: SourceControlFileChange, in repository: SourceControlRepositorySnapshot) -> some View {
        let key = "\(repository.root)|\(change.id)"
        let absolutePath = (repository.root as NSString).appendingPathComponent(change.path)
        return SourceControlFileRow(
            change: change,
            isSelected: selectedChangeKey == key,
            onOpenDiff: {
                selectedChangeKey = key
                onOpenDiff(.file(change, repositoryRoot: repository.root, opensAsPreview: true))
            },
            onOpenDiffInNewTab: {
                selectedChangeKey = key
                onOpenDiff(.file(change, repositoryRoot: repository.root, opensAsPreview: false))
            },
            onOpenFile: change.isDeletion ? nil : { onOpenFile(absolutePath) },
            onRevealInFinder: { reveal(absolutePath) },
            onCopyPath: { copy(absolutePath) },
            onCopyRelativePath: { copy(change.path) },
            onStage: change.group == .staged ? nil : { perform(.stage, [change], in: repository) },
            onUnstage: change.group == .staged ? { perform(.unstage, [change], in: repository) } : nil,
            onDiscard: (change.group == .unstaged || change.group == .untracked)
                ? { perform(.discard, [change], in: repository) }
                : nil
        )
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .cmuxFont(size: 11)
            .foregroundColor(.secondary)
            .padding(.leading, 30)
            .padding(.trailing, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            CmuxSystemSymbolImage(magnified: symbol, pointSize: 20, weight: .regular, tint: .secondary.opacity(0.6))
            Text(text)
                .cmuxFont(size: 12)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    /// Unstaged and untracked entries: what "Stage All" and "Discard All" act on.
    private func workingTreeChanges(_ repository: SourceControlRepositorySnapshot) -> [SourceControlFileChange] {
        repository.changes(in: .unstaged) + repository.changes(in: .untracked)
    }

    private func perform(
        _ action: SourceControlWorkTreeAction,
        _ changes: [SourceControlFileChange],
        in repository: SourceControlRepositorySnapshot
    ) {
        guard !changes.isEmpty else { return }
        if action == .discard, !confirmDiscard(changes) {
            return
        }
        Task { @MainActor in
            if let failure = await store.perform(action, on: changes, in: repository) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = String(localized: "sourceControl.error.actionFailed", defaultValue: "Source Control action failed")
                alert.informativeText = failure
                alert.runModal()
            }
        }
    }

    /// Discarding tracked changes cannot be undone, so it always asks first.
    private func confirmDiscard(_ changes: [SourceControlFileChange]) -> Bool {
        let paths = Set(changes.map(\.path))
        let movesToTrash = changes.contains { $0.group == .untracked }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if paths.count == 1, let path = paths.first {
            alert.messageText = String(
                localized: "sourceControl.discard.confirm.one",
                defaultValue: "Discard changes in \((path as NSString).lastPathComponent)?"
            )
        } else {
            alert.messageText = String(
                localized: "sourceControl.discard.confirm.many",
                defaultValue: "Discard changes in \(paths.count) files?"
            )
        }
        alert.informativeText = movesToTrash
            ? String(
                localized: "sourceControl.discard.detail.trash",
                defaultValue: "Changes to tracked files can't be undone. New files are moved to the Trash."
            )
            : String(localized: "sourceControl.discard.detail", defaultValue: "This can't be undone.")
        alert.addButton(withTitle: String(localized: "sourceControl.discard.button", defaultValue: "Discard Changes"))
        alert.addButton(withTitle: String(localized: "sourceControl.discard.cancel", defaultValue: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func toggle(_ set: inout Set<String>, _ key: String) {
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
    }

    private func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
