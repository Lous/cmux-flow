import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// A Source Control file tab is a live diff editor: it shows the file as it is
/// now, follows it between staged and working-tree changes, and may only write
/// the working-tree file it names.
final class DiffEditFileServiceTests: XCTestCase {
    private var root = ""
    private let service = DiffEditFileService()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diff-edit-tests-\(UUID().uuidString)", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try shell("""
            git init -q && git config user.email t@example.com && git config user.name t && \
            printf 'a\\nb\\n' > mod.txt && printf 'x\\r\\ny\\r\\n' > crlf.txt && printf 'same\\n' > clean.txt && \
            printf 'one\\n' > staged.txt && printf 'base\\n' > both.txt && printf 'gone\\n' > gone.txt && \
            printf '#!/bin/sh\\necho\\n' > run.sh && chmod 755 run.sh && git add . && git commit -qm init && \
            printf 'a\\nB\\n' > mod.txt && printf 'x\\r\\nY\\r\\n' > crlf.txt && printf '#!/bin/sh\\necho hi\\n' > run.sh && \
            printf 'two\\n' > staged.txt && git add staged.txt && \
            printf 'index\\n' > both.txt && git add both.txt && printf 'disk\\n' > both.txt && rm gone.txt && \
            mkdir -p newdir && printf 'new\\n' > newdir/u.txt && printf 'bin\\0ary' > bin.dat && \
            ln -s /etc/hosts out.txt && ln -s .git/config cfg.txt
            """)
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

    private func scope() async throws -> DiffEditScope {
        let scope = await service.scope(forRepositoryRoot: root)
        return try XCTUnwrap(scope)
    }

    private func load(_ path: String, preferring view: DiffEditView = .workingTree) async throws -> DiffEditLoadedFile {
        try await service.load(relativePath: path, preferring: view, in: try await scope())
    }

    func testScopeIsOnlyARepositoryTopLevel() async throws {
        _ = try await scope()
        let nested = await service.scope(forRepositoryRoot: root + "/newdir")
        XCTAssertNil(nested)
        let relative = await service.scope(forRepositoryRoot: "relative/path")
        XCTAssertNil(relative)
    }

    func testModifiedFileIsEditableAgainstTheIndex() async throws {
        let file = try await load("mod.txt")
        XCTAssertEqual(file.view, .workingTree)
        XCTAssertEqual(file.content, "a\nB\n")
        XCTAssertEqual(file.base, "a\nb\n")
        XCTAssertNotNil(file.grant)
        XCTAssertEqual(file.sha256, DiffEditFileService.sha256(of: Data("a\nB\n".utf8)))
    }

    func testKeepsCRLFInTextAndBase() async throws {
        let file = try await load("crlf.txt")
        XCTAssertEqual(file.content, "x\r\nY\r\n")
        XCTAssertEqual(file.base, "x\r\ny\r\n")
    }

    func testUntrackedFileComparesAgainstNothing() async throws {
        let file = try await load("newdir/u.txt")
        XCTAssertEqual(file.view, .workingTree)
        XCTAssertEqual(file.base, "")
        XCTAssertEqual(file.content, "new\n")
    }

    func testStagedTabIsReadOnlyIndexAgainstHead() async throws {
        // A Staged Changes click opens the tab preferring the staged comparison.
        let file = try await load("staged.txt", preferring: .staged)
        XCTAssertEqual(file.view, .staged)
        XCTAssertEqual(file.base, "one\n")
        XCTAssertEqual(file.content, "two\n")
        XCTAssertNil(file.grant)
    }

    func testUnstagingMovesTheTabToTheEditableWorkingTree() async throws {
        try shell("git restore --staged staged.txt")
        let file = try await load("staged.txt", preferring: .staged)
        XCTAssertEqual(file.view, .workingTree)
        XCTAssertEqual(file.base, "one\n")
        XCTAssertEqual(file.content, "two\n")
        XCTAssertNotNil(file.grant)
    }

    func testStagingEverythingKeepsTheWorkingTreeTabEditable() async throws {
        try shell("git add mod.txt")
        let file = try await load("mod.txt", preferring: .workingTree)
        XCTAssertEqual(file.view, .workingTree)
        XCTAssertEqual(file.base, "a\nB\n")
        XCTAssertEqual(file.content, "a\nB\n")
        XCTAssertNotNil(file.grant)
    }

    func testDiscardingLeavesTheFileClean() async throws {
        try shell("git checkout -- mod.txt")
        let file = try await load("mod.txt")
        XCTAssertEqual(file.view, .clean)
        XCTAssertEqual(file.base, file.content)
    }

    func testPartlyStagedFileKeepsTheComparisonTheTabShows() async throws {
        let staged = try await load("both.txt", preferring: .staged)
        XCTAssertEqual(staged.view, .staged)
        XCTAssertEqual(staged.base, "base\n")
        XCTAssertEqual(staged.content, "index\n")
        let workingTree = try await load("both.txt", preferring: .workingTree)
        XCTAssertEqual(workingTree.view, .workingTree)
        XCTAssertEqual(workingTree.base, "index\n")
        XCTAssertEqual(workingTree.content, "disk\n")
    }

    func testDeletedFileShowsItsLastTextReadOnly() async throws {
        let file = try await load("gone.txt")
        XCTAssertEqual(file.view, .workingTree)
        XCTAssertTrue(file.deleted)
        XCTAssertEqual(file.base, "gone\n")
        XCTAssertEqual(file.content, "")
        XCTAssertNil(file.grant)
    }

    func testBinaryFileIsNotEditable() async throws {
        do {
            _ = try await load("bin.dat")
            XCTFail("a binary file must not load as text")
        } catch DiffEditError.binary {}
    }

    func testSaveWritesAndRefusesStaleHash() async throws {
        let file = try await load("mod.txt")
        let grant = try XCTUnwrap(file.grant)
        let sha256 = try XCTUnwrap(file.sha256)
        let newHash = try await service.save("a\nB\nc\n", to: grant, expectedSHA256: sha256)
        XCTAssertEqual(try String(contentsOfFile: root + "/mod.txt", encoding: .utf8), "a\nB\nc\n")
        do {
            _ = try await service.save("zzz", to: grant, expectedSHA256: sha256)
            XCTFail("a save over outside changes must conflict")
        } catch DiffEditError.conflict(let current) {
            XCTAssertEqual(current, newHash)
        }
        XCTAssertEqual(try String(contentsOfFile: root + "/mod.txt", encoding: .utf8), "a\nB\nc\n")
    }

    func testSaveKeepsPermissions() async throws {
        let file = try await load("run.sh")
        _ = try await service.save(
            "#!/bin/sh\necho bye\n",
            to: try XCTUnwrap(file.grant),
            expectedSHA256: try XCTUnwrap(file.sha256)
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: root + "/run.sh")
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testGrantRejectsPathsOutsideTheRepository() async throws {
        let scope = try await scope()
        for path in ["../escape.txt", "/etc/hosts", ".git/config", ".GIT/config", "out.txt", "cfg.txt",
                     "newdir", "missing.txt", "newdir//u.txt", "./mod.txt"] {
            XCTAssertThrowsError(try DiffEditFileService.grant(for: path, in: scope), path) { error in
                XCTAssertEqual(error as? DiffEditError, .pathRejected, path)
            }
        }
    }
}
