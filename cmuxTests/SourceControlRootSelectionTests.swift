import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Git tab follows the workspace's terminals: it lists the repositories
/// they are in now, not every repository they ever visited.
final class SourceControlRootSelectionTests: XCTestCase {
    func testLeavingARepositoryDropsIt() {
        var selection = SourceControlRootSelection()
        XCTAssertEqual(selection.update(discovered: ["/src/wow"]).added, ["/src/wow"])

        // `cd ~/4Engine/cmux` from `~/wow`.
        let change = selection.update(discovered: ["/src/cmux"])
        XCTAssertEqual(selection.roots, ["/src/cmux"])
        XCTAssertEqual(change.added, ["/src/cmux"])
        XCTAssertEqual(change.removed, ["/src/wow"])
    }

    func testEveryTerminalContributesItsRepository() {
        var selection = SourceControlRootSelection()
        selection.update(discovered: ["/src/cmux", "/src/wow", "/src/cmux"])
        XCTAssertEqual(selection.roots, ["/src/cmux", "/src/wow"])

        let unchanged = selection.update(discovered: ["/src/cmux", "/src/wow"])
        XCTAssertTrue(unchanged.isEmpty)

        // Closing the terminal in `wow` drops it.
        XCTAssertEqual(selection.update(discovered: ["/src/cmux"]).removed, ["/src/wow"])
        XCTAssertTrue(selection.update(discovered: []).removed == ["/src/cmux"])
        XCTAssertTrue(selection.roots.isEmpty)
    }

    func testRemovedRepositoryStaysHiddenUntilATerminalEntersItAgain() {
        var selection = SourceControlRootSelection()
        selection.update(discovered: ["/src/a", "/src/b"])
        selection.dismiss("/src/a")
        XCTAssertEqual(selection.roots, ["/src/b"])

        // A terminal still in `a`: it stays hidden.
        XCTAssertTrue(selection.update(discovered: ["/src/a", "/src/b"]).isEmpty)
        XCTAssertEqual(selection.roots, ["/src/b"])

        // The terminal leaves `a`, then comes back.
        selection.update(discovered: ["/src/b"])
        XCTAssertEqual(selection.update(discovered: ["/src/a", "/src/b"]).added, ["/src/a"])
        XCTAssertEqual(selection.roots, ["/src/a", "/src/b"])
    }

    func testCandidatesAreTheOpenTerminalsDirectories() {
        let first = UUID()
        let second = UUID()
        // The workspace directory lags behind a closed terminal: left out.
        XCTAssertEqual(
            SourceControlRootSelection.candidateDirectories(
                currentDirectory: "/src/wow",
                panelDirectories: [first: "/src/cmux", second: " /src/cmux "]
            ),
            ["/src/cmux"]
        )
        // No terminal has reported a directory yet: the workspace's is used.
        XCTAssertEqual(
            SourceControlRootSelection.candidateDirectories(currentDirectory: "/src/wow", panelDirectories: [first: " "]),
            ["/src/wow"]
        )
        XCTAssertEqual(SourceControlRootSelection.candidateDirectories(currentDirectory: "", panelDirectories: [:]), [])
    }

    func testRootsThatStoppedBeingRepositoriesAreRemoved() {
        var selection = SourceControlRootSelection()
        selection.update(discovered: ["/src/mono/project", "/src/other"])
        selection.remove(["/src/mono/project"])
        XCTAssertEqual(selection.roots, ["/src/other"])
        // The enclosing monorepo is listed once discovery finds it.
        XCTAssertEqual(selection.update(discovered: ["/src/mono", "/src/other"]).added, ["/src/mono"])
    }
}
