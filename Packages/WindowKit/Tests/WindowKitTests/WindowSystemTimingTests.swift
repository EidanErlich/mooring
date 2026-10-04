import Testing
@testable import WindowKit

/// `LiveWindowSystem` needs Accessibility, so only its bounds are pinned here.
struct WindowSystemTimingTests {
    /// Accessibility calls run on the main actor: each must give up well before the system's 6 s default.
    @Test func accessibilityCallsAreBounded() {
        #expect(WindowSystemTiming.axTimeout == 1.5)
    }

    @Test func waitsStayShort() {
        #expect(WindowSystemTiming.unhideDelay == .milliseconds(150))
        #expect(WindowSystemTiming.restoreDelay == .milliseconds(350))
        #expect(WindowSystemTiming.previewDuration == .milliseconds(600))
    }
}
