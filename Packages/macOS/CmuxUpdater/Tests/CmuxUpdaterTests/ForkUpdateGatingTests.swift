import Testing
@testable import CmuxUpdater

/// A rebranded fork built from this source must never consult the public
/// cmux appcast, or a public update would replace it with the official app.
@MainActor
@Suite struct ForkUpdateGatingTests {
    @Test(arguments: [
        "io.github.lous.cmux-flow",
        "dev.example.terminal",
        "com.cmuxterm.app.debug",
        "com.cmuxterm.app.staging.my-tag"
    ])
    func keepsForksAndLocalBuildsOffTheReleaseTrain(_ bundleIdentifier: String) {
        #expect(UpdateController.isOffReleaseTrainBundleIdentifier(bundleIdentifier))
    }

    @Test(arguments: [
        "com.cmuxterm.app",
        "com.cmuxterm.app.nightly",
        "com.cmuxterm.app.rc"
    ])
    func keepsShippingChannelsOnTheReleaseTrain(_ bundleIdentifier: String) {
        #expect(!UpdateController.isOffReleaseTrainBundleIdentifier(bundleIdentifier))
    }

    @Test func treatsMissingIdentityAsShipping() {
        #expect(!UpdateController.isOffReleaseTrainBundleIdentifier(nil))
        #expect(!UpdateController.isOffReleaseTrainBundleIdentifier("  "))
    }
}
