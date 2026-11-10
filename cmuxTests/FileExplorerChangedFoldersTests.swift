import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Files tab re-lists every folder a change touched, not only the root,
/// so a file an agent writes in an expanded folder shows up right away.
final class FileExplorerChangedFoldersTests: XCTestCase {
    func testAFileInASubfolderTouchesThatFolder() {
        let changed = FileExplorerChangedFolders(
            eventPaths: ["/wow/WarShoutAlert/docs/curseforge-description.md"],
            rootPath: "/wow",
            resolvedRootPath: "/wow"
        )
        XCTAssertEqual(changed.folders, ["/wow/WarShoutAlert/docs"])
    }

    func testRootEntriesAndNewFoldersTouchTheirParent() {
        let changed = FileExplorerChangedFolders(
            eventPaths: ["/wow/README.md", "/wow/Addon/new-folder", "/wow/Addon/new-folder/"],
            rootPath: "/wow/",
            resolvedRootPath: "/wow"
        )
        XCTAssertEqual(changed.folders, ["/wow", "/wow/Addon"])
    }

    func testTheRootItselfAndPathsOutsideItAreIgnored() {
        let changed = FileExplorerChangedFolders(
            eventPaths: ["/wow", "/wowsers/file", "/elsewhere/file"],
            rootPath: "/wow",
            resolvedRootPath: "/wow"
        )
        XCTAssertTrue(changed.folders.isEmpty)
    }

    func testResolvedEventPathsMapBackOntoTheTreeRoot() {
        let changed = FileExplorerChangedFolders(
            eventPaths: ["/private/var/repo/src/a.swift", "/var/repo/b.txt"],
            rootPath: "/var/repo",
            resolvedRootPath: "/private/var/repo"
        )
        XCTAssertEqual(changed.folders, ["/var/repo/src", "/var/repo"])
    }

    func testGitBookkeepingIsNotAListingChange() {
        XCTAssertFalse(FileExplorerChangedFolders.isListingChange(["/repo/.git/index", "/repo/.git/refs/heads/main"]))
        XCTAssertTrue(FileExplorerChangedFolders.isListingChange(["/repo/.git/index", "/repo/docs/a.md"]))
        XCTAssertTrue(FileExplorerChangedFolders.isListingChange(["/repo/.github/workflows/ci.yml"]))
    }

    func testResolvedPathFollowsSymlinks() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("changed-folders-\(UUID().uuidString)")
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(
            FileExplorerChangedFolders.resolvedPath(link.path),
            FileExplorerChangedFolders.resolvedPath(real.path)
        )
        XCTAssertTrue(FileExplorerChangedFolders.resolvedPath(link.path).hasSuffix("/real"))
        XCTAssertEqual(FileExplorerChangedFolders.resolvedPath("/no/such/path"), "/no/such/path")
    }
}
