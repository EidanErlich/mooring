import Foundation
import Testing
@testable import Mooring

/// The license files the "Bundle license notices" build phase puts in the app, and the Advanced page's button.
struct AcknowledgementsTests {
    /// The repo root: App/Tests/<this file> is two levels below it.
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func notices() throws -> String {
        let url = try #require(Acknowledgements.noticesURL())
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func noticesAreInTheBuiltApp() throws {
        let url = try #require(Acknowledgements.noticesURL())
        #expect(url.path.hasSuffix("/Contents/Resources/THIRD_PARTY_NOTICES.md"))
        #expect(url.path.contains(".app/"))
    }

    @Test func licenseIsInTheBuiltAppUnchanged() throws {
        let url = try #require(Acknowledgements.licenseURL())
        #expect(url.path.hasSuffix("/Contents/Resources/LICENSE"))
        #expect(try Data(contentsOf: url) == Data(contentsOf: root.appendingPathComponent("LICENSE")))
    }

    @Test func noticesCoverEveryVendoredProject() throws {
        let text = try notices()
        let vendored = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("THIRD_PARTY").path)
            .filter { !$0.hasPrefix(".") }
        #expect(Set(vendored).isSuperset(of: ["Loop", "Maccy", "Awayke"]))
        for name in vendored {
            #expect(text.contains("\n### \(name)\n"), "\(name) is missing")
        }
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Permission is hereby granted, free of charge"))
    }

    @Test func noticesCoverEveryPinnedPackage() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("Config/Package.resolved"))
        let resolved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(resolved["pins"] as? [[String: Any]])
        #expect(pins.count >= 10)
        let text = try notices()
        for pin in pins {
            let location = try #require(pin["location"] as? String)
            let name = URL(string: location)?.deletingPathExtension().lastPathComponent ?? location
            #expect(text.contains("\n### \(name)\n"), "\(name) is missing")
            #expect(text.contains("- Source: \(location),"), "\(location) is missing")
        }
        for name in ["Luminare", "Scribe", "Subsurface", "swift-log", "Defaults", "KeyboardShortcuts", "Sauce",
                     "fuse-swift", "SwiftHEXColors", "Sparkle"] {
            #expect(text.contains("\n### \(name)\n"), "\(name) is missing")
        }
    }

    @MainActor
    @Test func advancedPageHasTheButtonBeforeUninstall() throws {
        let sections = AdvancedSettingsPage.sections(updates: nil)
        let acknowledgements = try #require(sections.firstIndex(of: .acknowledgements))
        let uninstall = try #require(sections.firstIndex(of: .uninstall))
        #expect(acknowledgements < uninstall)
        #expect(Acknowledgements.buttonTitle == "Acknowledgements…")
    }
}
