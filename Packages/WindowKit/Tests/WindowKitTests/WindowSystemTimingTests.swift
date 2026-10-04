import ApplicationServices
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

/// The timeouts a test's `setMessagingTimeout` was asked to set.
private final class TimeoutCalls {
    var made: [(element: AXUIElement, seconds: Float)] = []
}

extension WindowKitGlobalStateTests {
    /// `start()` sets the process-wide Accessibility timeout, which bounds Loop's own calls on elements it creates.
    @Suite
    @MainActor
    struct GlobalTimeoutTests {
        @Test func startBoundsEveryAccessibilityCall() {
            let calls = TimeoutCalls()
            let saved = WindowSystemTiming.setMessagingTimeout
            WindowSystemTiming.setMessagingTimeout = { element, seconds in
                calls.made.append((element, seconds))
                return .success
            }
            defer { WindowSystemTiming.setMessagingTimeout = saved }

            let kit = WindowKit()
            kit.start()
            kit.stop()
            #expect(calls.made.count == 1)
            #expect(calls.made.first?.seconds == 1.5)
            #expect(calls.made.first.map { CFEqual($0.element, AXUIElementCreateSystemWide()) } == true)
        }
    }
}
