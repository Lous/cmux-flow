import CmuxFoundation
import Foundation

/// Runs non-locking `git status --porcelain` and parses results into a path-to-status map.
struct GitStatusProvider: Sendable {
    private static let nonLockingGitEnvironmentKey = "GIT_OPTIONAL_LOCKS"
    private static let nonLockingGitEnvironmentValue = "0"
    private static let nonLockingRemoteGitCommand = "env \(nonLockingGitEnvironmentKey)=\(nonLockingGitEnvironmentValue) git"

    private let gitExecutableURL: URL
    private let sshExecutableURL: URL
    private let environment: [String: String]

    init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        sshExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.sshExecutableURL = sshExecutableURL
        self.environment = environment
    }

    /// Git status for an explorer root, plus what the explorer needs to keep it live.
    struct Result: Equatable, Sendable {
        var statusByPath: [String: GitFileStatus] = [:]
        /// Directories Git reported whole (`?? dir/`): everything inside them is untracked.
        var untrackedDirectories: [String] = []
        /// Work trees the status came from, physically spelled, for change watching.
        var repositoryRoots: [String] = []
    }

    /// Most repositories a folder of projects contributes, so a huge container
    /// folder cannot fan out into hundreds of `git status` runs.
    private static let maximumNestedRepositories = 24

    func fetchStatus(directory: String) -> [String: GitFileStatus] {
        fetchStatusResult(directory: directory).statusByPath
    }

    /// Status for `directory`. Inside a work tree this is that repository's status.
    /// Otherwise (a workspace opened on a folder of projects) it merges the status
    /// of each immediate child that is a repository, and marks each changed
    /// repository folder so it stands out in the parent listing.
    func fetchStatusResult(directory: String) -> Result {
        guard let repoRoot = gitRepoRoot(for: directory) else {
            return fetchNestedRepositoriesStatus(directory: directory)
        }
        // git reports the repo root physically (/private/var/...) while the caller may spell
        // the explorer root through a symlink (/var, /tmp, a symlinked project dir). Resolve
        // both to one spelling for the containment check, and emit keys under the caller's
        // spelling so FileExplorerStore lookups match.
        var result = parseGitStatus(
            output: runGit(in: repoRoot, arguments: ["status", "--porcelain=v1", "-z"]),
            repoRoot: Self.canonicalPath(repoRoot),
            explorerRoot: Self.canonicalPath(directory),
            keyRoot: directory
        )
        result.repositoryRoots = [repoRoot]
        return result
    }

    private func fetchNestedRepositoriesStatus(directory: String) -> Result {
        var result = Result()
        for child in Self.childRepositoryDirectories(of: directory, homeDirectory: environment["HOME"]) {
            guard result.repositoryRoots.count < Self.maximumNestedRepositories,
                  let repoRoot = gitRepoRoot(for: child) else { continue }
            let childResult = parseGitStatus(
                output: runGit(in: repoRoot, arguments: ["status", "--porcelain=v1", "-z"]),
                repoRoot: Self.canonicalPath(repoRoot),
                explorerRoot: Self.canonicalPath(child),
                keyRoot: child
            )
            result.repositoryRoots.append(repoRoot)
            result.untrackedDirectories.append(contentsOf: childResult.untrackedDirectories)
            result.statusByPath.merge(childResult.statusByPath) { current, _ in current }
            if !childResult.statusByPath.isEmpty {
                let onlyUntracked = childResult.statusByPath.values.allSatisfy { $0 == .untracked }
                result.statusByPath[child] = onlyUntracked ? .untracked : .modified
            }
        }
        return result
    }

    /// Immediate, non-hidden children of `directory` that hold a `.git` entry
    /// (a directory for a clone, a file for a linked worktree or submodule),
    /// spelled under the caller's `directory`. The home folder and the volume
    /// root are never scanned: they are not project folders, and scanning them
    /// would touch privacy-protected folders such as Desktop and Documents.
    private static func childRepositoryDirectories(of directory: String, homeDirectory: String?) -> [String] {
        let canonicalDirectory = canonicalPath(directory)
        let home = canonicalPath(homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path)
        guard canonicalDirectory != "/", canonicalDirectory != home else { return [] }
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { name -> String? in
                let child = (pathWithoutTrailingSlashes(directory) as NSString).appendingPathComponent(name)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child, isDirectory: &isDirectory), isDirectory.boolValue,
                      fileManager.fileExists(atPath: (child as NSString).appendingPathComponent(".git")) else {
                    return nil
                }
                return child
            }
    }

    func fetchStatusSSH(
        directory: String, destination: String, port: Int?,
        identityFile: String?, sshOptions: [String]
    ) -> [String: GitFileStatus] {
        let escapedDir = directory.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = [
            "cd '\(escapedDir)' 2>/dev/null",
            "\(Self.nonLockingRemoteGitCommand) rev-parse --show-toplevel 2>/dev/null",
            "echo '---GIT_STATUS---'",
            "\(Self.nonLockingRemoteGitCommand) status --porcelain=v1 -z 2>/dev/null",
        ].joined(separator: " && ")
        guard let output = runSSH(
            command: cmd, destination: destination,
            port: port, identityFile: identityFile, sshOptions: sshOptions
        ) else { return [:] }

        let parts = output.components(separatedBy: "---GIT_STATUS---\n")
        guard parts.count == 2 else { return [:] }
        let repoRoot = parts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        // Remote paths must not be resolved against the local filesystem, so the comparison
        // space and the key space are both the caller's spelling here.
        return parseGitStatus(output: parts[1], repoRoot: repoRoot, explorerRoot: directory, keyRoot: directory)
            .statusByPath
    }

    private func parseGitStatus(
        output: String?, repoRoot: String, explorerRoot: String, keyRoot: String
    ) -> Result {
        guard let output, !output.isEmpty else { return Result() }
        var statusMap: [String: GitFileStatus] = [:]
        var untrackedDirectories: [String] = []
        let normalizedRepoRoot = Self.pathWithoutTrailingSlashes(repoRoot)
        let normalizedExplorerRoot = Self.pathWithoutTrailingSlashes(explorerRoot)
        let normalizedKeyRoot = Self.pathWithoutTrailingSlashes(keyRoot)
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)

        var entryIndex = 0
        while entryIndex < entries.count {
            let entry = entries[entryIndex]
            guard entry.count >= 4 else {
                entryIndex += 1
                continue
            }
            let indexStatus = entry[entry.startIndex]
            let workTreeStatus = entry[entry.index(after: entry.startIndex)]
            // An untracked directory arrives whole as "dir/"; drop the slash so the
            // key matches the explorer's node path for that folder.
            let reportedPath = String(entry.dropFirst(3))
            let isDirectoryEntry = reportedPath.hasSuffix("/")
            let path = Self.pathWithoutTrailingSlashes(reportedPath)
            let usesSecondPath = Self.statusUsesSecondPath(index: indexStatus, workTree: workTreeStatus)
            entryIndex += usesSecondPath ? 2 : 1
            guard let status = parseStatusChars(index: indexStatus, workTree: workTreeStatus) else { continue }

            let absolutePath = Self.absolutePath(repoRoot: normalizedRepoRoot, relativePath: path)
            guard Self.path(absolutePath, isContainedIn: normalizedExplorerRoot) else { continue }
            // Re-spell the key under the caller's root. When the two roots already match
            // (the common case) the path is used as-is. The root == "/" branch is reached
            // when the caller's root is a symlink to "/" (the canonical root is "/" while
            // keyRoot is not) and keeps the leading slash that dropFirst would otherwise eat.
            let key: String
            if normalizedKeyRoot == normalizedExplorerRoot {
                key = absolutePath
            } else if normalizedExplorerRoot == "/" {
                key = normalizedKeyRoot + absolutePath
            } else {
                key = normalizedKeyRoot + String(absolutePath.dropFirst(normalizedExplorerRoot.count))
            }

            statusMap[key] = status
            if isDirectoryEntry && status == .untracked {
                untrackedDirectories.append(key)
            }
            markParentDirectories(
                absolutePath: key,
                explorerRoot: normalizedKeyRoot,
                status: status,
                in: &statusMap
            )
        }
        return Result(statusByPath: statusMap, untrackedDirectories: untrackedDirectories)
    }

    private func parseStatusChars(index: Character, workTree: Character) -> GitFileStatus? {
        if index == "?" && workTree == "?" { return .untracked }
        if index == "U" || workTree == "U" { return .modified }
        if index == "T" || workTree == "T" { return .modified }
        if index == "A" || workTree == "A" { return .added }
        if index == "C" || workTree == "C" { return .added }
        if index == "D" || workTree == "D" { return .deleted }
        if index == "R" || workTree == "R" { return .renamed }
        if index == "M" || workTree == "M" { return .modified }
        return nil
    }

    private func markParentDirectories(
        absolutePath: String, explorerRoot: String,
        status: GitFileStatus, in map: inout [String: GitFileStatus]
    ) {
        let dirStatus: GitFileStatus = (status == .untracked) ? .untracked : .modified
        var current = (absolutePath as NSString).deletingLastPathComponent
        while Self.path(current, isContainedIn: explorerRoot) && current != explorerRoot {
            if map[current] == nil {
                map[current] = dirStatus
            }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static func statusUsesSecondPath(index: Character, workTree: Character) -> Bool {
        index == "R" || workTree == "R" || index == "C" || workTree == "C"
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func absolutePath(repoRoot: String, relativePath: String) -> String {
        repoRoot == "/" ? "/" + relativePath : repoRoot + "/" + relativePath
    }

    private static func path(_ path: String, isContainedIn root: String) -> Bool {
        let normalizedPath = pathWithoutTrailingSlashes(path)
        let normalizedRoot = pathWithoutTrailingSlashes(root)
        if normalizedPath == normalizedRoot { return true }
        if normalizedRoot == "/" { return normalizedPath.hasPrefix("/") }
        return normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    private static func pathWithoutTrailingSlashes(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private func gitRepoRoot(for directory: String) -> String? {
        runGit(in: directory, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runGit(in directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = gitExecutableURL
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.environment = nonLockingGitEnvironment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func nonLockingGitEnvironment() -> [String: String] {
        var environment = environment
        environment[Self.nonLockingGitEnvironmentKey] = Self.nonLockingGitEnvironmentValue
        return environment
    }

    private func runSSH(
        command: String, destination: String,
        port: Int?, identityFile: String?, sshOptions: [String]
    ) -> String? {
        let process = Process()
        process.executableURL = sshExecutableURL
        process.arguments = ProcessSSHFileExplorerTransport.sshArguments(
            connection: SSHFileExplorerConnection(
                destination: destination,
                port: port,
                identityFile: identityFile,
                sshOptions: sshOptions
            ),
            command: command
        )
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
