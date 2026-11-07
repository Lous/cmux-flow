import Foundation

/// Repositories the Source Control panel has found per workspace.
///
/// A workspace's reported directory follows its focused terminal, so the set
/// of directories moves as terminals `cd` between projects. Remembering every
/// repository seen keeps a multi-project workspace listing all of its projects
/// instead of only the one the focused terminal is in. The list is persisted
/// by workspace id (stable across session restore), so a restarted app shows
/// the same projects before any terminal re-enters them. The app delegate owns
/// one instance.
@MainActor
final class SourceControlRepositoryMemory {
    /// One workspace's remembered repositories.
    private struct Record: Codable {
        var roots: [String]
        var updatedAt: Date
    }

    static let defaultsKey = "sourceControl.repositoriesByWorkspace"

    private let defaults: UserDefaults
    private let maximumRepositories: Int
    private let maximumWorkspaces: Int
    private var records: [UUID: Record]

    /// - Parameters:
    ///   - defaults: Where the lists persist.
    ///   - maximumRepositories: Cap per workspace, matching discovery's cap.
    ///   - maximumWorkspaces: Least recently updated workspaces are dropped past this.
    init(
        defaults: UserDefaults = .standard,
        maximumRepositories: Int = SourceControlGitClient.maximumRepositories,
        maximumWorkspaces: Int = 100
    ) {
        self.defaults = defaults
        self.maximumRepositories = maximumRepositories
        self.maximumWorkspaces = maximumWorkspaces
        records = Self.load(from: defaults)
    }

    /// Remembered roots that still exist on disk.
    func roots(for workspaceId: UUID) -> [String] {
        let fileManager = FileManager.default
        return (records[workspaceId]?.roots ?? []).filter { fileManager.fileExists(atPath: $0) }
    }

    /// Adds newly discovered roots after the known ones and returns the merged list.
    func merge(_ discovered: [String], for workspaceId: UUID) -> [String] {
        let known = roots(for: workspaceId)
        var merged = known
        for root in discovered where !merged.contains(root) {
            guard merged.count < maximumRepositories else { break }
            merged.append(root)
        }
        if merged != records[workspaceId]?.roots {
            store(merged, for: workspaceId)
        }
        return merged
    }

    /// Drops one repository; it comes back if a terminal enters it again.
    func remove(_ root: String, for workspaceId: UUID) -> [String] {
        var roots = roots(for: workspaceId)
        roots.removeAll { $0 == root }
        store(roots, for: workspaceId)
        return roots
    }

    private func store(_ roots: [String], for workspaceId: UUID) {
        records[workspaceId] = Record(roots: roots, updatedAt: Date())
        if records.count > maximumWorkspaces {
            let stale = records
                .sorted { $0.value.updatedAt > $1.value.updatedAt }
                .dropFirst(maximumWorkspaces)
                .map(\.key)
            for id in stale {
                records.removeValue(forKey: id)
            }
        }
        let encodable = Dictionary(uniqueKeysWithValues: records.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(encodable) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [UUID: Record] {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: Record].self, from: data) else {
            return [:]
        }
        var records: [UUID: Record] = [:]
        for (key, record) in decoded {
            if let id = UUID(uuidString: key) {
                records[id] = record
            }
        }
        return records
    }
}
