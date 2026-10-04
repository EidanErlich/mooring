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
        #expect(parsed.first { $0.name == "Screenshot" }?.chord == "⇧⌘4")
        #expect(parsed.first { $0.chord == "⌥⌘A" }?.name == "a macOS shortcut")
        #expect(parsed.count == 5, "an entry with no parameters is skipped")
    }

    @Test func unreadableDomainGivesNoHotkeys() {
        #expect(SystemHotkeys.read(from: [:]).isEmpty)
        #expect(SystemHotkeys.read(from: ["AppleSymbolicHotKeys": "nope"]).isEmpty)
        #expect(SystemHotkeys.read(from: ["AppleSymbolicHotKeys": ["64": "nope", "65": ["value": 3]]]).isEmpty)
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
