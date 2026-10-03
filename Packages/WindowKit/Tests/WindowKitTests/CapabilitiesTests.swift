import Defaults
import Foundation
import Testing
@testable import WindowKit

extension WindowKitGlobalStateTests {
    @Suite
    @MainActor
    struct CapabilitiesTests {
        private let spaceIDs: Set<String> = Set(WindowDirection.spaceSwitching.map(\.rawValue))

        @Test func failedCapabilityHidesFeature() {
            let failing = Capabilities(loadSymbol: { _ in nil })
            #expect(!failing.windowIDLookup)
            #expect(!failing.skyLightMoves)
            #expect(!failing.stash)
            #expect(!failing.windowFocus)
            #expect(failing.hidden.isSuperset(of: ["LeftHalf", "Maximize", "NextScreen", "NextSpace", "Stash", "FocusLeft"]))

            let kit = WindowKit(capabilities: failing)
            defer { Capabilities.active = .live }
            let offered = WindowKit.menuActions(primary: false).map(\.id)
            #expect(failing.hidden.isDisjoint(with: offered))

            kit.start()
            for id in failing.hidden.sorted() {
                #expect(WindowKit.performableDirection(id) == nil)
                WindowKit.perform(id, onFrontmostOf: getpid())
            }
            kit.stop()
        }

        @Test func missingSpaceSymbolsHideOnlySpaceActions() {
            let caps = Capabilities(loadSymbol: { name in
                name.hasPrefix("OBJC_CLASS_$_SLSBridged") ? nil : Capabilities.liveSymbol(name)
            })
            #expect(caps.windowIDLookup)
            #expect(!caps.skyLightMoves)
            #expect(caps.hidden == spaceIDs)

            _ = WindowKit(capabilities: caps)
            defer { Capabilities.active = .live }
            let offered = Set(WindowKit.menuActions(primary: false).map(\.id))
            #expect(offered.isDisjoint(with: spaceIDs))
            #expect(offered.contains("TopHalf"))
            #expect(WindowKit.performableDirection("NextSpace") == nil)
            #expect(WindowKit.performableDirection("LeftHalf") == .leftHalf)
        }

        @Test func liveCapabilitiesHideNothing() {
            #expect(Capabilities.live.windowIDLookup)
            #expect(Capabilities.live.skyLightMoves)
            #expect(Capabilities.live.stash)
            #expect(Capabilities.live.windowFocus)
            #expect(Capabilities.live.hidden.isEmpty)
        }

        @Test func primaryActionsAreTheFiveInOrder() {
            Capabilities.active = .live
            let primary = WindowKit.menuActions(primary: true)
            #expect(primary.map(\.id) == ["LeftHalf", "RightHalf", "Maximize", "Center", "NextScreen"])
            #expect(primary.map(\.title) == ["Left Half", "Right Half", "Maximize", "Center", "Next Screen"])
        }

        @Test func secondaryActionsFollowLoopsGroups() {
            Capabilities.active = .live
            let primaryIDs = Set(WindowKit.menuActions(primary: true).map(\.id))
            let secondary = WindowKit.menuActions(primary: false)
            let ids = secondary.map(\.id)

            #expect(Set(ids).count == ids.count)
            #expect(primaryIDs.isDisjoint(with: ids))
            #expect(!ids.contains { $0.hasPrefix("Focus") || $0 == "Stash" || $0 == "Unstash" })
            #expect(ids.contains("TopHalf"))
            #expect(ids.contains("NextSpace"))
            #expect(ids.contains("Undo"))

            var groups: [String] = []
            for action in secondary where groups.last != action.group {
                groups.append(action.group)
            }
            #expect(groups == [
                "General", "Halves", "Quarters", "Horizontal Thirds", "Vertical Thirds", "Horizontal Fourths",
                "Screen Switching", "Space Switching", "Size Adjustment", "Shrink", "Grow", "Move", "Go Back"
            ])
        }

        @Test func keybindsStartWithTheTriggerKey() {
            let keybinds = WindowKit.keybinds()
            #expect(keybinds.first?.title == "Trigger Key")
            #expect(keybinds.first?.chord == WindowChord.format(Defaults[.triggerKey]))
            #expect(keybinds.count == 1 + Defaults[.keybinds].count { !$0.keybind.isEmpty })
        }

        @Test func chordFormatOrdersModifiersThenKeys() {
            #expect(WindowChord.format([.kVK_Function]) == "fn")
            #expect(WindowChord.format([.kVK_Function, .kVK_LeftArrow]) == "fn←")
            #expect(WindowChord.format([.kVK_UpArrow, .kVK_Function, .kVK_LeftArrow]) == "fn←↑")
            #expect(WindowChord.format([.kVK_Command, .kVK_Shift, .kVK_Option, .kVK_Control, .kVK_Space]) == "⌃⌥⇧⌘␣")
            #expect(WindowChord.format([.kVK_RightCommand, .kVK_ANSI_A]) == "⌘A")
        }
    }
}
