import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The Files tab hides what VS Code's `files.exclude` would: its default
/// patterns, overridden entry by entry by `fileExplorer.exclude`.
final class FileExplorerExcludeFilterTests: XCTestCase {
    private func glob(_ source: String) throws -> FileExplorerGlobPattern {
        try XCTUnwrap(FileExplorerGlobPattern(source), source)
    }

    private func hides(_ filter: FileExplorerExcludeFilter, _ relativePath: String, siblings: Set<String> = []) -> Bool {
        let name = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        return filter.excludes(
            relativePath: relativePath,
            absolutePath: "/repo/" + relativePath,
            name: name,
            siblingNames: siblings
        )
    }

    func testGlobstarMatchesAnyDepthButOnlyWholeNames() throws {
        let git = try glob("**/.git")
        XCTAssertTrue(git.matches(".git"))
        XCTAssertTrue(git.matches("a/b/.git"))
        XCTAssertFalse(git.matches(".github"))
        XCTAssertFalse(git.matches("a/.gitignore"))
        XCTAssertTrue(try glob("src/**/gen").matches("src/gen"))
        XCTAssertTrue(try glob("src/**/gen").matches("src/a/b/gen"))
        XCTAssertFalse(try glob("src/**/gen").matches("lib/gen"))
    }

    func testPatternWithoutGlobstarNamesOnlyTheRoot() throws {
        let build = try glob("build")
        XCTAssertTrue(build.matches("build"))
        XCTAssertFalse(build.matches("app/build"))
        XCTAssertTrue(try glob("*.log").matches("x.log"))
        XCTAssertFalse(try glob("*.log").matches("logs/x.log"))
        XCTAssertTrue(try glob("**/*.log").matches("logs/x.log"))
    }

    func testWildcardsSetsAndBraces() throws {
        XCTAssertTrue(try glob("file?.txt").matches("file1.txt"))
        XCTAssertFalse(try glob("file?.txt").matches("file10.txt"))
        XCTAssertTrue(try glob("file[0-9].txt").matches("file3.txt"))
        XCTAssertFalse(try glob("file[0-9].txt").matches("fileA.txt"))
        XCTAssertTrue(try glob("file[!0-9].txt").matches("fileA.txt"))
        XCTAssertFalse(try glob("file[!0-9].txt").matches("file3.txt"))
        let either = try glob("{**/*.html,**/*.txt}")
        XCTAssertTrue(either.matches("a/b.html"))
        XCTAssertTrue(either.matches("c.txt"))
        XCTAssertFalse(either.matches("d.md"))
        XCTAssertTrue(try glob("**/*.{js,map}").matches("dist/app.js.map"))
        // `*` matches a leading dot, as in VS Code.
        XCTAssertTrue(try glob("*rc").matches(".luacheckrc"))
        XCTAssertTrue(try glob("**/.DS_Store").matches(".DS_Store"))
        XCTAssertFalse(try glob("**/.DS_Store").matches(".ds_store"))
    }

    func testNormalizesAndRejectsEmptyPatterns() throws {
        XCTAssertTrue(try glob("./build/").matches("build"))
        XCTAssertNil(FileExplorerGlobPattern(""))
        XCTAssertNil(FileExplorerGlobPattern("   "))
        let absolute = try glob("/repo/secret")
        XCTAssertTrue(absolute.isAbsolute)
        XCTAssertTrue(absolute.matches("/repo/secret"))
    }

    func testDefaultsHideOnlyWhatVSCodeHides() {
        let filter = FileExplorerExcludeFilter()
        for hidden in [".git", ".DS_Store", "sub/.DS_Store", ".svn", ".hg", "Thumbs.db"] {
            XCTAssertTrue(hides(filter, hidden), hidden)
        }
        for shown in [".github", ".gitignore", ".claude", ".luacheckrc", "README.md", "node_modules"] {
            XCTAssertFalse(hides(filter, shown), shown)
        }
    }

    func testUserEntriesOverrideDefaultsAndAddPatterns() {
        let filter = FileExplorerExcludeFilter(userEntries: [
            "**/.git": .enabled(false),
            "build": .enabled(true),
            "not a [valid": .enabled(true),
        ])
        XCTAssertFalse(hides(filter, ".git"))
        XCTAssertTrue(hides(filter, ".DS_Store"))
        XCTAssertTrue(hides(filter, "build"))
        XCTAssertFalse(hides(filter, "app/build"))
    }

    func testWhenClauseNeedsTheSibling() {
        let filter = FileExplorerExcludeFilter(userEntries: ["**/*.js": .whenSibling("$(basename).ts")])
        XCTAssertTrue(hides(filter, "src/app.js", siblings: ["app.js", "app.ts"]))
        XCTAssertFalse(hides(filter, "src/app.js", siblings: ["app.js"]))
        XCTAssertTrue(hides(filter, "lib.min.js", siblings: ["lib.min.ts"]))
    }

    func testAbsolutePatternsMatchTheFullPath() {
        let filter = FileExplorerExcludeFilter(userEntries: ["/repo/secret": .enabled(true)])
        XCTAssertTrue(hides(filter, "secret"))
        XCTAssertFalse(hides(filter, "other"))
    }

    func testRipgrepGlobsAnchorLikeVSCodeSearch() {
        let filter = FileExplorerExcludeFilter(userEntries: [
            "build": .enabled(true),
            "**/*.js": .whenSibling("$(basename).ts"),
            "/repo/secret": .enabled(true),
            "/elsewhere/x": .enabled(true),
            "**/.hg": .enabled(false),
        ])
        XCTAssertTrue(filter.hasSiblingRules)
        XCTAssertFalse(FileExplorerExcludeFilter().hasSiblingRules)
        XCTAssertEqual(
            Set(filter.ripgrepExcludeGlobs(rootPath: "/repo/")),
            ["!**/.DS_Store", "!**/.git", "!**/.svn", "!**/Thumbs.db", "!/repo/build", "!/repo/secret", "!/elsewhere/x"]
        )
        XCTAssertTrue(filter.ripgrepExcludeGlobs(rootPath: "/src/app[1]").contains("!/src/app\\[1\\]/build"))
    }

    func testSettingsStoreTheCmuxJSONValueAndReadItBack() throws {
        let suite = "cmux-exclude-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FileExplorerExcludeSettings(defaults: defaults)
        XCTAssertEqual(settings.filter(), FileExplorerExcludeFilter())

        XCTAssertNil(FileExplorerExcludeSettings.storedValue(fromJSON: ["**/.git"]))
        let parsed = try XCTUnwrap(FileExplorerExcludeSettings.storedValue(fromJSON: [
            "**/.git": false,
            "**/*.js": ["when": "$(basename).ts"],
            "count": 1,
            "word": "yes",
        ] as [String: Any]))
        XCTAssertEqual(parsed.skippedPatterns, ["count", "word"])
        defaults.set(parsed.stored, forKey: FileExplorerExcludeSettings.key)
        XCTAssertEqual(settings.filter(), FileExplorerExcludeFilter(userEntries: [
            "**/.git": .enabled(false),
            "**/*.js": .whenSibling("$(basename).ts"),
        ]))
    }
}
