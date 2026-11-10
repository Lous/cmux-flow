import CmuxCloud
import CmuxCore
import CmuxFoundation
import AppKit
import Combine
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Explorer Visual Style

enum FileExplorerStyle: Int, CaseIterable {
    case liquidGlass = 0
    case highDensity = 1
    case terminalStealth = 2
    case proStudio = 3
    case finder = 4

    var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .highDensity: return "High-Density IDE"
        case .terminalStealth: return "Terminal Stealth"
        case .proStudio: return "Pro Studio"
        case .finder: return "Finder"
        }
    }

    var rowHeight: CGFloat {
        let baseHeight: CGFloat
        switch self {
        case .liquidGlass: baseHeight = 28
        case .highDensity: baseHeight = 20
        case .terminalStealth: baseHeight = 24
        case .proStudio: baseHeight = 32
        case .finder: baseHeight = 26
        }
        return GlobalFontMagnification.scaledSize(baseHeight)
    }

    var indentation: CGFloat {
        switch self {
        case .liquidGlass: return 16
        case .highDensity: return 12
        case .terminalStealth: return 14
        case .proStudio: return 20
        case .finder: return 18
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .liquidGlass: return 16
        case .highDensity: return 14
        case .terminalStealth: return 12
        case .proStudio: return 18
        case .finder: return 18
        }
    }

    var iconWeight: NSFont.Weight {
        switch self {
        case .liquidGlass: return .regular
        case .highDensity: return .regular
        case .terminalStealth: return .light
        case .proStudio: return .regular
        case .finder: return .medium
        }
    }

    var nameFont: NSFont {
        switch self {
        case .liquidGlass: return GlobalFontMagnification.systemFont(ofSize: 13, weight: .medium)
        case .highDensity: return GlobalFontMagnification.systemFont(ofSize: 11, weight: .regular)
        case .terminalStealth: return GlobalFontMagnification.monospacedSystemFont(ofSize: 12, weight: .regular)
        case .proStudio: return GlobalFontMagnification.systemFont(ofSize: 14, weight: .semibold)
        case .finder: return GlobalFontMagnification.systemFont(ofSize: 13, weight: .regular)
        }
    }

    var iconToTextSpacing: CGFloat {
        switch self {
        case .liquidGlass: return 8
        case .highDensity: return 4
        case .terminalStealth: return 6
        case .proStudio: return 12
        case .finder: return 6
        }
    }

    var selectionInset: CGFloat {
        switch self {
        case .liquidGlass: return 8
        case .highDensity: return 0
        case .terminalStealth: return 0
        case .proStudio: return 4
        case .finder: return 4
        }
    }

    var selectionRadius: CGFloat {
        switch self {
        case .liquidGlass: return 6
        case .highDensity: return 0
        case .terminalStealth: return 0
        case .proStudio: return 8
        case .finder: return 5
        }
    }

    var selectionColor: NSColor {
        switch self {
        case .liquidGlass: return .controlAccentColor.withAlphaComponent(0.15)
        case .highDensity: return .selectedContentBackgroundColor
        case .terminalStealth: return .controlAccentColor
        case .proStudio: return .controlAccentColor
        case .finder: return .controlAccentColor.withAlphaComponent(0.15)
        }
    }

    var hoverColor: NSColor {
        switch self {
        case .liquidGlass: return .labelColor.withAlphaComponent(0.05)
        case .highDensity: return .white.withAlphaComponent(0.05)
        case .terminalStealth: return .white.withAlphaComponent(0.03)
        case .proStudio: return .white.withAlphaComponent(0.1)
        case .finder: return .labelColor.withAlphaComponent(0.04)
        }
    }

    var usesBorderSelection: Bool {
        self == .terminalStealth
    }

    var fileIconTint: NSColor {
        palette.fileIconTint
    }

    var folderIconTint: NSColor {
        palette.folderIconTint
    }

    func gitColor(for status: GitFileStatus) -> NSColor {
        palette.gitColor(for: status)
    }

    private var palette: FileExplorerPalette {
        switch self {
        case .liquidGlass: .liquidGlass
        case .highDensity: .highDensity
        case .terminalStealth: .terminalStealth
        case .proStudio: .proStudio
        case .finder: .finder
        }
    }

    static var current: FileExplorerStyle {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "fileExplorer.style") == nil {
            return .highDensity
        }
        return FileExplorerStyle(rawValue: defaults.integer(forKey: "fileExplorer.style")) ?? .highDensity
    }
}

// MARK: - Models

struct FileExplorerEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
}

final class FileExplorerNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileExplorerNode]?
    var isLoading: Bool = false
    var error: String?
    var resourceContextID: UUID?

    init(name: String, path: String, isDirectory: Bool) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    var isExpandable: Bool { isDirectory }

    var sortedChildren: [FileExplorerNode]? {
        children?.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Root Resolver

enum FileExplorerRootResolver {
    static func displayPath(for fullPath: String, homePath: String?) -> String {
        guard let home = homePath, !home.isEmpty else { return fullPath }
        let normalizedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        let normalizedPath = fullPath.hasSuffix("/") ? String(fullPath.dropLast()) : fullPath
        if normalizedPath == normalizedHome {
            return "~"
        }
        let homePrefix = normalizedHome + "/"
        if normalizedPath.hasPrefix(homePrefix) {
            return "~/" + normalizedPath.dropFirst(homePrefix.count)
        }
        return fullPath
    }
}

// MARK: - Provider Protocol

protocol FileExplorerProvider: AnyObject {
    func listDirectory(path: String, showHidden: Bool) async throws -> [FileExplorerEntry]
    func createFile(path: String) async throws
    func createDirectory(path: String) async throws
    func rename(path: String, to destinationPath: String) async throws
    func delete(path: String) async throws
    func copy(path: String, to destinationPath: String) async throws
    func moveToTrash(path: String) async throws
    var homePath: String { get }
    var isAvailable: Bool { get }
    /// Whether removal can go to a recoverable Trash instead of deleting permanently.
    var supportsTrash: Bool { get }
}

extension FileExplorerProvider {
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func createFile(path: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func createDirectory(path: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func rename(path: String, to destinationPath: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func delete(path: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func copy(path: String, to destinationPath: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func moveToTrash(path: String) async throws {
        throw FileExplorerError.mutationFailed
    }

    var supportsTrash: Bool { false }
}

struct SSHFileExplorerConnection: Equatable, Sendable {
    let destination: String
    let port: Int?
    let identityFile: String?
    let sshOptions: [String]
}

protocol SSHFileExplorerTransport: AnyObject {
    nonisolated func resolveHomePath(connection: SSHFileExplorerConnection) async throws -> String
    nonisolated func listDirectory(
        path: String,
        connection: SSHFileExplorerConnection,
        showHidden: Bool
    ) async throws -> [FileExplorerEntry]
    nonisolated func downloadFile(
        path: String,
        connection: SSHFileExplorerConnection,
        to localURL: URL
    ) async throws
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func createFile(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func createDirectory(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func rename(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func delete(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func copy(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws
}

extension SSHFileExplorerTransport {
    nonisolated func createFile(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        throw FileExplorerError.mutationFailed
    }

    nonisolated func createDirectory(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        throw FileExplorerError.mutationFailed
    }

    nonisolated func rename(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        throw FileExplorerError.mutationFailed
    }

    nonisolated func delete(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        throw FileExplorerError.mutationFailed
    }

    nonisolated func copy(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        throw FileExplorerError.mutationFailed
    }
}

enum FileExplorerWorkspaceRoot: Equatable {
    case none
    case local(workspaceId: UUID, path: String)
    case remoteSSH(
        workspaceId: UUID,
        connection: SSHFileExplorerConnection,
        displayTarget: String,
        rootPath: String?,
        isAvailable: Bool,
        unavailableDetail: String?
    )
    case remoteCloud(
        workspaceId: UUID,
        vmID: String,
        displayTarget: String,
        rootPath: String?,
        isAvailable: Bool,
        unavailableDetail: String?,
        target: CloudFileExplorerTarget?
    )
}

// MARK: - Local Provider

final class LocalFileExplorerProvider: FileExplorerProvider {
    var homePath: String { NSHomeDirectory() }
    var isAvailable: Bool { true }
    var supportsTrash: Bool { true }

    private let trashItem: @Sendable (URL) throws -> Void

    /// - Parameter trashItem: Moves one item to the Trash. Tests inject a
    ///   recorder so they never touch the user's real Trash.
    init(
        trashItem: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.trashItem = trashItem
    }

    func listDirectory(path: String, showHidden: Bool) async throws -> [FileExplorerEntry] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: path)
        return contents.compactMap { name in
            guard showHidden || !name.hasPrefix(".") else { return nil }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
            return FileExplorerEntry(name: name, path: fullPath, isDirectory: isDir.boolValue)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func createFile(path: String) async throws {
        // O_EXCL fails on an existing name instead of truncating that file,
        // which FileManager.createFile would do.
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else {
            throw FileExplorerError.mutationError(posixCode: errno)
        }
        close(descriptor)
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func createDirectory(path: String) async throws {
        do {
            try FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: false,
                attributes: nil
            )
        } catch {
            throw FileExplorerError.mutationError(from: error)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func rename(path: String, to destinationPath: String) async throws {
        do {
            if path != destinationPath,
               path.caseInsensitiveCompare(destinationPath) == .orderedSame {
                let parentPath = (path as NSString).deletingLastPathComponent
                let temporaryPath = (parentPath as NSString)
                    .appendingPathComponent(".cmux-rename-\(UUID().uuidString)")
                try FileManager.default.moveItem(atPath: path, toPath: temporaryPath)
                do {
                    try FileManager.default.moveItem(atPath: temporaryPath, toPath: destinationPath)
                } catch {
                    try? FileManager.default.moveItem(atPath: temporaryPath, toPath: path)
                    throw error
                }
                return
            }
            try FileManager.default.moveItem(atPath: path, toPath: destinationPath)
        } catch {
            throw FileExplorerError.mutationError(from: error)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func delete(path: String) async throws {
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            throw FileExplorerError.mutationError(from: error)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func copy(path: String, to destinationPath: String) async throws {
        do {
            // copyItem fails when the destination exists, so a duplicate never
            // replaces another entry.
            try FileManager.default.copyItem(atPath: path, toPath: destinationPath)
        } catch {
            throw FileExplorerError.mutationError(from: error)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    func moveToTrash(path: String) async throws {
        do {
            try trashItem(URL(fileURLWithPath: path))
        } catch {
            throw FileExplorerError.mutationError(from: error)
        }
    }
}

// MARK: - SSH Provider

// Captured by async SSH tasks; mutable availability/root state is guarded by stateLock.
final class SSHFileExplorerProvider: RemoteFileExplorerProvider, @unchecked Sendable {
    private struct State: Sendable {
        var homePath: String
        var isAvailable: Bool
    }

    let connection: SSHFileExplorerConnection
    let displayTarget: String
    private let transport: SSHFileExplorerTransport
    private let stateLock = NSLock()
    private var state: State

    var homePath: String {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.homePath
    }

    var isAvailable: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.isAvailable
    }

    var destination: String { connection.destination }
    nonisolated var remoteIdentity: String {
        "ssh:\(connection.destination)|\(connection.port.map(String.init) ?? "")|\(connection.identityFile ?? "")|\(connection.sshOptions.joined(separator: "\u{1f}"))"
    }
    var port: Int? { connection.port }
    var identityFile: String? { connection.identityFile }
    var sshOptions: [String] { connection.sshOptions }

    init(
        destination: String,
        port: Int?,
        identityFile: String?,
        sshOptions: [String],
        displayTarget: String? = nil,
        homePath: String,
        isAvailable: Bool,
        transport: SSHFileExplorerTransport = ProcessSSHFileExplorerTransport.shared
    ) {
        self.connection = SSHFileExplorerConnection(
            destination: destination,
            port: port,
            identityFile: identityFile,
            sshOptions: sshOptions
        )
        self.displayTarget = displayTarget ?? {
            guard let port else { return destination }
            return "\(destination):\(port)"
        }()
        self.transport = transport
        self.state = State(homePath: homePath, isAvailable: isAvailable)
    }

    init(
        connection: SSHFileExplorerConnection,
        displayTarget: String,
        homePath: String,
        isAvailable: Bool,
        transport: SSHFileExplorerTransport = ProcessSSHFileExplorerTransport.shared
    ) {
        self.connection = connection
        self.displayTarget = displayTarget
        self.transport = transport
        self.state = State(homePath: homePath, isAvailable: isAvailable)
    }

    func updateAvailability(_ available: Bool, homePath: String?) {
        stateLock.lock()
        defer { stateLock.unlock() }
        state.isAvailable = available
        if let homePath {
            state.homePath = homePath
        }
    }

    func resolveHomePath() async throws -> String {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        let home = try await transport.resolveHomePath(connection: connection)
        guard !home.isEmpty else {
            throw FileExplorerError.sshCommandFailed("remote HOME was empty")
        }
        return home
    }

    func listDirectory(path: String, showHidden: Bool) async throws -> [FileExplorerEntry] {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        return try await transport.listDirectory(path: path, connection: connection, showHidden: showHidden)
    }

    func downloadFile(path: String, to localURL: URL) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.downloadFile(path: path, connection: connection, to: localURL)
    }

    func createFile(path: String) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.createFile(path: path, connection: connection)
    }

    func createDirectory(path: String) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.createDirectory(path: path, connection: connection)
    }

    func rename(path: String, to destinationPath: String) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.rename(path: path, to: destinationPath, connection: connection)
    }

    func delete(path: String) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.delete(path: path, connection: connection)
    }

    func copy(path: String, to destinationPath: String) async throws {
        guard isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        try await transport.copy(path: path, to: destinationPath, connection: connection)
    }
}

final class ProcessSSHFileExplorerTransport: SSHFileExplorerTransport {
    static let shared = ProcessSSHFileExplorerTransport()

    nonisolated func resolveHomePath(connection: SSHFileExplorerConnection) async throws -> String {
        let output = try await Self.runSSHCommand(
            connection: connection,
            command: #"printf '%s\n' "$HOME""#
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func listDirectory(
        path: String,
        connection: SSHFileExplorerConnection,
        showHidden: Bool
    ) async throws -> [FileExplorerEntry] {
        try await Self.runSSHListCommand(path: path, connection: connection, showHidden: showHidden)
    }

    nonisolated func downloadFile(
        path: String,
        connection: SSHFileExplorerConnection,
        to localURL: URL
    ) async throws {
        let escapedPath = Self.remoteShellPathWord(path)
        let outputURL = localURL
        let commandProcess = SSHDownloadCommandProcess(
            connection: connection,
            command: "test -f \(escapedPath) && cat -- \(escapedPath)",
            outputURL: outputURL
        )
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try commandProcess.run() })
                }
            }
        } onCancel: {
            commandProcess.terminate()
        }
        guard result.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            throw FileExplorerError.sshCommandFailed(result.stderr)
        }
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func createFile(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        try await Self.runSSHMutationCommand(.createFile(path: path), connection: connection)
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func createDirectory(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        try await Self.runSSHMutationCommand(.createDirectory(path: path), connection: connection)
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func rename(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        try await Self.runSSHMutationCommand(
            .rename(path: path, to: destinationPath),
            connection: connection
        )
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func delete(
        path: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        try await Self.runSSHMutationCommand(.delete(path: path), connection: connection)
    }

    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    nonisolated func copy(
        path: String,
        to destinationPath: String,
        connection: SSHFileExplorerConnection
    ) async throws {
        try await Self.runSSHMutationCommand(
            .copy(path: path, to: destinationPath),
            connection: connection
        )
    }

    private struct SSHCommandResult: Sendable {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
    }

    // Keeps the child process reachable from the cancellation handler while
    // the blocking wait runs off Swift's cooperative executor.
    private final class SSHCommandProcess: @unchecked Sendable {
        private let process = Process()
        private let outPipe = Pipe()
        private let errPipe = Pipe()
        private let lock = NSLock()
        private var terminationGate = ProcessTerminationGate()
        private var cancelled = false

        init(connection: SSHFileExplorerConnection, command: String) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ProcessSSHFileExplorerTransport.sshArguments(connection: connection, command: command)
            process.standardOutput = outPipe
            process.standardError = errPipe
        }

        func run() throws -> SSHCommandResult {
            lock.lock()
            let wasCancelled = cancelled
            lock.unlock()
            if wasCancelled {
                throw CancellationError()
            }

            do {
                try process.run()
            } catch {
                lock.lock()
                terminationGate.markFinished()
                lock.unlock()
                throw error
            }

            lock.lock()
            let shouldTerminate = cancelled
            let shouldTerminateDeferredRequest = terminationGate.markLaunched()
            lock.unlock()
            if shouldTerminateDeferredRequest || shouldTerminate {
                guard process.isRunning else {
                    process.waitUntilExit()
                    lock.lock()
                    terminationGate.markFinished()
                    lock.unlock()
                    throw CancellationError()
                }
                process.terminate()
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            let stderrData = errPipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            lock.lock()
            terminationGate.markFinished()
            let cancelledAfterExit = cancelled
            lock.unlock()
            if cancelledAfterExit {
                throw CancellationError()
            }

            return SSHCommandResult(
                stdout: String(data: data, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                terminationStatus: process.terminationStatus
            )
        }

        func terminate() {
            lock.lock()
            cancelled = true
            let shouldTerminate = terminationGate.requestTermination()
            lock.unlock()

            guard shouldTerminate else {
                return
            }
            guard process.isRunning else {
                return
            }
            process.terminate()
        }
    }

    private final class SSHDownloadCommandProcess: @unchecked Sendable {
        private let process = Process()
        private let outPipe = Pipe()
        private let errPipe = Pipe()
        private let outputURL: URL
        private let lock = NSLock()
        private var terminationGate = ProcessTerminationGate()
        private var cancelled = false

        init(connection: SSHFileExplorerConnection, command: String, outputURL: URL) {
            self.outputURL = outputURL
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ProcessSSHFileExplorerTransport.sshArguments(connection: connection, command: command)
            process.standardOutput = outPipe
            process.standardError = errPipe
        }

        func run() throws -> SSHCommandResult {
            lock.lock()
            let wasCancelled = cancelled
            lock.unlock()
            if wasCancelled {
                throw CancellationError()
            }

            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            defer { try? outputHandle.close() }

            do {
                try process.run()
            } catch {
                lock.lock()
                terminationGate.markFinished()
                lock.unlock()
                throw error
            }

            lock.lock()
            let shouldTerminate = cancelled
            let shouldTerminateDeferredRequest = terminationGate.markLaunched()
            lock.unlock()
            if shouldTerminateDeferredRequest || shouldTerminate {
                guard process.isRunning else {
                    process.waitUntilExit()
                    lock.lock()
                    terminationGate.markFinished()
                    lock.unlock()
                    throw CancellationError()
                }
                process.terminate()
            }

            try outPipe.fileHandleForReading.copyDataToEndOfFile(to: outputHandle)
            let stderrData = errPipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            lock.lock()
            terminationGate.markFinished()
            let cancelledAfterExit = cancelled
            lock.unlock()
            if cancelledAfterExit {
                throw CancellationError()
            }

            return SSHCommandResult(
                stdout: "",
                stderr: String(data: stderrData, encoding: .utf8) ?? "",
                terminationStatus: process.terminationStatus
            )
        }

        func terminate() {
            lock.lock()
            cancelled = true
            let shouldTerminate = terminationGate.requestTermination()
            lock.unlock()

            guard shouldTerminate else {
                return
            }
            guard process.isRunning else {
                return
            }
            process.terminate()
        }
    }

    private static func runSSHCommand(connection: SSHFileExplorerConnection, command: String) async throws -> String {
        let result = try await runSSHProcess(connection: connection, command: command)
        guard result.terminationStatus == 0 else {
            throw FileExplorerError.sshCommandFailed(result.stderr)
        }
        return result.stdout
    }

    private static func runSSHProcess(
        connection: SSHFileExplorerConnection,
        command: String
    ) async throws -> SSHCommandResult {
        let commandProcess = SSHCommandProcess(connection: connection, command: command)
        let result = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try commandProcess.run() })
                }
            }
        } onCancel: {
            commandProcess.terminate()
        }
        return result
    }

    private static func runSSHMutationCommand(
        _ mutation: SSHFileExplorerMutationCommand,
        connection: SSHFileExplorerConnection
    ) async throws {
        let result = try await runSSHProcess(connection: connection, command: mutation.command)
        switch result.terminationStatus {
        case 0:
            return
        case 255:
            // ssh itself failed (connection, auth); keep its diagnostics.
            throw FileExplorerError.sshCommandFailed(result.stderr)
        default:
            throw FileExplorerError.mutationError(exitStatus: result.terminationStatus)
        }
    }

    // Probes reuse the workspace's master through its ControlPath and must
    // never become one, like cmux's other background ssh runs.
    static func sshArguments(connection: SSHFileExplorerConnection, command: String) -> [String] {
        WorkspaceRemoteConfiguration(
            destination: connection.destination,
            port: connection.port,
            identityFile: connection.identityFile,
            sshOptions: connection.sshOptions,
            localProxyPort: nil,
            relayPort: nil,
            relayID: nil,
            relayToken: nil,
            localSocketPath: nil,
            terminalStartupCommand: nil
        ).batchSSHCommandArguments(command: command, effectiveSSHOptions: connection.sshOptions)
    }

    private static func runSSHListCommand(
        path: String,
        connection: SSHFileExplorerConnection,
        showHidden: Bool
    ) async throws -> [FileExplorerEntry] {
        let escapedPath = remoteShellPathWord(path)
        let lsFlags = showHidden ? "-1paFA" : "-1paF"
        let output = try await runSSHCommand(
            connection: connection,
            command: "ls \(lsFlags) \(escapedPath) 2>/dev/null"
        )

        let normalizedPath = path.hasSuffix("/") ? path : path + "/"
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let entry = String(line)
            // Skip . and .. entries
            guard entry != "./" && entry != "../" else { return nil }
            let isDir = entry.hasSuffix("/")
            let name = isDir ? String(entry.dropLast()) : entry
            guard showHidden || !name.hasPrefix(".") else { return nil }
            // Strip type indicators from -F flag (*, @, =, |) for files
            let cleanName: String
            if !isDir, let last = name.last, "*@=|".contains(last) {
                cleanName = String(name.dropLast())
            } else {
                cleanName = name
            }
            let fullPath = normalizedPath + cleanName
            return FileExplorerEntry(name: cleanName, path: fullPath, isDirectory: isDir)
        }
    }

    /// Shell word that expands to `path` on the remote host, byte for byte.
    ///
    /// `Process` passes arguments through `fileSystemRepresentation`, which
    /// decomposes them to NFD. Remote Linux filesystems usually store names in
    /// NFC and treat the two forms as different files, so a non-ASCII path must
    /// not appear literally in the ssh command. Such paths travel base64-encoded
    /// and are decoded by the remote shell.
    static func remoteShellPathWord(_ path: String) -> String {
        guard !path.unicodeScalars.allSatisfy(\.isASCII) else {
            return shellSingleQuote(path)
        }
        let encoded = shellSingleQuote(Data(path.utf8).base64EncodedString())
        // GNU coreutils and macOS accept --decode, BusyBox (Alpine) only -d;
        // -D is the older macOS short flag.
        let decode = ["--decode", "-d", "-D"]
            .map { "printf '%s' \(encoded) | base64 \($0) 2>/dev/null" }
            .joined(separator: " || ")
        return "\"$(\(decode))\""
    }

    private static func shellSingleQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

enum FileExplorerError: LocalizedError, Equatable {
    case providerUnavailable
    case sshCommandFailed(String)
    case remoteCommandFailed(String)
    case mutationFailed
    case invalidMutationName
    /// A create, rename or duplicate target name is already taken.
    case mutationTargetExists
    /// The containing folder is not writable.
    case mutationPermissionDenied
    case previewCapacity
    case remoteFileTooLarge

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return String(localized: "fileExplorer.error.unavailable", defaultValue: "File explorer is not available")
        case .sshCommandFailed:
            return String(localized: "fileExplorer.error.sshFailed", defaultValue: "SSH command failed")
        case .previewCapacity:
            return String(localized: "fileExplorer.preview.capacity", defaultValue: "Close a Cloud file preview and try again.")
        case .remoteFileTooLarge:
            return String(localized: "fileExplorer.error.cloudPreviewTooLarge", defaultValue: "Cloud file previews are limited to 1 MB.")
        case .remoteCommandFailed:
            return String(localized: "fileExplorer.error.remoteFailed", defaultValue: "Remote command failed")
        case .mutationFailed:
            return String(localized: "fileExplorer.error.mutationFailed", defaultValue: "Unable to update this file or folder.")
        case .invalidMutationName:
            return String(localized: "fileExplorer.error.invalidName", defaultValue: "Enter a single file or folder name.")
        case .mutationTargetExists:
            return String(localized: "fileExplorer.error.alreadyExists", defaultValue: "An item with that name already exists.")
        case .mutationPermissionDenied:
            return String(localized: "fileExplorer.error.permissionDenied", defaultValue: "You don't have permission to change this folder.")
        }
    }
}

enum FileExplorerEntryKind: Equatable, Sendable {
    case file
    case directory
}

// MARK: - Selection Restoration

enum FileExplorerSelectionRestoration {
    static func scrollRow(anchorRow: Int?, exactRows: IndexSet) -> Int? {
        if let anchorRow, exactRows.contains(anchorRow) {
            return anchorRow
        }
        return exactRows.first
    }
}

// MARK: - Store

/// Main-actor store for file-explorer presentation and loading state.
@MainActor
final class FileExplorerStore: ObservableObject {
    @Published var rootPath: String = ""
    @Published var rootNodes: [FileExplorerNode] = []
    @Published private(set) var isRootLoading: Bool = false
    /// Not @Published: a git-only change repaints visible rows through
    /// ``observeGitDecorations(owner:_:)`` instead of reloading the outline.
    private(set) var gitStatusByPath: [String: GitFileStatus] = [:]
    /// Directories Git reported as wholly untracked; their contents are untracked too.
    private(set) var gitUntrackedDirectories: [String] = []
    /// Bumped whenever git decorations change, so the outline repaints visible
    /// rows' decorations only then and never during ordinary navigation.
    private(set) var gitDecorationRevision = 0
    private var gitDecorationObservers: [GitDecorationObserver] = []

    /// A view that repaints rows when git decorations change.
    private struct GitDecorationObserver {
        weak var owner: AnyObject?
        let handler: @MainActor () -> Void
    }

    /// Calls `handler` after git decorations change. Held only while `owner` lives;
    /// registering again for the same owner replaces its handler.
    func observeGitDecorations(owner: AnyObject, _ handler: @escaping @MainActor () -> Void) {
        gitDecorationObservers.removeAll { $0.owner == nil || $0.owner === owner }
        gitDecorationObservers.append(GitDecorationObserver(owner: owner, handler: handler))
    }

    private func notifyGitDecorationObservers() {
        gitDecorationObservers.removeAll { $0.owner == nil }
        for observer in gitDecorationObservers {
            observer.handler()
        }
    }
    /// Re-reads git status when files change anywhere inside the root's repositories.
    private let gitStatusWatcher = FileExplorerGitStatusWatcher()
    @Published private(set) var contentRevision = 0
    @Published private(set) var rootStatusMessage: String?
    private(set) var workspaceRootIdentity: UUID?

    var provider: FileExplorerProvider?

    /// Whether hidden files are shown. Set from FileExplorerState externally.
    var showHiddenFiles: Bool = false

    /// Watches the whole tree for entries appearing or disappearing (local only).
    private var directoryWatcher: RecursivePathWatcher?
    private var directoryWatchTask: Task<Void, Never>?
    private var directoryWatchPath: String?
    /// In-flight in-place re-listings of loaded folders, keyed by path.
    private var folderRefreshTasks: [String: Task<Void, Never>] = [:]

    /// Paths that are logically expanded (persisted across provider changes)
    private(set) var expandedPaths: Set<String> = []

    /// Stable navigation selection. The outline view mirrors this path after reloads.
    private(set) var selectedPath: String?

    /// Stable multi-selection. `selectedPath` remains the keyboard/navigation anchor.
    private(set) var selectedPaths: Set<String> = []

    /// Folder path whose first child should be selected once its async load completes.
    private var pendingDescendIntoFirstChildPath: String?

    /// Paths currently being loaded
    private(set) var loadingPaths: Set<String> = []

    /// In-flight load tasks keyed by path
    private var loadTasks: [String: Task<Void, Never>] = [:]

    /// Cache of path -> node for quick lookup
    private var nodesByPath: [String: FileExplorerNode] = [:]

    /// Prefetch debounce schedulers keyed by path.
    private var prefetchSchedulers: [String: MainActorDeferredActionScheduler] = [:]

    /// In-flight in-place root refresh (see ``refreshRootInPlace()``).
    private var rootRefreshTask: Task<Void, Never>?
    /// Set by ``reveal(path:)`` so the outline scrolls the revealed row into view once.
    private var revealScrollRequested = false

    var workspaceRootObservation: FileExplorerWorkspaceObservation?
    var remoteHomeResolutionTask: Task<Void, Never>?
    var remoteHomeResolutionKey: String?
    let cloudPreviewCache = CloudFilePreviewCache()
    private(set) var resourceContextID = UUID()

    private let gitStatusProvider: GitStatusProvider
    private var gitStatusGeneration: UInt64 = 0

    /// What `fileExplorer.exclude` hides, like VS Code's `files.exclude`.
    private(set) var excludeFilter: FileExplorerExcludeFilter
    private var excludeObservation: Task<Void, Never>?

    init(
        gitStatusProvider: GitStatusProvider = GitStatusProvider(),
        excludeSettings: FileExplorerExcludeSettings = FileExplorerExcludeSettings(defaults: .standard)
    ) {
        self.gitStatusProvider = gitStatusProvider
        excludeFilter = excludeSettings.filter()
        excludeObservation = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: FileExplorerExcludeSettings.didChangeNotification) {
                self?.applyExcludeFilter(excludeSettings.filter())
            }
        }
    }

    /// Shows the tree again under a new `fileExplorer.exclude`; expanded folders stay expanded.
    func applyExcludeFilter(_ filter: FileExplorerExcludeFilter) {
        guard filter != excludeFilter else { return }
        excludeFilter = filter
        reload()
    }

    var displayRootPath: String {
        if rootPath.isEmpty, let cloudProvider = provider as? CloudVMFileExplorerProvider {
            return cloudProvider.displayTarget
        }
        if let sshProvider = provider as? SSHFileExplorerProvider {
            guard !rootPath.isEmpty else {
                return "ssh://\(sshProvider.displayTarget)"
            }
            return "ssh://\(sshProvider.displayTarget):\(rootPath)"
        }
        return FileExplorerRootResolver.displayPath(for: rootPath, homePath: provider?.homePath)
    }

    // MARK: - Public API

    func applyWorkspaceRoot(
        _ request: FileExplorerWorkspaceRoot,
        sshTransport: SSHFileExplorerTransport = ProcessSSHFileExplorerTransport.shared
    ) {
        switch request {
        case .none:
            workspaceRootObservation?.stop(); workspaceRootObservation = nil
            cancelRemoteHomeResolution(); setRootStatusMessage(nil); setWorkspaceRootIdentity(nil)
            if provider != nil { setProvider(nil, reloadIfAvailable: false) }
            setRootPath("")
        case .local(let workspaceId, let path):
            cancelRemoteHomeResolution(); setRootStatusMessage(nil); setWorkspaceRootIdentity(workspaceId)
            if !(provider is LocalFileExplorerProvider) {
                setRootPath("")
                setProvider(LocalFileExplorerProvider(), reloadIfAvailable: false)
            }
            setRootPath(path)
        case .remoteSSH(let workspaceId, let connection, let displayTarget, let rootPath, let isAvailable, let unavailableDetail):
            applyRemoteSSHWorkspaceRoot(
                workspaceId: workspaceId,
                connection: connection,
                displayTarget: displayTarget,
                rootPath: rootPath,
                isAvailable: isAvailable,
                unavailableDetail: unavailableDetail,
                sshTransport: sshTransport
            )
        case .remoteCloud(let workspaceId, let vmID, let displayTarget, let rootPath, let isAvailable, let unavailableDetail, let target):
            applyRemoteCloudWorkspaceRoot(
                workspaceId: workspaceId,
                vmID: vmID,
                displayTarget: displayTarget,
                rootPath: rootPath,
                isAvailable: isAvailable,
                unavailableDetail: unavailableDetail, target: target
            )
        }
    }
    func setWorkspaceRootIdentity(_ identity: UUID?) {
        guard workspaceRootIdentity != identity else { return }
        workspaceRootIdentity = identity
        resetResourceContext()
        rootPath = ""
        updateDirectoryWatcher()
    }

    func setRootStatusMessage(_ message: String?) {
        guard rootStatusMessage != message else { return }
        rootStatusMessage = message
    }

    private func resetResourceContext(preservingNavigation: Bool = false) {
        resourceContextID = UUID()
        cancelRemoteHomeResolution()
        cancelAllLoads()
        if !preservingNavigation {
            selectedPath = nil; selectedPaths = []; expandedPaths = []
        }
        rootNodes = []; nodesByPath = [:]; gitUntrackedDirectories = []; gitStatusByPath = [:]
        gitDecorationRevision &+= 1
        contentRevision &+= 1
    }

    /// Git decoration for an explorer path, including files inside an untracked folder.
    func gitStatus(forPath path: String) -> GitFileStatus? {
        if let status = gitStatusByPath[path] {
            return status
        }
        for directory in gitUntrackedDirectories where path.hasPrefix(directory + "/") {
            return .untracked
        }
        return nil
    }

    func setRootPath(_ path: String) {
        guard path != rootPath else {
            #if DEBUG
            NSLog("[FileExplorer] setRootPath skipped (same path): \(path)")
            #endif
            return
        }
        #if DEBUG
        NSLog("[FileExplorer] setRootPath: \(rootPath) -> \(path)")
        #endif
        if let selectedPath, !Self.path(selectedPath, isContainedIn: path) {
            self.selectedPath = nil
            selectedPaths = []
            pendingDescendIntoFirstChildPath = nil
        }
        resourceContextID = UUID()
        rootPath = path
        reload()
        refreshGitStatus()
        updateDirectoryWatcher()
    }

    func refreshGitStatus() {
        gitStatusGeneration &+= 1
        let generation = gitStatusGeneration, path = rootPath
        let context = resourceContextID, source = gitStatusProvider
        guard !path.isEmpty, provider?.isAvailable == true,
              provider is LocalFileExplorerProvider || provider is SSHFileExplorerProvider else {
            gitStatusWatcher.stop()
            let hadDecorations = !gitStatusByPath.isEmpty || !gitUntrackedDirectories.isEmpty
            gitUntrackedDirectories = []
            gitStatusByPath = [:]
            if hadDecorations {
                gitDecorationRevision &+= 1
                notifyGitDecorationObservers()
            }
            return
        }
        let connection = (provider as? SSHFileExplorerProvider)?.connection
        if connection != nil {
            gitStatusWatcher.stop()
        }
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                if let connection {
                    return GitStatusProvider.Result(statusByPath: source.fetchStatusSSH(directory: path,
                        destination: connection.destination, port: connection.port,
                        identityFile: connection.identityFile, sshOptions: connection.sshOptions))
                }
                return source.fetchStatusResult(directory: path)
            }.value
            guard let self, self.gitStatusGeneration == generation, self.resourceContextID == context else { return }
            // Set before the published map so the outline reload sees both, and skip
            // identical results so watcher-driven refreshes do not reload the outline.
            if self.gitUntrackedDirectories != result.untrackedDirectories
                || self.gitStatusByPath != result.statusByPath {
                self.gitUntrackedDirectories = result.untrackedDirectories
                self.gitStatusByPath = result.statusByPath
                self.gitDecorationRevision &+= 1
                self.notifyGitDecorationObservers()
            }
            if connection == nil {
                self.gitStatusWatcher.watch(repositoryRoots: result.repositoryRoots) { [weak self] in
                    self?.refreshGitStatus()
                }
            }
        }
    }

    func materializeRemoteFileForPreview(
        path: String,
        expectedWorkspaceRootIdentity: UUID? = nil
    ) async throws -> URL {
        // `DisableFileTransfer` (MDM): a preview copies the file off the remote
        // host onto this Mac, which is a cmux-mediated download.
        guard !ManagedFileTransferPolicy.isDisabled else {
            throw ManagedFileTransferPolicy.refusalError()
        }
        guard expectedWorkspaceRootIdentity == nil || workspaceRootIdentity == expectedWorkspaceRootIdentity,
              let remoteProvider = provider as? SSHFileExplorerProvider else {
            throw FileExplorerError.providerUnavailable
        }
        let cacheURL = Self.remotePreviewCacheURL(
            displayTarget: remoteProvider.displayTarget,
            remotePath: path
        )
        try await remoteProvider.downloadFile(path: path, to: cacheURL)
        guard expectedWorkspaceRootIdentity == nil ||
              (workspaceRootIdentity == expectedWorkspaceRootIdentity && provider === remoteProvider) else {
            try? FileManager.default.removeItem(at: cacheURL)
            throw FileExplorerError.providerUnavailable
        }
        return cacheURL
    }

    func createEntry(
        kind: FileExplorerEntryKind,
        in directoryPath: String,
        named name: String
    ) async throws -> String {
        guard Self.path(directoryPath, isContainedIn: rootPath) else {
            throw FileExplorerError.mutationFailed
        }
        let path = try Self.childPath(directoryPath: directoryPath, name: name)
        guard let provider, provider.isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        let context = resourceContextID
        switch kind {
        case .file:
            try await provider.createFile(path: path)
        case .directory:
            try await provider.createDirectory(path: path)
        }
        guard self.provider === provider, resourceContextID == context else {
            throw FileExplorerError.providerUnavailable
        }
        selectedPath = path
        selectedPaths = [path]
        reload()
        refreshGitStatus()
        return path
    }

    func renameEntry(path: String, toName name: String) async throws -> String {
        guard Self.path(path, isContainedIn: rootPath), !Self.pathsEqual(path, rootPath) else {
            throw FileExplorerError.mutationFailed
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        let destinationPath = try Self.childPath(directoryPath: parentPath, name: name)
        guard let provider, provider.isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        if path == destinationPath {
            return path
        }
        let context = resourceContextID
        try await provider.rename(path: path, to: destinationPath)
        guard self.provider === provider, resourceContextID == context else {
            throw FileExplorerError.providerUnavailable
        }
        if selectedPaths.contains(path) {
            selectedPaths.remove(path)
            selectedPaths.insert(destinationPath)
        }
        if selectedPath == path {
            selectedPath = destinationPath
        }
        expandedPaths = Set(expandedPaths.map { Self.replacingPathPrefix($0, old: path, new: destinationPath) })
        selectedPaths = Set(selectedPaths.map { Self.replacingPathPrefix($0, old: path, new: destinationPath) })
        reload()
        refreshGitStatus()
        return destinationPath
    }

    /// Whether ``removeEntries(paths:)`` moves items to the Trash (recoverable)
    /// instead of deleting them permanently.
    var removesToTrash: Bool { provider?.supportsTrash == true }

    /// Copies an entry next to itself as "name copy", "name copy 2", … and
    /// selects the copy.
    func duplicateEntry(path: String) async throws -> String {
        guard Self.path(path, isContainedIn: rootPath), !Self.pathsEqual(path, rootPath) else {
            throw FileExplorerError.mutationFailed
        }
        guard let provider, provider.isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        let parentPath = (path as NSString).deletingLastPathComponent
        let context = resourceContextID
        let siblings = try await provider.listDirectory(path: parentPath, showHidden: true)
        guard self.provider === provider, resourceContextID == context else {
            throw FileExplorerError.providerUnavailable
        }
        let name = (path as NSString).lastPathComponent
        let isDirectory = siblings.first { $0.name == name }?.isDirectory ?? false
        let copyName = Self.duplicateName(
            for: name,
            isDirectory: isDirectory,
            existingNames: Set(siblings.map(\.name))
        )
        let destinationPath = (parentPath as NSString).appendingPathComponent(copyName)
        try await provider.copy(path: path, to: destinationPath)
        guard self.provider === provider, resourceContextID == context else {
            throw FileExplorerError.providerUnavailable
        }
        selectedPath = destinationPath
        selectedPaths = [destinationPath]
        reload()
        refreshGitStatus()
        return destinationPath
    }

    /// Removes entries, moving them to the Trash when the provider supports it
    /// (local roots) and deleting them permanently otherwise (SSH and Cloud).
    func removeEntries(paths: [String]) async throws {
        guard !paths.isEmpty,
              paths.allSatisfy({ Self.path($0, isContainedIn: rootPath) && !Self.pathsEqual($0, rootPath) }) else {
            throw FileExplorerError.mutationFailed
        }
        guard let provider, provider.isAvailable else {
            throw FileExplorerError.providerUnavailable
        }
        let uniquePaths = Set(paths)
        // Removing an ancestor already removes its descendants.
        let topLevelPaths = uniquePaths.filter { path in
            !Self.pathHasAncestor(path, in: uniquePaths)
        }
        let useTrash = provider.supportsTrash
        let context = resourceContextID
        var removedPaths: Set<String> = []
        do {
            for path in topLevelPaths.sorted() {
                if useTrash {
                    try await provider.moveToTrash(path: path)
                } else {
                    try await provider.delete(path: path)
                }
                removedPaths.insert(path)
            }
        } catch {
            // Earlier items may already be gone; drop their state before
            // surfacing the failure.
            if self.provider === provider, resourceContextID == context {
                clearState(forRemovedPaths: removedPaths)
            } else {
                reload()
            }
            throw error
        }
        guard self.provider === provider, resourceContextID == context else {
            throw FileExplorerError.providerUnavailable
        }
        clearState(forRemovedPaths: removedPaths)
        refreshGitStatus()
    }

    /// Drops selection and expansion state under removed paths, then reloads.
    private func clearState(forRemovedPaths removedPaths: Set<String>) {
        selectedPaths = selectedPaths.filter { selected in
            !Self.pathIsContained(selected, inAnyOf: removedPaths)
        }
        if let selectedPath,
           Self.pathIsContained(selectedPath, inAnyOf: removedPaths) {
            self.selectedPath = nil
        }
        expandedPaths = expandedPaths.filter { expanded in
            !Self.pathIsContained(expanded, inAnyOf: removedPaths)
        }
        reload()
    }

    /// Finder-style duplicate name: "notes copy.txt", then "notes copy 2.txt".
    /// Directories and dotfiles keep their whole name as the stem.
    static func duplicateName(for name: String, isDirectory: Bool, existingNames: Set<String>) -> String {
        let pathExtension = isDirectory ? "" : (name as NSString).pathExtension
        let stem = pathExtension.isEmpty ? name : (name as NSString).deletingPathExtension
        let copyFormat = String(localized: "fileExplorer.duplicate.copyName", defaultValue: "%@ copy")
        let copyStem = String.localizedStringWithFormat(copyFormat, stem)
        var index = 1
        while true {
            let candidateStem = index == 1 ? copyStem : "\(copyStem) \(index)"
            let candidate = pathExtension.isEmpty ? candidateStem : "\(candidateStem).\(pathExtension)"
            if !existingNames.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

    private func updateDirectoryWatcher() {
        if provider is LocalFileExplorerProvider, !rootPath.isEmpty {
            guard directoryWatchPath != rootPath || directoryWatchTask == nil else { return }
            stopDirectoryWatcher()
            let path = rootPath
            directoryWatchPath = path
            // Recursive, like VS Code's explorer: a file a terminal or agent writes
            // in an expanded folder shows up as one written in the root does.
            directoryWatchTask = Task { @MainActor [weak self] in
                let resolvedPath = FileExplorerChangedFolders.resolvedPath(path)
                guard let watcher = await RecursivePathWatcher(
                    paths: [resolvedPath],
                    throttleInterval: .milliseconds(300),
                    eventFilter: { FileExplorerChangedFolders.isListingChange($0.paths) }
                ) else { return }
                guard !Task.isCancelled, self?.adoptDirectoryWatcher(watcher, for: path) == true else {
                    await watcher.stop()
                    return
                }
                for await change in watcher.pathEvents {
                    guard let self, self.directoryWatchPath == path else { break }
                    self.handleDirectoryChange(change, resolvedRootPath: resolvedPath)
                }
            }
        } else {
            stopDirectoryWatcher()
        }
    }

    private func adoptDirectoryWatcher(_ watcher: RecursivePathWatcher, for path: String) -> Bool {
        guard directoryWatchPath == path else { return false }
        directoryWatcher = watcher
        return true
    }

    /// Re-lists, in place, the shown folders a change touched: the root and any
    /// folder whose children are loaded. Folders never listed are read fresh when
    /// expanded, so their changes are skipped. Nothing is reloaded: a full reload
    /// empties the tree and shows the loading state, which flashed on every file a
    /// terminal or agent created.
    private func handleDirectoryChange(_ change: RecursivePathChange, resolvedRootPath: String) {
        let root = rootPath
        let folders: Set<String>
        if change.requiresFullRescan {
            folders = Set(nodesByPath.values.filter { $0.isDirectory && $0.children != nil }.map(\.path)).union([root])
        } else {
            folders = FileExplorerChangedFolders(
                eventPaths: change.paths,
                rootPath: root,
                resolvedRootPath: resolvedRootPath
            ).folders
        }
        for folder in folders {
            if Self.pathsEqual(folder, root) {
                refreshRootInPlace()
                refreshGitStatus()
            } else if let node = nodesByPath[folder], node.isDirectory, node.children != nil {
                refreshChildrenInPlace(of: node)
            }
        }
    }

    /// Re-lists a loaded folder and merges the listing into its children, the
    /// way ``refreshRootInPlace()`` does for the root.
    private func refreshChildrenInPlace(of node: FileExplorerNode) {
        guard let provider, node.children != nil, !node.isLoading, !loadingPaths.contains(node.path) else { return }
        let path = node.path
        let context = resourceContextID
        let showHidden = showHiddenFiles
        folderRefreshTasks[path]?.cancel()
        folderRefreshTasks[path] = Task { [weak self] in
            let entries = try? await provider.listDirectory(path: path, showHidden: showHidden)
            guard !Task.isCancelled, let self else { return }
            self.folderRefreshTasks[path] = nil
            // A folder deleted meanwhile fails to list; its parent's refresh drops it.
            guard let entries,
                  self.resourceContextID == context,
                  self.nodesByPath[path] === node,
                  node.children != nil else { return }
            self.mergeListing(self.visibleEntries(entries, filter: self.excludeFilter), into: node)
        }
    }

    private static func childPath(directoryPath: String, name rawName: String) throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\0"),
              !name.contains("\n"),
              !name.contains("\r") else {
            throw FileExplorerError.invalidMutationName
        }
        return (directoryPath as NSString).appendingPathComponent(name)
    }

    private static func replacingPathPrefix(_ candidate: String, old: String, new: String) -> String {
        guard candidate == old || Self.path(candidate, isContainedIn: old) else { return candidate }
        let suffix = String(candidate.dropFirst(old.count))
        return new + suffix
    }

    private static func pathHasAncestor(_ candidate: String, in paths: Set<String>) -> Bool {
        var ancestor = (candidate as NSString).deletingLastPathComponent
        while !ancestor.isEmpty {
            if paths.contains(ancestor) { return true }
            let nextAncestor = (ancestor as NSString).deletingLastPathComponent
            guard nextAncestor != ancestor else { return false }
            ancestor = nextAncestor
        }
        return false
    }

    private static func pathIsContained(_ candidate: String, inAnyOf roots: Set<String>) -> Bool {
        var current = candidate
        while true {
            if roots.contains(current) { return true }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current else { return false }
            current = parent
        }
    }

    private static func pathsEqual(_ lhs: String, _ rhs: String) -> Bool {
        func trimmed(_ path: String) -> String {
            var result = path
            while result.count > 1, result.hasSuffix("/") {
                result.removeLast()
            }
            return result
        }
        return trimmed(lhs) == trimmed(rhs)
    }

    /// Cancels the directory-watch consumer, stops the watcher and drops any
    /// folder re-listing still in flight.
    private func stopDirectoryWatcher() {
        directoryWatchTask?.cancel()
        directoryWatchTask = nil
        if let directoryWatcher {
            Task { await directoryWatcher.stop() }
        }
        directoryWatcher = nil
        directoryWatchPath = nil
        for task in folderRefreshTasks.values {
            task.cancel()
        }
        folderRefreshTasks = [:]
    }

    func setProvider(_ newProvider: FileExplorerProvider?, reloadIfAvailable: Bool = true) {
        #if DEBUG
        NSLog("[FileExplorer] setProvider: \(type(of: newProvider).self) available=\(newProvider?.isAvailable ?? false)")
        #endif
        let providerChanged: Bool
        switch (provider, newProvider) {
        case let (current?, next?): providerChanged = current !== next
        case (nil, nil): providerChanged = false
        default: providerChanged = true
        }
        if providerChanged { resetResourceContext(preservingNavigation: true) }
        provider = newProvider
        // Re-expand previously expanded nodes if provider becomes available
        if reloadIfAvailable, newProvider?.isAvailable == true {
            reload()
        }
    }

    #if DEBUG
    func setProviderForTesting(_ newProvider: FileExplorerProvider?, reloadIfAvailable: Bool = true) {
        setProvider(newProvider, reloadIfAvailable: reloadIfAvailable)
    }
    #endif

    func reload() {
        #if DEBUG
        NSLog("[FileExplorer] reload() path=\(rootPath) provider=\(type(of: provider).self)")
        #endif
        contentRevision &+= 1
        cancelAllLoads()
        rootNodes = []
        nodesByPath = [:]
        guard !rootPath.isEmpty, provider != nil else { return }
        isRootLoading = true
        let path = rootPath
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadChildren(for: nil, at: path)
        }
        loadTasks[rootPath] = task
    }

    /// Re-lists the root after an entry appears or disappears in it and merges the
    /// listing into the current tree. Unlike ``reload()``, the tree is never emptied
    /// and no loading state is shown, so a terminal or agent creating files in the
    /// root no longer makes the whole tree flash. Nodes for entries that still exist
    /// are kept, with their loaded children, expansion and selection.
    func refreshRootInPlace() {
        guard !rootPath.isEmpty, let provider, !isRootLoading, !rootNodes.isEmpty else {
            reload()
            return
        }
        let path = rootPath
        let context = resourceContextID
        let showHidden = showHiddenFiles
        rootRefreshTask?.cancel()
        rootRefreshTask = Task { [weak self] in
            guard let entries = try? await provider.listDirectory(path: path, showHidden: showHidden),
                  !Task.isCancelled,
                  let self,
                  self.rootPath == path,
                  self.resourceContextID == context else { return }
            self.mergeListing(self.visibleEntries(entries, filter: self.excludeFilter), into: nil)
        }
    }

    /// Merges a fresh listing into the root (`parent` nil) or a loaded folder.
    /// Nodes for entries that still exist are kept, with their loaded children,
    /// expansion and selection; nothing changes when no entry appeared or
    /// disappeared.
    private func mergeListing(_ entries: [FileExplorerEntry], into parent: FileExplorerNode?) {
        let current = parent.map { $0.children ?? [] } ?? rootNodes
        var existing: [String: FileExplorerNode] = [:]
        for node in current {
            existing[node.path] = node
        }
        var directoriesToReexpand: [FileExplorerNode] = []
        let merged = entries.map { entry -> FileExplorerNode in
            if let node = existing[entry.path], node.isDirectory == entry.isDirectory {
                return node
            }
            let node = FileExplorerNode(name: entry.name, path: entry.path, isDirectory: entry.isDirectory)
            node.resourceContextID = resourceContextID
            nodesByPath[entry.path] = node
            if node.isDirectory, expandedPaths.contains(node.path) {
                directoriesToReexpand.append(node)
            }
            return node
        }.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        // Nothing appeared or disappeared (a metadata-only change): leave the tree alone.
        guard merged.map(\.path) != current.map(\.path) else { return }

        let keptPaths = Set(merged.map(\.path))
        let removedPaths = current.map(\.path).filter { !keptPaths.contains($0) }
        if !removedPaths.isEmpty {
            nodesByPath = nodesByPath.filter { path, _ in
                !removedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
            }
            if let selectedPath, nodesByPath[selectedPath] == nil {
                self.selectedPath = nil
            }
            selectedPaths = selectedPaths.filter { nodesByPath[$0] != nil }
        }
        if let parent {
            // The outline reloads loaded folders' rows in place on this signal.
            parent.children = merged
            objectWillChange.send()
        } else {
            rootNodes = merged
            contentRevision &+= 1
        }

        for directory in directoriesToReexpand {
            directory.isLoading = true
            let directoryPath = directory.path
            loadTasks[directoryPath] = Task { [weak self] in
                guard let self else { return }
                await self.loadChildren(for: directory, at: directoryPath)
            }
        }
    }

    /// Expands every folder between the root and `path`, selects `path` and asks
    /// the outline to scroll it into view. Returns false when `path` is not
    /// inside the current root or no longer exists.
    @discardableResult
    func reveal(path: String) async -> Bool {
        let root = rootPath
        guard !root.isEmpty, Self.path(path, isContainedIn: root), !Self.pathsEqual(path, root) else { return false }
        if rootNodes.isEmpty, let rootLoad = loadTasks[root] {
            await rootLoad.value
        }
        var ancestors: [String] = []
        var current = (path as NSString).deletingLastPathComponent
        while Self.path(current, isContainedIn: root), !Self.pathsEqual(current, root) {
            ancestors.insert(current, at: 0)
            current = (current as NSString).deletingLastPathComponent
        }
        for ancestor in ancestors {
            guard rootPath == root, let node = nodesByPath[ancestor], node.isDirectory else { return false }
            expandedPaths.insert(ancestor)
            if node.children == nil {
                await loadChildren(for: node, at: ancestor)
            }
        }
        guard rootPath == root, nodesByPath[path] != nil else { return false }
        selectedPath = path
        selectedPaths = [path]
        revealScrollRequested = true
        objectWillChange.send()
        return true
    }

    /// Whether the next selection sync should scroll; true once after a reveal.
    func consumeRevealScrollRequest() -> Bool {
        defer { revealScrollRequested = false }
        return revealScrollRequested
    }

    func expand(node: FileExplorerNode) {
        guard node.resourceContextID == nil || node.resourceContextID == resourceContextID, node.isDirectory else { return }
        expandedPaths.insert(node.path)
        if node.children == nil, loadTasks[node.path] == nil, !loadingPaths.contains(node.path) {
            node.isLoading = true
            node.error = nil
            objectWillChange.send()
            let nodePath = node.path
            let task = Task { [weak self] in
                guard let self else { return }
                await self.loadChildren(for: node, at: nodePath)
            }
            loadTasks[node.path] = task
        }
    }

    func collapse(node: FileExplorerNode) {
        expandedPaths.remove(node.path)
        if pendingDescendIntoFirstChildPath == node.path {
            pendingDescendIntoFirstChildPath = nil
        }
        objectWillChange.send()
    }

    func isExpanded(_ node: FileExplorerNode) -> Bool {
        expandedPaths.contains(node.path)
    }

    func select(node: FileExplorerNode?) {
        let path = node?.path
        let paths = path.map { Set([$0]) } ?? []
        guard selectedPath != path || selectedPaths != paths else { return }
        selectedPath = path
        selectedPaths = paths
        if path != pendingDescendIntoFirstChildPath {
            pendingDescendIntoFirstChildPath = nil
        }
    }

    func select(nodes: [FileExplorerNode], anchor: FileExplorerNode?) {
        let paths = Set(nodes.map(\.path))
        let path = anchor?.path ?? nodes.first?.path
        guard selectedPath != path || selectedPaths != paths else { return }
        selectedPath = path
        selectedPaths = paths
        if path != pendingDescendIntoFirstChildPath {
            pendingDescendIntoFirstChildPath = nil
        }
    }

    func requestDescendIntoFirstChild(of node: FileExplorerNode) {
        guard node.resourceContextID == nil || node.resourceContextID == resourceContextID, node.isDirectory else { return }
        selectedPath = node.path
        selectedPaths = [node.path]
        pendingDescendIntoFirstChildPath = node.path
        expand(node: node)
    }

    func prefetchChildren(for node: FileExplorerNode) {
        guard node.resourceContextID == nil || node.resourceContextID == resourceContextID, node.isDirectory, node.children == nil, !loadingPaths.contains(node.path) else { return }
        // Debounce: only prefetch if hover persists for 200ms
        let path = node.path
        let scheduler = prefetchSchedulers[path] ?? MainActorDeferredActionScheduler()
        prefetchSchedulers[path] = scheduler
        scheduler.schedule(after: .milliseconds(200)) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, node.children == nil, !self.loadingPaths.contains(path) else { return }
                // Silent prefetch: don't show loading indicator
                await self.loadChildren(for: node, at: path, silent: true)
            }
        }
    }

    func cancelPrefetch(for node: FileExplorerNode) {
        prefetchSchedulers[node.path]?.cancel()
        prefetchSchedulers.removeValue(forKey: node.path)
    }

    /// Called when SSH provider becomes available after being unavailable.
    /// Re-hydrates expanded nodes that were waiting.
    func hydrateExpandedNodes() {
        guard let provider, provider.isAvailable, !expandedPaths.isEmpty else { return }
        #if DEBUG
        NSLog("[FileExplorer] hydrateExpandedNodes: \(expandedPaths.count) paths to hydrate")
        #endif
        reload()
    }

    // MARK: - Private

    @MainActor
    private func loadChildren(for parentNode: FileExplorerNode?, at path: String, silent: Bool = false) async {
        guard parentNode?.resourceContextID == nil || parentNode?.resourceContextID == resourceContextID else { return }
        // A load cancelled by cancelAllLoads (e.g. a root reload during an SSH provider swap) must not
        // reach provider.listDirectory: the provider may have been replaced, so a stale in-flight load
        // would list the old path through the new transport. Bail before any listing.
        guard !Task.isCancelled else { return }
        guard let provider else { return }

        if !silent {
            loadingPaths.insert(path)
            parentNode?.error = nil
            objectWillChange.send()
        }

        do {
            let entries = visibleEntries(
                try await provider.listDirectory(path: path, showHidden: showHiddenFiles),
                filter: excludeFilter
            )
            try Task.checkCancellation()
            let children = entries.map { entry in
                let node = FileExplorerNode(name: entry.name, path: entry.path, isDirectory: entry.isDirectory)
                node.resourceContextID = resourceContextID
                nodesByPath[entry.path] = node
                return node
            }.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            if let parentNode {
                parentNode.children = children
                parentNode.isLoading = false
                parentNode.error = nil
                if pendingDescendIntoFirstChildPath == parentNode.path {
                    let path = children.first?.path ?? parentNode.path
                    selectedPath = path
                    selectedPaths = [path]
                    pendingDescendIntoFirstChildPath = nil
                }
            } else {
                rootNodes = children
                isRootLoading = false
                setRootStatusMessage(nil)
                if selectedPath == nil {
                    selectedPath = children.first?.path
                    selectedPaths = selectedPath.map { Set([$0]) } ?? []
                }
            }
            loadingPaths.remove(path)
            loadTasks.removeValue(forKey: path)
            objectWillChange.send()

            // Auto-expand children that were previously expanded
            for child in children where child.isDirectory && expandedPaths.contains(child.path) {
                child.isLoading = true
                objectWillChange.send()
                let childPath = child.path
                let childTask = Task { [weak self] in
                    guard let self else { return }
                    await self.loadChildren(for: child, at: childPath)
                }
                loadTasks[child.path] = childTask
            }
        } catch {
            if !Task.isCancelled {
                if let parentNode {
                    parentNode.isLoading = false
                    parentNode.error = error.localizedDescription
                } else {
                    isRootLoading = false
                    setRootStatusMessage(error.localizedDescription)
                }
                loadingPaths.remove(path)
                loadTasks.removeValue(forKey: path)
                objectWillChange.send()
            }
        }
    }

    private func cancelAllLoads() {
        for (_, task) in loadTasks {
            task.cancel()
        }
        loadTasks.removeAll()
        loadingPaths.removeAll()
        pendingDescendIntoFirstChildPath = nil
        for scheduler in prefetchSchedulers.values {
            scheduler.cancel()
        }
        prefetchSchedulers.removeAll()
        isRootLoading = false
    }

    private static func remotePreviewCacheURL(displayTarget: String, remotePath: String) -> URL {
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-remote-file-previews", isDirectory: true)
        let target = sanitizedCacheComponent(displayTarget)
        let remote = sanitizedCacheComponent(remotePath)
        let basename = URL(fileURLWithPath: remotePath).lastPathComponent
        let filename = basename.isEmpty ? remote : "\(remote)-\(basename)"
        return cacheRoot
            .appendingPathComponent(target, isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
    }

    private static func sanitizedCacheComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let candidate = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return candidate.isEmpty ? UUID().uuidString : String(candidate.prefix(160))
    }

    deinit {
        remoteHomeResolutionTask?.cancel()
        directoryWatchTask?.cancel()
        excludeObservation?.cancel()
    }
}
