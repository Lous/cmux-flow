import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Git tab lists only folders that are still repositories: a remembered
/// project folded into an enclosing monorepo must not show that repo's changes.
final class SourceControlGitClientTests: XCTestCase {
    private var root = ""
    private let client = SourceControlGitClient()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scm-client-tests-\(UUID().uuidString)", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        // `project` starts as its own repository, then moves into the `root` monorepo.
        try shell("""
            mkdir project && cd project && git init -q && git config user.email t@example.com && \
            git config user.name t && printf 'a\\n' > a.txt && git add . && git commit -qm init && cd .. && \
            git init -q && git config user.email t@example.com && git config user.name t && \
            printf 'top\\n' > top.txt && git add top.txt && git commit -qm init && printf 'staged\\n' > new.txt && git add new.txt
            """)
        root = SourceControlGitClient.normalizedPath(root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    private func shell(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: root, isDirectory: true)
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, command)
    }

    func testRepositoryRootsHaveAGitMarker() {
        XCTAssertTrue(client.isRepositoryRoot(root))
        XCTAssertTrue(client.isRepositoryRoot(root + "/project"))
        XCTAssertFalse(client.isRepositoryRoot(root + "/missing"))
    }

    func testAProjectFoldedIntoAMonorepoIsNoLongerARepository() async throws {
        let project = root + "/project"
        let before = await client.snapshot(forRepositoryRoot: project)
        XCTAssertTrue(before.isRepositoryRoot)
        XCTAssertTrue(before.changes.isEmpty)

        try FileManager.default.removeItem(atPath: project + "/.git")
        let after = await client.snapshot(forRepositoryRoot: project)
        XCTAssertFalse(after.isRepositoryRoot)
        // Git would have answered for the monorepo, staging `new.txt`.
        XCTAssertTrue(after.changes.isEmpty)
        XCTAssertNil(after.errorMessage)

        let monorepo = await client.snapshot(forRepositoryRoot: root)
        XCTAssertTrue(monorepo.isRepositoryRoot)
        XCTAssertTrue(monorepo.changes.contains { $0.path == "new.txt" && $0.group == .staged })
    }

    func testDiscoveryResolvesAFoldedProjectToItsMonorepo() async throws {
        try FileManager.default.removeItem(atPath: root + "/project/.git")
        let discovered = await client.discoverRepositories(in: [root + "/project"])
        XCTAssertEqual(discovered, [root])
    }
}
