import CryptoKit
import Darwin
import Foundation

/// Reads and writes working-tree files for the diff viewer's editor.
///
/// The file a live diff tab edits is named by the app (the Source Control
/// panel's record of the tab), never by the page. A path is accepted only when
/// it stays inside the repository once symlinks resolve, never touches Git's
/// own directory, and names an existing regular UTF-8 file. A save rewrites the
/// file atomically (keeping its permissions) and only while its bytes still
/// hash to what was last read.
///
/// Methods are nonisolated `async`, so their file and Git work runs off the
/// main actor.
struct DiffEditFileService: Sendable {
    /// Larger files stay read-only in the viewer.
    static let maximumFileBytes = 4 * 1024 * 1024

    private let git: SourceControlGitClient

    init(git: SourceControlGitClient = SourceControlGitClient()) {
        self.git = git
    }

    /// The scope for a page showing `root`'s working tree, or nil when `root`
    /// is not the top level of a Git work tree.
    func scope(forRepositoryRoot root: String) async -> DiffEditScope? {
        guard root.hasPrefix("/"),
              let resolvedRoot = Self.resolved(root),
              let topLevel = await git.repositoryRoot(containing: resolvedRoot),
              Self.resolved(topLevel) == resolvedRoot else { return nil }
        return DiffEditScope(repositoryRoot: resolvedRoot)
    }

    /// The file as a live diff tab shows it now.
    ///
    /// `preferred` keeps the tab on the comparison it shows while that still
    /// applies, otherwise the tab follows the file, preferring the editable
    /// comparison: unstaging moves a staged tab to ``DiffEditView/workingTree``,
    /// staging everything keeps a working-tree tab editable with no differences
    /// left (as VS Code does), and discarding or committing every change leaves
    /// ``DiffEditView/clean``.
    ///
    /// - Parameter originalPath: The source path of a staged rename, so its
    ///   `HEAD` text is the base.
    func load(
        relativePath: String,
        originalPath: String? = nil,
        preferring preferred: DiffEditView,
        in scope: DiffEditScope
    ) async throws -> DiffEditLoadedFile {
        try Self.validate(relativePath)
        if let originalPath {
            try Self.validate(originalPath)
        }
        let changes = try await status(of: relativePath, originalPath: originalPath, in: scope)
        let stagedChange = changes.first { $0.group == .staged }
        let workingTreeChange = changes.first { $0.group != .staged }
        let view: DiffEditView
        if preferred == .staged, stagedChange != nil {
            view = .staged
        } else if workingTreeChange != nil {
            view = .workingTree
        } else if let stagedChange {
            // Fully staged: like VS Code's "(Working Tree)" editor, keep showing
            // the editable file against the index (no differences left), unless
            // the index deletes it.
            view = stagedChange.isDeletion ? .staged : .workingTree
        } else {
            view = .clean
        }

        switch view {
        case .staged:
            let change = stagedChange!
            let base = change.gitStatus == "A"
                ? ""
                : try await objectText("HEAD:\(change.originalPath ?? originalPath ?? relativePath)", in: scope) ?? ""
            let deleted = change.gitStatus == "D"
            let content = deleted ? "" : try await objectText(":\(relativePath)", in: scope) ?? ""
            return DiffEditLoadedFile(view: .staged, base: base, content: content, grant: nil, sha256: nil, deleted: deleted)
        case .workingTree:
            let change = workingTreeChange ?? stagedChange!
            let baseObject: String? = switch change.group {
            case .untracked: nil
            case .conflicts: "HEAD:\(relativePath)"
            case .staged, .unstaged: ":\(relativePath)"
            }
            var base = ""
            if let baseObject {
                base = try await objectText(baseObject, in: scope) ?? ""
            }
            if change.group == .unstaged, change.isDeletion {
                return DiffEditLoadedFile(view: .workingTree, base: base, content: "", grant: nil, sha256: nil, deleted: true)
            }
            let grant = try Self.grant(for: relativePath, in: scope)
            let data = try Self.read(grant)
            guard let content = Self.text(from: data) else { throw DiffEditError.binary }
            return DiffEditLoadedFile(
                view: .workingTree,
                base: base,
                content: content,
                grant: grant,
                sha256: Self.sha256(of: data),
                deleted: false
            )
        case .clean:
            // Nothing left to compare: both sides are the file as it is now,
            // still editable so a new change can start here.
            guard let grant = try? Self.grant(for: relativePath, in: scope) else {
                return DiffEditLoadedFile(view: .clean, base: "", content: "", grant: nil, sha256: nil, deleted: true)
            }
            let data = try Self.read(grant)
            guard let content = Self.text(from: data) else { throw DiffEditError.binary }
            return DiffEditLoadedFile(
                view: .clean,
                base: content,
                content: content,
                grant: grant,
                sha256: Self.sha256(of: data),
                deleted: false
            )
        }
    }

    /// Writes `content` over the granted file; returns the new content's SHA-256.
    ///
    /// - Throws: ``DiffEditError/conflict(currentSHA256:)`` when the file no
    ///   longer hashes to `expectedSHA256`.
    func save(_ content: String, to grant: DiffEditGrant, expectedSHA256: String) async throws -> String {
        // The path must still lead to the file that was validated on open.
        guard Self.resolved(grant.absolutePath) == grant.resolvedPath else { throw DiffEditError.pathRejected }
        let data = Data(content.utf8)
        guard data.count <= Self.maximumFileBytes else { throw DiffEditError.tooLarge }
        let currentSHA256 = Self.sha256(of: try Self.read(grant))
        guard currentSHA256 == expectedSHA256 else {
            throw DiffEditError.conflict(currentSHA256: currentSHA256)
        }
        let fileManager = FileManager.default
        let target = URL(fileURLWithPath: grant.resolvedPath)
        do {
            // A scratch directory on the file's volume, outside the repository,
            // so watchers never see a half-written sibling.
            let scratch = try fileManager.url(
                for: .itemReplacementDirectory,
                in: .userDomainMask,
                appropriateFor: target,
                create: true
            )
            defer { try? fileManager.removeItem(at: scratch) }
            let staged = scratch.appendingPathComponent(target.lastPathComponent, isDirectory: false)
            try data.write(to: staged)
            // Keeps the original's permissions and creation date.
            _ = try fileManager.replaceItemAt(target, withItemAt: staged)
        } catch {
            throw DiffEditError.io(String(
                localized: "diffEdit.error.saveFailed",
                defaultValue: "Could not save the file: \(error.localizedDescription)"
            ))
        }
        return Self.sha256(of: data)
    }

    // MARK: - Validation

    /// A repository-relative path with no `.`, `..`, empty or `.git` components.
    static func validate(_ relativePath: String) throws {
        guard !relativePath.isEmpty,
              relativePath.utf8.count <= 4096,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else { throw DiffEditError.pathRejected }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { isForbiddenComponent($0) }) else { throw DiffEditError.pathRejected }
    }

    static func grant(for relativePath: String, in scope: DiffEditScope) throws -> DiffEditGrant {
        try validate(relativePath)
        let absolutePath = (scope.repositoryRoot as NSString).appendingPathComponent(relativePath)
        guard let resolvedPath = resolved(absolutePath),
              resolvedPath.hasPrefix(scope.repositoryRoot + "/") else { throw DiffEditError.pathRejected }
        // A symlink inside the repository may still point into Git's directory.
        let resolvedComponents = resolvedPath.dropFirst(scope.repositoryRoot.count + 1).split(separator: "/")
        guard !resolvedComponents.contains(where: { isForbiddenComponent($0) }),
              let attributes = try? FileManager.default.attributesOfItem(atPath: resolvedPath),
              attributes[.type] as? FileAttributeType == .typeRegular else { throw DiffEditError.pathRejected }
        return DiffEditGrant(
            repositoryRoot: scope.repositoryRoot,
            relativePath: relativePath,
            absolutePath: absolutePath,
            resolvedPath: resolvedPath
        )
    }

    private static func isForbiddenComponent(_ component: Substring) -> Bool {
        component.isEmpty || component == "." || component == ".." || component.lowercased() == ".git"
    }

    /// The status entries for `relativePath` (and a rename's source).
    private func status(
        of relativePath: String,
        originalPath: String?,
        in scope: DiffEditScope
    ) async throws -> [SourceControlFileChange] {
        var arguments = ["status", "--porcelain=v2", "-z", "--untracked-files=all", "--", ":(literal)\(relativePath)"]
        if let originalPath {
            arguments.append(":(literal)\(originalPath)")
        }
        guard let output = await git.run(arguments, in: scope.repositoryRoot), output.status == 0 else {
            throw DiffEditError.io(String(
                localized: "diffEdit.error.gitFailed",
                defaultValue: "Git could not read the repository status."
            ))
        }
        return SourceControlStatusParser().parseStatus(output.stdout).changes.filter { $0.path == relativePath }
    }

    /// A Git object's text, checked out through the repository's filters so
    /// line endings match the working tree; nil when it does not exist.
    ///
    /// - Throws: ``DiffEditError/binary`` for a binary object.
    private func objectText(_ object: String, in scope: DiffEditScope) async throws -> String? {
        guard let output = await git.run(["cat-file", "--filters", object], in: scope.repositoryRoot),
              output.status == 0 else { return nil }
        guard let text = Self.text(from: output.stdout) else { throw DiffEditError.binary }
        return text
    }

    // MARK: - Files

    private static func read(_ grant: DiffEditGrant) throws -> Data {
        let url = URL(fileURLWithPath: grant.resolvedPath)
        if let size = (try? FileManager.default.attributesOfItem(atPath: grant.resolvedPath))?[.size] as? NSNumber,
           size.intValue > maximumFileBytes {
            throw DiffEditError.tooLarge
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= maximumFileBytes else { throw DiffEditError.tooLarge }
            return data
        } catch let error as DiffEditError {
            throw error
        } catch {
            throw DiffEditError.io(String(
                localized: "diffEdit.error.readFailed",
                defaultValue: "Could not read the file: \(error.localizedDescription)"
            ))
        }
    }

    static func text(from data: Data) -> String? {
        guard !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `realpath(3)`: absolute, symlinks and `.`/`..` resolved; nil when the path does not exist.
    static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }
}
