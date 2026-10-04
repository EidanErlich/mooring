import Testing
@testable import Mooring

struct SystemHotkeysTests {
    private func hotkey(_ enabled: Bool, _ parameters: [Int]) -> [String: Any] {
        ["enabled": enabled, "value": ["parameters": parameters, "type": "standard"]]
    }

    @Test func parsesSymbolicHotkeysDictionary() {
        let domain: [String: Any] = [
            "AppleSymbolicHotKeys": [
                "64": hotkey(true, [32, 49, 1_048_576]),
                "61": hotkey(false, [32, 49, 786_432]),
                "32": hotkey(true, [65535, 126, 8_650_752]),
                "30": hotkey(true, [52, 21, 1_179_648]),
                "999": hotkey(true, [97, 0, 1_572_864]),
                "70": ["enabled": true]
            ]
        ]
        let parsed = SystemHotkeys.read(from: domain)
        #expect(parsed.first { $0.name == "Spotlight" } == SystemHotkey(name: "Spotlight", chord: "⌘␣", enabled: true))
        #expect(parsed.first { $0.chord == "⌃⌥␣" } == SystemHotkey(
            name: "Select next source in Input menu", chord: "⌃⌥␣", enabled: false))
        #expect(parsed.first { $0.name == "Mission Control" }?.chord == "⌃↑")
        #expect(parsed.contains(SystemHotkey(name: "Screenshot", chord: "⇧⌘4", enabled: true)))
        #expect(parsed.first { $0.chord == "⌥⌘A" }?.name == "a macOS shortcut")
        #expect(parsed.filter { $0.name == "a macOS shortcut" }.count == 1, "an unknown id with no parameters is skipped")
    }

    @Test func unreadableDomainGivesNoHotkeys() {
        #expect(SystemHotkeys.read(from: ["AppleSymbolicHotKeys": "nope"]).isEmpty)
        let malformed = SystemHotkeys.read(from: ["AppleSymbolicHotKeys": ["64": "nope", "65": ["value": 3]]])
        #expect(!malformed.contains { $0.name == "Spotlight" || $0.name == "Finder search window" })
    }

    /// macOS writes an entry only after a shortcut is changed, so a stock Mac's plist lacks most ids.
    @Test func absentIdsGetTheirDefaults() {
        let stock = SystemHotkeys.read(from: [:])
        #expect(stock.allSatisfy { $0.enabled })
        #expect(Set(stock.map(\.chord)).isSuperset(of: ["⌘␣", "⌥⌘␣", "⌃↑", "⌃↓", "F11", "⌃␣", "⌃⌥␣", "⇧⌘3", "⌃⇧⌘3", "⇧⌘4", "⌃⇧⌘4", "⇧⌘5"]))
        #expect(stock.first { $0.name == "Spotlight" }?.chord == "⌘␣")
        #expect(SystemHotkeys.read(from: ["AppleSymbolicHotKeys": [String: Any]()]) == stock)
    }

    @Test func disabledEntrySuppressesDefault() {
        let domain: [String: Any] = ["AppleSymbolicHotKeys": ["64": ["enabled": false]]]
        #expect(!SystemHotkeys.read(from: domain).contains { $0.name == "Spotlight" })
        let valueless: [String: Any] = ["AppleSymbolicHotKeys": ["64": ["enabled": true]]]
        #expect(SystemHotkeys.read(from: valueless).first { $0.name == "Spotlight" }?.chord == "⌘␣")
    }

    @Test func customValueOverridesDefault() {
        let domain: [String: Any] = ["AppleSymbolicHotKeys": ["64": hotkey(true, [32, 49, 1_310_720])]]
        let spotlight = SystemHotkeys.read(from: domain).filter { $0.name == "Spotlight" }
        #expect(spotlight == [SystemHotkey(name: "Spotlight", chord: "⌃⌘␣", enabled: true)])
    }

    @Test func namesTheCommonIds() {
        let names = [64: "Spotlight", 32: "Mission Control", 36: "Show Desktop", 60: "Select the previous input source",
                     61: "Select next source in Input menu", 28: "Screenshot", 31: "Screenshot", 33: "Application windows",
                     5: "a macOS shortcut"]
        for (id, name) in names {
            #expect(SystemHotkeys.name(forID: id) == name, "id \(id)")
        }
    }
}
