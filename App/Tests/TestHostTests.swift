import Testing
@testable import Mooring

struct TestHostTests {
    /// When Xcode launches the app only to host tests, it must not start the engine,
    /// which would read and write the user's real ~/Library/Application Support/Mooring.
    @Test func appKnowsItIsHostingTests() {
        #expect(AppDelegate.isHostingTests)
    }
}
