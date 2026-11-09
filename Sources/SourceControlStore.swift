import AppKit
import CmuxFoundation
import Foundation
import Observation

/// Live Git state for every repository in the selected workspace.
///
/// The Source Control panel owns one store and binds it to the selected
/// workspace. While bound, the store rediscovers repositories when the
/// workspace's directories change and refreshes a repository when FSEvents
/// reports a change under its work tree or Git directory. Nothing runs while
/// the panel is not mounted.
@MainActor
@Observable
final class SourceControlStore {
    private(set) var repositories: [SourceControlRepositorySnapshot] = []
    private(set) var hasCompletedInitialLoad = false
    /// True while a refresh the user waits on runs: the first load and the
    /// toolbar's refresh button. Refreshes driven by file changes stay silent so
    /// the toolbar does not flash every time a terminal or agent writes a file.
    private(set) var isRefreshing = false
    /// Set when the bound workspace's files live on another machine.
    private(set) var unsupportedReason: String?

    /// Repositories refreshed concurrently; more would only queue on the disk.
    private static let maximumConcurrentSnapshots = 4

    @ObservationIgnored private let client: SourceControlGitClient
    @ObservationIgnored private let memory: SourceControlRepositoryMemory
    @ObservationIgnored private weak var workspace: Workspace?
    @ObservationIgnored private(set) var workspaceId: UUID?
    @ObservationIgnored private var roots: [String] = []
    @ObservationIgnored private var gitDirectories: [String: String] = [:]
    @ObservationIgnored private var directoriesTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: RecursivePathWatcher?
    @ObservationIgnored private var watcherTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFullRefresh = false
    @ObservationIgnored private var pendingRoots: Set<String> = []
    /// Bumped on every bind and unbind so work started for an old binding is dropped.
    @ObservationIgnored private var generation = 0

    init(
        memory: SourceControlRepositoryMemory,
        client: SourceControlGitClient = SourceControlGitClient()
    ) {
        self.memory = memory
        self.client = client
    }

    func bind(to workspace: Workspace?) {
        if let workspace, workspace.id == workspaceId, self.workspace != nil {
            return
        }
        unbind()
        guard let workspace else { return }
        self.workspace = workspace
        workspaceId = workspace.id
        let currentGeneration = generation

        if workspace.usesRemoteDirectoryProvenance {
            unsupportedReason = String(
                localized: "sourceControl.unsupported.remote",
                defaultValue: "Source Control is available for workspaces on this Mac."
            )
            hasCompletedInitialLoad = true
            return
        }

        roots = memory.roots(for: workspace.id)
        // Workspace publishes its directories through Combine; consume them as
        // an async sequence at this seam. @Published replays its current value
        // on subscribe, so this also runs the first discovery.
        let directoryChanges = workspace.$panelDirectories
            .combineLatest(workspace.$currentDirectory)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .values
        directoriesTask = Task { [weak self] in
            for await (panelDirectories, currentDirectory) in directoryChanges {
                guard let self, self.generation == currentGeneration else { return }
                self.discoverRepositories(
                    candidates: Self.candidateDirectories(
                        currentDirectory: currentDirectory,
                        panelDirectories: panelDirectories
                    )
                )
            }
        }
        // FSEvents can miss changes made while the Mac slept or a volume was
        // remounted; coming back to the app is a cheap moment to re-check.
        activationTask = Task { [weak self] in
            let activations = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification)
            for await _ in activations {
                guard let self, self.generation == currentGeneration else { return }
                self.requestRefresh(nil)
            }
        }
    }

    func unbind() {
        generation &+= 1
        directoriesTask?.cancel()
        directoriesTask = nil
        activationTask?.cancel()
        activationTask = nil
        discoveryTask?.cancel()
        discoveryTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        stopWatcher()
        pendingFullRefresh = false
        pendingRoots = []
        roots = []
        gitDirectories = [:]
        repositories = []
        isRefreshing = false
        hasCompletedInitialLoad = false
        unsupportedReason = nil
        workspace = nil
        workspaceId = nil
    }

    /// Rediscovers repositories and re-reads all of them (the toolbar's refresh button).
    func refreshAll() {
        guard let workspace, unsupportedReason == nil else { return }
        discoverRepositories(
            candidates: Self.candidateDirectories(
                currentDirectory: workspace.currentDirectory,
                panelDirectories: workspace.panelDirectories
            )
        )
        requestRefresh(nil, showsProgress: true)
    }

    /// Stages, unstages or discards `changes` in `repository`, then re-reads it.
    /// Returns nil on success, or a message describing what failed.
    func perform(
        _ action: SourceControlWorkTreeAction,
        on changes: [SourceControlFileChange],
        in repository: SourceControlRepositorySnapshot
    ) async -> String? {
        let client = self.client
        let root = repository.root
        let hasCommits = repository.branch.oid != nil
        let failure = await Task.detached(priority: .userInitiated) {
            await client.perform(action, on: changes, inRepositoryRoot: root, hasCommits: hasCommits)
        }.value
        requestRefresh([root])
        return failure
    }

    /// Stops listing `root` until a terminal in this workspace enters it again.
    func removeRepository(_ root: String) {
        guard let workspaceId else { return }
        roots = memory.remove(root, for: workspaceId)
        repositories.removeAll { $0.root == root }
        restartWatcher()
    }

    // MARK: - Discovery

    private func discoverRepositories(candidates: [String]) {
        guard let workspaceId else { return }
        let client = self.client
        let currentGeneration = generation
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            let discovered = await Task.detached(priority: .utility) {
                await client.discoverRepositories(in: candidates)
            }.value
            guard !Task.isCancelled, let self, self.generation == currentGeneration else { return }
            let merged = self.memory.merge(discovered, for: workspaceId)
            let added = Set(merged).subtracting(self.roots)
            let isInitialLoad = !self.hasCompletedInitialLoad && self.refreshTask == nil
            self.roots = merged
            if isInitialLoad {
                self.requestRefresh(nil, showsProgress: true)
                self.restartWatcher()
            } else if !added.isEmpty {
                self.requestRefresh(added)
                self.restartWatcher()
            }
        }
    }

    /// The workspace directory plus every terminal's reported directory.
    private static func candidateDirectories(
        currentDirectory: String,
        panelDirectories: [UUID: String]
    ) -> [String] {
        var seen = Set<String>()
        var directories: [String] = []
        for directory in [currentDirectory] + panelDirectories.values.sorted() {
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            directories.append(trimmed)
        }
        return directories
    }

    // MARK: - Refresh

    /// Queues a status refresh for `targets`, or for every repository when nil.
    /// Requests that arrive during a refresh are folded into the next pass.
    private func requestRefresh(_ targets: Set<String>?, showsProgress: Bool = false) {
        guard workspace != nil, unsupportedReason == nil else { return }
        if showsProgress {
            isRefreshing = true
        }
        if let targets {
            pendingRoots.formUnion(targets)
        } else {
            pendingFullRefresh = true
        }
        guard refreshTask == nil else { return }
        let currentGeneration = generation
        refreshTask = Task { [weak self] in
            await self?.drainRefreshQueue(generation: currentGeneration)
        }
    }

    private func drainRefreshQueue(generation currentGeneration: Int) async {
        while generation == currentGeneration, pendingFullRefresh || !pendingRoots.isEmpty {
            let targets = pendingFullRefresh ? roots : roots.filter { pendingRoots.contains($0) }
            pendingFullRefresh = false
            pendingRoots = []
            guard !targets.isEmpty else { continue }
            let client = self.client
            let limit = Self.maximumConcurrentSnapshots
            let snapshots = await Task.detached(priority: .utility) {
                await Self.snapshots(of: targets, client: client, maximumConcurrent: limit)
            }.value
            guard generation == currentGeneration else { return }
            apply(snapshots)
        }
        guard generation == currentGeneration else { return }
        isRefreshing = false
        hasCompletedInitialLoad = true
        refreshTask = nil
    }

    private nonisolated static func snapshots(
        of roots: [String],
        client: SourceControlGitClient,
        maximumConcurrent: Int
    ) async -> [String: SourceControlRepositorySnapshot] {
        await withTaskGroup(of: SourceControlRepositorySnapshot.self) { group in
            var pending = roots.makeIterator()
            for _ in 0..<maximumConcurrent {
                guard let root = pending.next() else { break }
                group.addTask { await client.snapshot(forRepositoryRoot: root) }
            }
            var results: [String: SourceControlRepositorySnapshot] = [:]
            while let snapshot = await group.next() {
                results[snapshot.root] = snapshot
                if let root = pending.next() {
                    group.addTask { await client.snapshot(forRepositoryRoot: root) }
                }
            }
            return results
        }
    }

    private func apply(_ snapshots: [String: SourceControlRepositorySnapshot]) {
        let gone = snapshots.values.filter { !$0.isRepositoryRoot }.map(\.root)
        if !gone.isEmpty {
            forget(gone)
        }
        var byRoot: [String: SourceControlRepositorySnapshot] = [:]
        for repository in repositories {
            byRoot[repository.root] = repository
        }
        for (root, snapshot) in snapshots where snapshot.isRepositoryRoot {
            byRoot[root] = snapshot
        }
        let ordered = roots
            .compactMap { byRoot[$0] }
            .sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.root < rhs.root : order == .orderedAscending
            }
        // Skip identical snapshots so FSEvents noise does not re-render the list.
        if ordered != repositories {
            repositories = ordered
        }
    }

    /// Drops remembered roots that stopped being repositories (a project
    /// folded into a monorepo, a deleted clone), so they leave the list and
    /// are not shown again after a restart.
    private func forget(_ gone: [String]) {
        guard let workspaceId else { return }
        for root in gone {
            roots = memory.remove(root, for: workspaceId)
        }
        restartWatcher()
    }

    // MARK: - File watching

    private func restartWatcher() {
        stopWatcher()
        let roots = self.roots
        guard !roots.isEmpty else { return }
        let client = self.client
        let currentGeneration = generation
        watcherTask = Task { [weak self] in
            let gitDirectoryPairs = await Task.detached(priority: .utility) { () -> [(String, String)] in
                var pairs: [(String, String)] = []
                for root in roots {
                    if let gitDirectory = await client.gitDirectory(forRepositoryRoot: root) {
                        pairs.append((root, gitDirectory))
                    }
                }
                return pairs
            }.value
            var paths = roots
            for (root, gitDirectory) in gitDirectoryPairs where !Self.path(gitDirectory, isInside: root) {
                paths.append(gitDirectory)
            }
            guard !Task.isCancelled,
                  let watcher = await RecursivePathWatcher(
                    paths: paths,
                    throttleInterval: .milliseconds(400),
                    eventFilter: { SourceControlStore.isRelevantChange($0) }
                  ) else { return }
            guard !Task.isCancelled, let store = self, store.generation == currentGeneration else {
                await watcher.stop()
                return
            }
            store.watcher = watcher
            store.gitDirectories = Dictionary(gitDirectoryPairs, uniquingKeysWith: { first, _ in first })
            let events = watcher.pathEvents
            for await change in events {
                guard let store = self, store.generation == currentGeneration else { break }
                store.handle(change)
            }
        }
    }

    private func stopWatcher() {
        watcherTask?.cancel()
        watcherTask = nil
        if let watcher {
            Task { await watcher.stop() }
        }
        watcher = nil
    }

    private func handle(_ change: RecursivePathChange) {
        if change.requiresFullRescan {
            requestRefresh(nil)
            return
        }
        // Longest root first, so a change inside a nested repository refreshes
        // that repository rather than its parent.
        let rootsByDepth = roots.sorted { $0.count > $1.count }
        var affected = Set<String>()
        for path in change.paths where Self.isRelevantPath(path) {
            if let root = rootsByDepth.first(where: { Self.path(path, isInside: $0) }) {
                affected.insert(root)
            } else if let entry = gitDirectories.first(where: { Self.path(path, isInside: $0.value) }) {
                affected.insert(entry.key)
            }
        }
        if !affected.isEmpty {
            requestRefresh(affected)
        }
    }

    nonisolated static func isRelevantChange(_ change: RecursivePathChange) -> Bool {
        change.requiresFullRescan || change.paths.contains { isRelevantPath($0) }
    }

    /// Git object writes, reflogs and dependency folders change constantly
    /// without changing what the panel shows.
    nonisolated static func isRelevantPath(_ path: String) -> Bool {
        let noise = ["/.git/objects/", "/.git/logs/", "/.git/lfs/", "/node_modules/"]
        return !noise.contains { path.contains($0) }
    }

    nonisolated static func path(_ path: String, isInside root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }
}
