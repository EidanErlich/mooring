import AppKit
import Defaults

extension UserDefaults {
    static let clipKitProductionSuiteName = "dev.mooring.clipboard"

    /// Under a test host, a scratch suite, so tests never touch the user's real Clipboard settings.
    static let clipKitSuiteName = TestHost.isActive ? "dev.mooring.clipboard.tests" : clipKitProductionSuiteName

    /// Maccy's settings live here, apart from Mooring's own `UserDefaults.standard`.
    static let clipKit = UserDefaults(suiteName: clipKitSuiteName)!
}

/// The Clipboard settings the app's Settings pages show, read from and written to ClipKit's suite.
public struct ClipSettings: Equatable, Sendable {
    public enum PopupPosition: String, CaseIterable, Sendable {
        case cursor, statusItem, window, center, lastPosition
    }

    public enum PinsPosition: String, CaseIterable, Sendable {
        case top, bottom
    }

    public enum SearchVisibility: String, CaseIterable, Sendable {
        case always, duringSearch, never
    }

    // History
    public var historySize: Int
    public var clearOnQuit: Bool
    public var pasteByDefault: Bool
    public var removeFormattingByDefault: Bool

    // Ignore rules
    public var ignoredApps: [String]
    public var ignoreAllAppsExceptListed: Bool
    public var ignoredTypes: Set<String>
    public var ignoreRegexes: [String]
    public var recordUniversalClipboard: Bool

    // Appearance
    public var popupPosition: PopupPosition
    public var pinsPosition: PinsPosition
    public var searchVisibility: SearchVisibility
    public var showPreview: Bool
    public var previewDelayMilliseconds: Int
    public var imageMaxHeight: Int
}

extension ClipKit {
    /// The current Clipboard settings. Reading them creates nothing.
    public static func settingsValues() -> ClipSettings {
        ClipSettings(
            historySize: Defaults[.size],
            clearOnQuit: Defaults[.clearOnQuit],
            pasteByDefault: Defaults[.pasteByDefault],
            removeFormattingByDefault: Defaults[.removeFormattingByDefault],
            ignoredApps: Defaults[.ignoredApps],
            ignoreAllAppsExceptListed: Defaults[.ignoreAllAppsExceptListed],
            ignoredTypes: Defaults[.ignoredPasteboardTypes],
            ignoreRegexes: Defaults[.ignoreRegexp],
            recordUniversalClipboard: Defaults[.recordUniversalClipboard],
            popupPosition: ClipSettings.PopupPosition(rawValue: Defaults[.popupPosition].rawValue) ?? .cursor,
            pinsPosition: Defaults[.pinTo] == .bottom ? .bottom : .top,
            searchVisibility: !Defaults[.showSearch] ? .never
                : Defaults[.searchVisibility] == .duringSearch ? .duringSearch : .always,
            showPreview: Defaults[.openPreviewAutomatically],
            previewDelayMilliseconds: Defaults[.previewDelay],
            imageMaxHeight: Defaults[.imageMaxHeight]
        )
    }

    /// Writes the settings that differ from the current ones.
    public static func setSettingsValues(_ values: ClipSettings) {
        let current = settingsValues()
        update(\.historySize, .size, from: current, to: values)
        update(\.clearOnQuit, .clearOnQuit, from: current, to: values)
        update(\.pasteByDefault, .pasteByDefault, from: current, to: values)
        update(\.removeFormattingByDefault, .removeFormattingByDefault, from: current, to: values)
        update(\.ignoredApps, .ignoredApps, from: current, to: values)
        update(\.ignoreAllAppsExceptListed, .ignoreAllAppsExceptListed, from: current, to: values)
        update(\.ignoredTypes, .ignoredPasteboardTypes, from: current, to: values)
        update(\.ignoreRegexes, .ignoreRegexp, from: current, to: values)
        update(\.recordUniversalClipboard, .recordUniversalClipboard, from: current, to: values)
        update(\.showPreview, .openPreviewAutomatically, from: current, to: values)
        update(\.previewDelayMilliseconds, .previewDelay, from: current, to: values)
        update(\.imageMaxHeight, .imageMaxHeight, from: current, to: values)

        if values.popupPosition != current.popupPosition, let position = PopupPosition(rawValue: values.popupPosition.rawValue) {
            Defaults[.popupPosition] = position
        }
        if values.pinsPosition != current.pinsPosition {
            Defaults[.pinTo] = values.pinsPosition == .bottom ? .bottom : .top
        }
        if values.searchVisibility != current.searchVisibility {
            Defaults[.showSearch] = values.searchVisibility != .never
            Defaults[.searchVisibility] = values.searchVisibility == .duringSearch ? .duringSearch : .always
        }
    }

    private static func update<Value: Equatable & Defaults.Serializable>(
        _ path: KeyPath<ClipSettings, Value>,
        _ key: Defaults.Key<Value>,
        from current: ClipSettings,
        to values: ClipSettings
    ) {
        if values[keyPath: path] != current[keyPath: path] {
            Defaults[key] = values[keyPath: path]
        }
    }
}
