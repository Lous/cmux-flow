import Foundation

/// Runs the Git commands behind the Source Control panel.
///
/// Commands use `GIT_OPTIONAL_LOCKS=0` (like ``GitStatusProvider``) so
/// refreshing the panel never writes the index or contends with a Git command
/// the user is running.
struct SourceControlGitClient: Sendable {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
    }

    /// Upper bound on repositories the panel tracks for one workspace.
    static let maximumRepositories = 24

    private let gitExecutableURL: URL
    private let environment: [String: String]
    private let timeout: Duration
    private let parser: SourceControlStatusParser
    private let homeDirectory: String

    /// - Parameters:
    ///   - gitExecutableURL: Git binary; `/usr/bin/git` matches the Files explorer.
    ///   - environment: Base environment; repository overrides are stripped.
    ///   - timeout: Upper bound for one Git command, so a wedged Git (network
    ///     filesystem, stuck fsmonitor) cannot pin a refresh forever.
    ///   - homeDirectory: Never scanned for child repositories.
    init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(15),
        parser: SourceControlStatusParser = SourceControlStatusParser(),
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.gitExecutableURL = gitExecutableURL
        var environment = environment
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        // An inherited repository override would point every command at one repo.
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX"] {
            environment.removeValue(forKey: key)
        }
        self.environment = environment
        self.timeout = timeout
        self.parser = parser
        self.homeDirectory = Self.normalizedPath(homeDirectory)
    }

    /// Runs `git <arguments>` in `directory`; nil when Git could not be launched.
    func run(_ arguments: [String], in directory: String) async -> Output? {
        let process = Process()
        process.executableURL = gitExecutableURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let (exitStatuses, exitContinuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }
        do {
            try process.run()
        } catch {
            return nil
        }

        let limit = timeout
        let deadline = Task.detached(priority: .utility) {
            try? await Task.sleep(for: limit)
            // Process.terminate is safe from any thread; it ends the read below.
            if !Task.isCancelled, process.isRunning {
                process.terminate()
            }
        }
        // Drain stdout while Git runs so a large status cannot fill the pipe and stall it.
        let readDescriptor = pipe.fileHandleForReading.fileDescriptor
        let data = await Task.detached(priority: .utility) {
            Self.readToEnd(fileDescriptor: readDescriptor)
        }.value
        var status: Int32 = -1
        for await exitStatus in exitStatuses {
            status = exitStatus
        }
        deadline.cancel()
        withExtendedLifetime(pipe) {}
        return Output(status: status, stdout: data)
    }

    private static func readToEnd(fileDescriptor: Int32) -> Data {
        let handle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)
        return (try? handle.readToEnd()) ?? Data()
    }

    private func firstLine(_ arguments: [String], in directory: String) async -> String? {
        guard let output = await run(arguments, in: directory), output.status == 0 else { return nil }
        let text = String(decoding: output.stdout, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Discovery

    /// The repository root containing `directory`, or nil outside a work tree.
    func repositoryRoot(containing directory: String) async -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return await firstLine(["rev-parse", "--show-toplevel"], in: directory)
    }

    /// The repository's Git directory. For a linked worktree it lives outside
    /// the root, so the panel watches it separately to see commits and staging.
    func gitDirectory(forRepositoryRoot root: String) async -> String? {
        await firstLine(["rev-parse", "--absolute-git-dir"], in: root).map(Self.normalizedPath)
    }

    /// Resolves the repositories behind a workspace's directories.
    ///
    /// A directory inside a work tree contributes that repository. A directory
    /// that is not itself in a repository (a workspace opened on a folder of
    /// projects) contributes each immediate child that is a repository root.
    func discoverRepositories(in candidateDirectories: [String]) async -> [String] {
        var roots: [String] = []
        var seen = Set<String>()
        for candidate in candidateDirectories {
            let found: [String]
            if let root = await repositoryRoot(containing: candidate) {
                found = [root]
            } else {
                found = childRepositoryRoots(of: candidate)
            }
            for root in found {
                guard roots.count < Self.maximumRepositories else { return roots }
                let normalized = Self.normalizedPath(root)
                if seen.insert(normalized).inserted {
                    roots.append(normalized)
                }
            }
        }
        return roots
    }

    private func childRepositoryRoots(of directory: String) -> [String] {
        let normalized = Self.normalizedPath(directory)
        // Scanning the home folder or the volume root would touch protected
        // folders (Desktop, Documents) and is never a project container.
        guard normalized != "/", normalized != homeDirectory else { return [] }
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(atPath: normalized) else { return [] }
        return children
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { name -> String? in
                let child = (normalized as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue else {
                    return nil
                }
                // `.git` is a directory for a clone and a file for a linked worktree or submodule.
                let marker = (child as NSString).appendingPathComponent(".git")
                return fileManager.fileExists(atPath: marker) ? child : nil
            }
    }

    /// Physical absolute path, the spelling Git and FSEvents both report.
    ///
    /// `realpath` rather than `URL.resolvingSymlinksInPath()`, which strips the
    /// `/private` prefix (`/private/tmp` becomes `/tmp`) so FSEvents paths would
    /// no longer match the repository roots they belong to.
    static func normalizedPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard let resolved = realpath(standardized, nil) else { return standardized }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Status

    /// Branch, changed files and line counts for one repository.
    func snapshot(forRepositoryRoot root: String) async -> SourceControlRepositorySnapshot {
        guard let statusOutput = await run(
            ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"],
            in: root
        ) else {
            return SourceControlRepositorySnapshot(
                root: root,
                branch: SourceControlBranchInfo(),
                changes: [],
                errorMessage: String(localized: "sourceControl.error.gitUnavailable", defaultValue: "Git could not be started.")
            )
        }
        guard statusOutput.status == 0 else {
            return SourceControlRepositorySnapshot(
                root: root,
                branch: SourceControlBranchInfo(),
                changes: [],
                errorMessage: String(localized: "sourceControl.error.statusFailed", defaultValue: "git status failed for this repository.")
            )
        }

        let status = parser.parseStatus(statusOutput.stdout)
        var changes = status.changes
        let hasStaged = changes.contains { $0.group == .staged }
        let hasUnstaged = changes.contains { $0.group == .unstaged }
        async let stagedCounts = hasStaged
            ? numstat(["diff", "--cached", "--numstat", "-z", "--no-ext-diff"], in: root)
            : [:]
        async let unstagedCounts = hasUnstaged
            ? numstat(["diff", "--numstat", "-z", "--no-ext-diff"], in: root)
            : [:]
        let staged = await stagedCounts
        let unstaged = await unstagedCounts
        for index in changes.indices {
            let counts: SourceControlStatusParser.LineCounts?
            switch changes[index].group {
            case .staged: counts = staged[changes[index].path]
            case .unstaged: counts = unstaged[changes[index].path]
            case .conflicts, .untracked: counts = nil
            }
            changes[index].additions = counts?.additions
            changes[index].deletions = counts?.deletions
        }
        return SourceControlRepositorySnapshot(
            root: root,
            branch: status.branch,
            changes: changes,
            isTruncated: status.isTruncated
        )
    }

    private func numstat(_ arguments: [String], in root: String) async -> [String: SourceControlStatusParser.LineCounts] {
        guard let output = await run(arguments, in: root), output.status == 0 else { return [:] }
        return parser.parseNumstat(output.stdout)
    }

    // MARK: - Patches

    /// A unified diff for one entry, in the format `cmux diff` renders.
    func patch(for change: SourceControlFileChange, inRepositoryRoot root: String) async -> String? {
        let base = ["diff", "--no-ext-diff", "--no-color", "--binary"]
        let arguments: [String]
        var allowedStatuses: Set<Int32> = [0]
        switch change.group {
        case .staged:
            if let originalPath = change.originalPath {
                arguments = base + ["--cached", "-M", "--", originalPath, change.path]
            } else {
                arguments = base + ["--cached", "--", change.path]
            }
        case .unstaged, .conflicts:
            arguments = base + ["--", change.path]
        case .untracked:
            // --no-index exits 1 when the files differ, which is always the case here.
            arguments = base + ["--no-index", "--", "/dev/null", change.path]
            allowedStatuses = [0, 1]
        }
        guard let output = await run(arguments, in: root), allowedStatuses.contains(output.status) else { return nil }
        return String(decoding: output.stdout, as: UTF8.self)
    }
}
