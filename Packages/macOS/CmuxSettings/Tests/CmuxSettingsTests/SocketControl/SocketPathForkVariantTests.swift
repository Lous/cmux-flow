import Testing
@testable import CmuxSettings

/// A rebranded fork must not claim the shipping app's stable control socket
/// or its discovery markers; cmux's own identities keep their defaults.
@Suite struct SocketPathForkVariantTests {
    @Test(arguments: ["io.github.lous.cmux-flow", "dev.example.terminal"])
    func forkIdentityGetsItsOwnSocketAndMarkers(_ bundleIdentifier: String) throws {
        let variant = SocketPathMarkerFiles.variant(bundleIdentifier: bundleIdentifier, environment: [:])
        guard case .fork(let slug) = variant else {
            Issue.record("expected a fork variant for \(bundleIdentifier), got \(variant)")
            return
        }
        let path = SocketPathMarkerFiles.defaultSocketPath(
            bundleIdentifier: bundleIdentifier,
            environment: [:],
            isDebugBuild: false,
            stableSocketPath: "/stable/cmux.sock"
        )
        #expect(path == "/tmp/cmux-fork-\(slug).sock")
        #expect(variant.markerFileName != SocketPathMarkerFiles.stableMarkerFileName)
        #expect(variant.tmpPath != SocketPathMarkerFiles.stableTmpPath)
    }

    @Test(arguments: [
        "",
        "com.cmuxterm.app",
        "com.cmuxterm.app.tunnel",
        "com.cmuxterm.cli",
        "com.apple.dt.xctest.tool"
    ])
    func cmuxAndToolIdentitiesKeepTheStableDefaults(_ bundleIdentifier: String) {
        #expect(SocketPathMarkerFiles.variant(bundleIdentifier: bundleIdentifier, environment: [:]) == .stable)
    }
}
