import CmuxFoundation
import Foundation

/// Keeps the Files explorer's git decorations live.
///
/// The explorer's own directory watcher only sees entries added or removed at
/// its root, so editing a file deeper in a repository never re-colored it.
/// This watches the repositories behind the explorer root recursively
/// (FSEvents, coalesced) and asks the store to re-read git status, the same
/// way VS Code updates its explorer decorations as files change.
@MainActor
final class FileExplorerGitStatusWatcher {
    private var watchedRoots: [String] = []
    private var watcher: RecursivePathWatcher?
    private var task: Task<Void, Never>?
    private let throttleInterval: Duration

    /// - Parameter throttleInterval: Minimum spacing between change signals;
    ///   a build writing many files triggers one status refresh per window.
    init(throttleInterval: Duration = .milliseconds(500)) {
        self.throttleInterval = throttleInterval
    }

    /// Watches `repositoryRoots`, calling `onChange` after relevant changes.
    /// Calling again with the same roots keeps the current watcher.
    func watch(repositoryRoots: [String], onChange: @escaping @MainActor () -> Void) {
        let roots = Array(Set(repositoryRoots)).sorted()
        guard roots != watchedRoots || task == nil else { return }
        stop()
        guard !roots.isEmpty else { return }
        watchedRoots = roots
        let throttle = throttleInterval
        task = Task { [weak self] in
            guard let watcher = await RecursivePathWatcher(
                paths: roots,
                throttleInterval: throttle,
                eventFilter: { SourceControlStore.isRelevantChange($0) }
            ) else { return }
            guard !Task.isCancelled, let owner = self else {
                await watcher.stop()
                return
            }
            owner.watcher = watcher
            for await _ in watcher.events {
                guard !Task.isCancelled else { break }
                onChange()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        watchedRoots = []
        if let watcher {
            Task { await watcher.stop() }
        }
        watcher = nil
    }
}
