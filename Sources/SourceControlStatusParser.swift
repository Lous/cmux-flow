import Foundation

/// Parses Git's machine-readable status and numstat output.
///
/// Both inputs come from `-z` invocations: records are NUL-terminated and
/// paths are never quoted, so names with spaces, tabs or newlines survive.
struct SourceControlStatusParser: Sendable {
    /// Status for one repository: its branch headers and changed entries.
    struct StatusResult: Equatable, Sendable {
        var branch = SourceControlBranchInfo()
        var changes: [SourceControlFileChange] = []
        var isTruncated = false
    }

    /// Line counts for one path; nil counts mean Git reported a binary file.
    struct LineCounts: Equatable, Sendable {
        var additions: Int?
        var deletions: Int?
    }

    /// Default upper bound on listed entries, so a repository with an
    /// unignored build directory cannot flood the panel.
    static let maximumEntries = 2_000

    let maximumEntries: Int

    init(maximumEntries: Int = SourceControlStatusParser.maximumEntries) {
        self.maximumEntries = maximumEntries
    }

    /// Parses `git status --porcelain=v2 --branch -z` output.
    func parseStatus(_ data: Data) -> StatusResult {
        var result = StatusResult()
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var index = 0
        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)
            index += 1
            guard !record.isEmpty else { continue }

            if record.hasPrefix("# ") {
                parseBranchHeader(record, into: &result.branch)
                continue
            }
            guard result.changes.count < maximumEntries else {
                result.isTruncated = true
                continue
            }

            switch record.first {
            case "1":
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count == 9 else { continue }
                appendOrdinary(xy: fields[1], path: String(fields[8]), originalPath: nil, into: &result.changes)
            case "2":
                // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <Xscore> <path>, then <origPath> as its own record.
                let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10 else { continue }
                var originalPath: String?
                if index < records.count {
                    originalPath = String(decoding: records[index], as: UTF8.self)
                    index += 1
                }
                appendOrdinary(xy: fields[1], path: String(fields[9]), originalPath: originalPath, into: &result.changes)
            case "u":
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count == 11 else { continue }
                result.changes.append(
                    SourceControlFileChange(group: .conflicts, path: String(fields[10]), originalPath: nil, gitStatus: "U")
                )
            case "?":
                let path = String(record.dropFirst(2))
                guard !path.isEmpty else { continue }
                result.changes.append(
                    SourceControlFileChange(group: .untracked, path: path, originalPath: nil, gitStatus: "?")
                )
            default:
                // "!" ignored entries (only with --ignored) and future record kinds.
                continue
            }
        }
        return result
    }

    /// Parses `git diff --numstat -z` output, keying renames by their destination path.
    func parseNumstat(_ data: Data) -> [String: LineCounts] {
        var counts: [String: LineCounts] = [:]
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var index = 0
        while index < records.count {
            let record = String(decoding: records[index], as: UTF8.self)
            index += 1
            guard !record.isEmpty else { continue }
            // <added>\t<deleted>\t<path>, or <added>\t<deleted>\t followed by
            // <origPath> and <path> records for a rename.
            let fields = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let path: String
            if fields[2].isEmpty {
                guard index + 1 < records.count else { break }
                path = String(decoding: records[index + 1], as: UTF8.self)
                index += 2
            } else {
                path = String(fields[2])
            }
            counts[path] = LineCounts(additions: Int(fields[0]), deletions: Int(fields[1]))
        }
        return counts
    }

    private func parseBranchHeader(_ record: String, into branch: inout SourceControlBranchInfo) {
        let fields = record.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard fields.count == 3 else { return }
        let value = String(fields[2])
        switch fields[1] {
        case "branch.oid":
            branch.oid = value == "(initial)" ? nil : value
        case "branch.head":
            branch.head = value == "(detached)" ? nil : value
        case "branch.upstream":
            branch.upstream = value
        case "branch.ab":
            for part in value.split(separator: " ") {
                if part.hasPrefix("+") {
                    branch.ahead = Int(part.dropFirst()) ?? 0
                } else if part.hasPrefix("-") {
                    branch.behind = Int(part.dropFirst()) ?? 0
                }
            }
        default:
            break
        }
    }

    private func appendOrdinary(
        xy: Substring,
        path: String,
        originalPath: String?,
        into changes: inout [SourceControlFileChange]
    ) {
        let codes = Array(xy)
        guard codes.count == 2 else { return }
        let indexCode = codes[0]
        let workTreeCode = codes[1]
        if indexCode != "." {
            changes.append(
                SourceControlFileChange(group: .staged, path: path, originalPath: originalPath, gitStatus: indexCode)
            )
        }
        if workTreeCode != "." {
            changes.append(
                SourceControlFileChange(group: .unstaged, path: path, originalPath: nil, gitStatus: workTreeCode)
            )
        }
    }
}
