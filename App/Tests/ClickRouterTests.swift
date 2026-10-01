import Testing
@testable import Mooring

struct ClickRouterTests {
    @Test func leftClickToggles() {
        #expect(ClickRouter.action(isRightMouse: false, controlDown: false, swapped: false) == .toggle)
    }

    @Test func rightOrControlClickOpensPanel() {
        #expect(ClickRouter.action(isRightMouse: true, controlDown: false, swapped: false) == .openMenu)
        #expect(ClickRouter.action(isRightMouse: false, controlDown: true, swapped: false) == .openMenu)
    }

    @Test func swappingFlipsBoth() {
        #expect(ClickRouter.action(isRightMouse: false, controlDown: false, swapped: true) == .openMenu)
        #expect(ClickRouter.action(isRightMouse: true, controlDown: false, swapped: true) == .toggle)
    }
}
