import Testing
@testable import Mooring

struct ClickRouterTests {
    @Test func leftClickToggles() {
        #expect(ClickRouter.action(isRightMouse: false, controlDown: false, swapped: false) == .toggle)
    }

    @Test func rightOrControlClickOpensPanel() {
        #expect(ClickRouter.action(isRightMouse: true, controlDown: false, swapped: false) == .openPanel)
        #expect(ClickRouter.action(isRightMouse: false, controlDown: true, swapped: false) == .openPanel)
    }

    @Test func swappingFlipsBoth() {
        #expect(ClickRouter.action(isRightMouse: false, controlDown: false, swapped: true) == .openPanel)
        #expect(ClickRouter.action(isRightMouse: true, controlDown: false, swapped: true) == .toggle)
    }
}
