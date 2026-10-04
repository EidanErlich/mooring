import CoreGraphics
import Defaults
import Testing
@testable import WindowKit

extension WindowKitGlobalStateTests {
/// Target frames from Loop's resolver, with injected screen bounds (CoreGraphics coordinates, no padding).
@Suite
@MainActor
struct FrameMathTests {
    private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)

    private func frame(_ direction: WindowDirection, in bounds: CGRect) -> CGRect {
        WindowFrameResolver.getFrame(for: WindowAction(direction), bounds: bounds, padding: .zero)
    }

    private func frame(_ direction: WindowDirection, from window: CGRect, in bounds: CGRect) -> CGRect {
        let context = ResizeContext(initialFrame: window, bounds: bounds, padding: .zero, action: WindowAction(direction))
        return WindowFrameResolver.getFrame(resizeContext: context).frame
    }

    @Test func primaryActionsOnOneScreen() {
        #expect(frame(.leftHalf, in: main) == CGRect(x: 0, y: 0, width: 756, height: 982))
        #expect(frame(.rightHalf, in: main) == CGRect(x: 756, y: 0, width: 756, height: 982))
        #expect(frame(.maximize, in: main) == main)
        #expect(frame(.center, in: main) == CGRect(x: 378, y: 245.5, width: 756, height: 491))
    }

    @Test func primaryActionsOnTheLeftScreen() {
        #expect(frame(.leftHalf, in: left) == CGRect(x: -1920, y: 0, width: 960, height: 1080))
        #expect(frame(.rightHalf, in: left) == CGRect(x: -960, y: 0, width: 960, height: 1080))
        #expect(frame(.maximize, in: left) == left)
        #expect(frame(.center, in: left) == CGRect(x: -1440, y: 270, width: 960, height: 540))
    }

    @Test func quarters() {
        #expect(frame(.topLeftQuarter, in: main) == CGRect(x: 0, y: 0, width: 756, height: 491))
        #expect(frame(.topRightQuarter, in: main) == CGRect(x: 756, y: 0, width: 756, height: 491))
        #expect(frame(.bottomLeftQuarter, in: main) == CGRect(x: 0, y: 491, width: 756, height: 491))
        #expect(frame(.bottomRightQuarter, in: main) == CGRect(x: 756, y: 491, width: 756, height: 491))
        #expect(frame(.bottomRightQuarter, in: left) == CGRect(x: -960, y: 540, width: 960, height: 540))
    }

    @Test func thirdsAndTwoThirds() {
        #expect(frame(.leftThird, in: main) == CGRect(x: 0, y: 0, width: 504, height: 982))
        #expect(frame(.horizontalCenterThird, in: main) == CGRect(x: 504, y: 0, width: 504, height: 982))
        #expect(frame(.rightThird, in: main) == CGRect(x: 1008, y: 0, width: 504, height: 982))
        #expect(frame(.leftTwoThirds, in: main) == CGRect(x: 0, y: 0, width: 1008, height: 982))
        #expect(frame(.rightTwoThirds, in: main) == CGRect(x: 504, y: 0, width: 1008, height: 982))

        #expect(frame(.topThird, in: left) == CGRect(x: -1920, y: 0, width: 1920, height: 360))
        #expect(frame(.verticalCenterThird, in: left) == CGRect(x: -1920, y: 360, width: 1920, height: 360))
        #expect(frame(.bottomThird, in: left) == CGRect(x: -1920, y: 720, width: 1920, height: 360))
        #expect(frame(.topTwoThirds, in: left) == CGRect(x: -1920, y: 0, width: 1920, height: 720))
        #expect(frame(.bottomTwoThirds, in: left) == CGRect(x: -1920, y: 360, width: 1920, height: 720))
    }

    @Test func almostMaximize() {
        #expect(frame(.almostMaximize, in: left) == CGRect(x: -1824, y: 54, width: 1728, height: 972))
    }

    @Test func growShrinkLargerSmaller() {
        resetScratchWindowsSuite()
        defer { resetScratchWindowsSuite() }
        Defaults[.sizeIncrement] = 20
        Defaults[.previewPadding] = 10
        let window = CGRect(x: 300, y: 200, width: 600, height: 400)

        #expect(frame(.growRight, from: window, in: main) == CGRect(x: 300, y: 200, width: 620, height: 400))
        #expect(frame(.growLeft, from: window, in: main) == CGRect(x: 280, y: 200, width: 620, height: 400))
        #expect(frame(.growTop, from: window, in: main) == CGRect(x: 300, y: 180, width: 600, height: 420))
        #expect(frame(.growBottom, from: window, in: main) == CGRect(x: 300, y: 200, width: 600, height: 420))
        #expect(frame(.shrinkRight, from: window, in: main) == CGRect(x: 300, y: 200, width: 580, height: 400))
        #expect(frame(.shrinkLeft, from: window, in: main) == CGRect(x: 320, y: 200, width: 580, height: 400))
        #expect(frame(.larger, from: window, in: main) == CGRect(x: 280, y: 180, width: 640, height: 440))
        #expect(frame(.smaller, from: window, in: main) == CGRect(x: 320, y: 220, width: 560, height: 360))
    }

    @Test func growStopsAtTheScreenEdge() {
        let window = CGRect(x: 756, y: 0, width: 756, height: 982)
        #expect(frame(.growRight, from: window, in: main) == window)
    }

    @Test func nextAndPreviousScreenOnOneScreenKeepTheFrame() {
        let window = CGRect(x: 0, y: 0, width: 756, height: 982)
        #expect(ScreenSwitchFrames.frame(for: .nextScreen, window: window, screen: main, screens: [main]) == window)
        #expect(ScreenSwitchFrames.frame(for: .previousScreen, window: window, screen: main, screens: [main]) == window)
    }

    @Test func nextAndPreviousScreenAcrossTwoScreens() {
        let screens = [main, left]
        let leftHalfOfMain = CGRect(x: 0, y: 0, width: 756, height: 982)
        let leftHalfOfLeft = CGRect(x: -1920, y: 0, width: 960, height: 1080)
        let centredOnLeft = CGRect(x: -1440, y: 270, width: 960, height: 540)
        let centredOnMain = CGRect(x: 378, y: 245.5, width: 756, height: 491)

        #expect(ScreenSwitchFrames.frame(for: .nextScreen, window: leftHalfOfMain, screen: main, screens: screens)
            == leftHalfOfLeft)
        #expect(ScreenSwitchFrames.frame(for: .previousScreen, window: leftHalfOfMain, screen: main, screens: screens)
            == leftHalfOfLeft)
        #expect(ScreenSwitchFrames.frame(for: .nextScreen, window: centredOnLeft, screen: left, screens: screens)
            == centredOnMain)
        #expect(ScreenSwitchFrames.frame(for: .previousScreen, window: centredOnLeft, screen: left, screens: screens)
            == centredOnMain)
    }

    @Test func screensAreOrderedLeftToRight() {
        #expect(ScreenUtility.next(from: left, in: [main, left], frame: { $0 }) == main)
        #expect(ScreenUtility.next(from: main, in: [main, left], frame: { $0 }) == left)
        #expect(ScreenUtility.next(from: main, in: [main, left], frame: { $0 }, canRestartCycle: false) == nil)
        #expect(ScreenUtility.previous(from: left, in: [main, left], frame: { $0 }) == main)
        #expect(ScreenUtility.previous(from: main, in: [main, left], frame: { $0 }) == left)
    }

    @Test func cycleStepsThroughItsActionsAndWraps() throws {
        let cycle = WindowAction(
            cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)],
            keybind: [.kVK_LeftArrow]
        )
        let context = ResizeContext(bounds: main, padding: .zero)
        var frames: [CGRect] = []

        for _ in 0..<4 {
            let proposal = try #require(context.proposeCycleAction(
                in: cycle,
                restartAtBeginningWhenInterrupted: false,
                mode: .advance(.forward)
            ))
            let child = try #require(context.commitCycleAction(proposal, in: cycle))
            context.setAction(to: child, parent: cycle)
            frames.append(context.getTargetFrame().raw)
        }

        #expect(frames == [
            CGRect(x: 0, y: 0, width: 756, height: 982),
            CGRect(x: 0, y: 0, width: 504, height: 982),
            CGRect(x: 0, y: 0, width: 1008, height: 982),
            CGRect(x: 0, y: 0, width: 756, height: 982)
        ])
    }
}
}
