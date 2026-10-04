import Testing
@testable import WindowKit

/// Region names for agent arrangements: SPEC's spelling ("right-half", "top-left"), with Loop's raw values accepted too.
struct WindowRegionTests {
    @Test func namesAreKebabCaseWithShortQuarters() {
        #expect(WindowRegion.name(for: .leftHalf) == "left-half")
        #expect(WindowRegion.name(for: .almostMaximize) == "almost-maximize")
        #expect(WindowRegion.name(for: .topLeftQuarter) == "top-left")
        #expect(WindowRegion.name(for: .bottomRightQuarter) == "bottom-right")
        #expect(WindowRegion.name(for: .rightTwoThirds) == "right-two-thirds")
        #expect(WindowRegion.name(for: .macOSCenter) == "mac-os-center")
        #expect(WindowRegion.name(for: .maximize) == "maximize")
    }

    @Test func everyDirectionHasADistinctName() {
        let names = WindowDirection.allCases.map(WindowRegion.name(for:))
        #expect(Set(names).count == names.count)
    }

    @Test func lookupIgnoresCaseAndPunctuation() {
        let directions = WindowDirection.allCases
        for name in ["left-half", "LeftHalf", "left_half", "Left Half"] {
            #expect(WindowRegion.direction(named: name, among: directions) == .leftHalf)
        }
        for name in ["top-left", "top-left-quarter", "TopLeftQuarter"] {
            #expect(WindowRegion.direction(named: name, among: directions) == .topLeftQuarter)
        }
        #expect(WindowRegion.direction(named: "center", among: directions) == .center)
    }

    @Test func lookupOnlyFindsGivenDirections() {
        #expect(WindowRegion.direction(named: "stash", among: [.leftHalf]) == nil)
        #expect(WindowRegion.direction(named: "nowhere", among: WindowDirection.allCases) == nil)
        #expect(WindowRegion.direction(named: "--", among: WindowDirection.allCases) == nil)
    }
}

extension WindowKitGlobalStateTests {
    /// Agents get only regions that set a window's frame, which `win.undo` can put back.
    @Suite
    @MainActor
    struct AgentRegionTests {
        static let excluded: [WindowDirection] = [
            .minimize, .minimizeOthers, .hide, .fullscreen, .nextSpace, .previousSpace, .undo, .initialFrame,
            .focusUp, .focusDown, .focusLeft, .focusRight, .focusNextInStack, .stash, .unstash, .cycle, .custom
        ] + WindowDirection.spaceSwitching

        @Test func offeredRegionsAreFrameOnly() {
            Capabilities.active = .live
            let offered = WindowRegion.offered
            for direction in Self.excluded {
                #expect(!offered.contains(direction), "\(direction) is offered")
            }
            for direction in [WindowDirection.leftHalf, .topLeftQuarter, .rightTwoThirds, .firstFourth, .maximize,
                              .almostMaximize, .center, .larger, .growLeft, .moveUp, .nextScreen] {
                #expect(offered.contains(direction), "\(direction) isn't offered")
            }
        }

        @Test func excludedNamesAreWithheld() {
            for name in ["minimize-others", "MinimizeOthers", "hide", "fullscreen", "next-space", "undo", "initial-frame",
                         "stash", "focus-left", "cycle"] {
                #expect(WindowRegion.isWithheld(name), "\(name)")
            }
            for name in ["left-half", "maximize", "next-screen", "sideways", ""] {
                #expect(!WindowRegion.isWithheld(name), "\(name)")
            }
        }
    }
}
