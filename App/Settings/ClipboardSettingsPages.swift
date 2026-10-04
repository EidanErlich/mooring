import ClipKit
import SwiftUI

/// What a Clipboard settings page shows.
enum ClipboardPageContent: Equatable {
    /// Only the "Clipboard is off" banner: no ClipKit settings are read and no ClipKit view is built.
    case offBanner
    case page(SettingsPage)
}

extension SettingsPage {
    var isClipboardPage: Bool {
        switch self {
        case .clipboardHistory, .clipboardIgnoreRules, .clipboardAppearance: true
        default: false
        }
    }

    /// History carries the Clipboard switch at the top, in every state.
    var hasClipboardToggle: Bool {
        self == .clipboardHistory
    }

    /// The page once Clipboard is on; the off banner alone otherwise. Nil for pages outside the group.
    func clipboardContent(isOn: Bool) -> ClipboardPageContent? {
        guard isClipboardPage else { return nil }
        return isOn ? .page(self) : .offBanner
    }
}

/// Where the pages read and write ClipKit's settings. Tests swap it for an in-memory copy.
struct ClipboardSettingsAccess {
    var read: @MainActor () -> ClipSettings = { ClipKit.settingsValues() }
    var write: @MainActor (ClipSettings) -> Void = { ClipKit.setSettingsValues($0) }
}

/// The settings a Clipboard page edits. Each change is written as it's made.
@MainActor @Observable
final class ClipboardSettingsModel {
    static let historySizeRange = 10...999
    static let imageHeightRange = 1...200

    private(set) var values: ClipSettings
    @ObservationIgnored private let access: ClipboardSettingsAccess

    init(access: ClipboardSettingsAccess) {
        self.access = access
        values = access.read()
    }

    func binding<Value>(_ path: WritableKeyPath<ClipSettings, Value>) -> Binding<Value> {
        Binding(get: { self.values[keyPath: path] }, set: { newValue in self.update { $0[keyPath: path] = newValue } })
    }

    func update(_ change: (inout ClipSettings) -> Void) {
        var next = values
        change(&next)
        next.historySize = next.historySize.clamped(to: Self.historySizeRange)
        next.imageMaxHeight = next.imageMaxHeight.clamped(to: Self.imageHeightRange)
        guard next != values else { return }
        values = next
        access.write(next)
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// "Clipboard": on turns Clipboard on, off turns it off.
struct ClipboardToggle: View {
    static let title = "Clipboard"

    let clipboard: ClipboardController

    static func isOn(_ clipboard: ClipboardController) -> Binding<Bool> {
        Binding(get: { clipboard.isOn }, set: { $0 ? clipboard.turnOn() : clipboard.turnOff() })
    }

    var body: some View {
        HStack {
            Text(Self.title)
            Spacer()
            Toggle(Self.title, isOn: Self.isOn(clipboard))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// One page of Settings → Clipboard. While Clipboard is off it is the banner alone.
struct ClipboardSettingsPage: View {
    static let offTitle = "Clipboard is off"

    let page: SettingsPage
    let clipboard: ClipboardController
    var access = ClipboardSettingsAccess()
    /// Picks an app to ignore and returns its bundle id; tests inject an answer.
    var chooseApp: @MainActor () -> String? = IgnoredAppPicker.choose
    /// The popup hotkey's recorder; built only while Clipboard is on.
    var recorder: @MainActor () -> AnyView = { AnyView(KeyboardShortcuts.Recorder(for: ClipKit.popupShortcutName)) }

    var body: some View {
        VStack(spacing: 0) {
            if page.hasClipboardToggle {
                ClipboardToggle(clipboard: clipboard)
                Divider()
            }
            switch page.clipboardContent(isOn: clipboard.isOn) {
            case .offBanner:
                WindowsPageBanner(title: Self.offTitle, turnOn: clipboard.turnOn)
            case .page(let page):
                ClipboardOnPage(page: page, access: access, chooseApp: chooseApp, recorder: recorder)
            case nil:
                EmptyView()
            }
        }
        .navigationTitle(page.title)
    }
}

/// A page while Clipboard is on. It reads ClipKit's settings once, when it appears.
private struct ClipboardOnPage: View {
    let page: SettingsPage
    let chooseApp: @MainActor () -> String?
    let recorder: @MainActor () -> AnyView
    @State private var model: ClipboardSettingsModel

    init(page: SettingsPage, access: ClipboardSettingsAccess, chooseApp: @escaping @MainActor () -> String?,
         recorder: @escaping @MainActor () -> AnyView) {
        self.page = page
        self.chooseApp = chooseApp
        self.recorder = recorder
        _model = State(initialValue: ClipboardSettingsModel(access: access))
    }

    var body: some View {
        switch page {
        case .clipboardHistory: historyForm
        case .clipboardIgnoreRules: IgnoreRulesForm(model: model, chooseApp: chooseApp)
        default: AppearanceForm(model: model)
        }
    }

    private var historyForm: some View {
        Form {
            Section {
                Stepper(value: model.binding(\.historySize), in: ClipboardSettingsModel.historySizeRange) {
                    LabeledContent("History size") { Text("\(model.values.historySize)").monospacedDigit() }
                }
                Toggle("Clear history on quit", isOn: model.binding(\.clearOnQuit))
            }
            Section {
                Toggle("Paste automatically", isOn: model.binding(\.pasteByDefault))
                Toggle("Paste without formatting", isOn: model.binding(\.removeFormattingByDefault))
            }
            Section {
                LabeledContent("Clipboard popup") { recorder() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceForm: View {
    let model: ClipboardSettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Popup position", selection: model.binding(\.popupPosition)) {
                    ForEach(ClipSettings.PopupPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Pinned items", selection: model.binding(\.pinsPosition)) {
                    ForEach(ClipSettings.PinsPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Search field", selection: model.binding(\.searchVisibility)) {
                    ForEach(ClipSettings.SearchVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                Toggle("Show preview", isOn: model.binding(\.showPreview))
                Stepper(value: model.binding(\.imageMaxHeight), in: ClipboardSettingsModel.imageHeightRange) {
                    LabeledContent("Image height") { Text("\(model.values.imageMaxHeight) pt").monospacedDigit() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension ClipSettings.PopupPosition {
    var title: String {
        switch self {
        case .cursor: "At the cursor"
        case .statusItem: "Under the menu bar icon"
        case .window: "In the active window"
        case .center: "In the center of the screen"
        case .lastPosition: "Where it was last"
        }
    }
}

extension ClipSettings.PinsPosition {
    var title: String {
        switch self {
        case .top: "At the top"
        case .bottom: "At the bottom"
        }
    }
}

extension ClipSettings.SearchVisibility {
    var title: String {
        switch self {
        case .always: "Always shown"
        case .duringSearch: "Only while searching"
        case .never: "Hidden"
        }
    }
}
