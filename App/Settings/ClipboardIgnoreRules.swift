import AppKit
import ClipKit
import SwiftUI
import UniformTypeIdentifiers

extension ClipboardSettingsModel {
    /// Asks `choose` for an app's bundle id and ignores it, unless it's cancelled or already listed.
    func addIgnoredApp(choosing choose: @MainActor () -> String?) {
        guard let bundleID = choose(), !values.ignoredApps.contains(bundleID) else { return }
        update { $0.ignoredApps.append(bundleID) }
    }

    func removeIgnoredApp(_ bundleID: String) {
        update { $0.ignoredApps.removeAll { $0 == bundleID } }
    }

    var sortedIgnoredTypes: [String] {
        values.ignoredTypes.sorted()
    }

    func addIgnoredType(_ type: String) {
        let type = type.trimmingCharacters(in: .whitespaces)
        guard !type.isEmpty else { return }
        update { $0.ignoredTypes.insert(type) }
    }

    func removeIgnoredType(_ type: String) {
        update { $0.ignoredTypes.remove(type) }
    }

    /// Adds a pattern; false when it isn't a valid regular expression. Blank and repeated patterns are skipped.
    @discardableResult
    func addIgnoreRegex(_ pattern: String) -> Bool {
        let pattern = pattern.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty, !values.ignoreRegexes.contains(pattern) else { return true }
        guard (try? NSRegularExpression(pattern: pattern)) != nil else { return false }
        update { $0.ignoreRegexes.append(pattern) }
        return true
    }

    func removeIgnoreRegex(_ pattern: String) {
        update { $0.ignoreRegexes.removeAll { $0 == pattern } }
    }
}

/// The app picker behind the ignored-apps "+": an open panel limited to `.app` files in /Applications.
enum IgnoredAppPicker {
    static func configure(_ panel: NSOpenPanel) {
        panel.directoryURL = URL(filePath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an app whose copies Clipboard should ignore"
    }

    /// The chosen app's bundle id; nil when cancelled or the app has none.
    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        configure(panel)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }

    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// The app's name, or its bundle id when it isn't installed.
    static func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path(percentEncoded: false))
            .replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for bundleID: String) -> NSImage? {
        url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
    }
}

struct IgnoreRulesForm: View {
    let model: ClipboardSettingsModel
    let chooseApp: @MainActor () -> String?
    @State private var newType = ""
    @State private var newRegex = ""
    @State private var regexError = false

    var body: some View {
        Form {
            Section("Ignored apps") {
                ForEach(model.values.ignoredApps, id: \.self) { bundleID in
                    HStack {
                        if let icon = IgnoredAppPicker.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(IgnoredAppPicker.name(for: bundleID))
                        Spacer()
                        removeButton("Remove \(IgnoredAppPicker.name(for: bundleID))") { model.removeIgnoredApp(bundleID) }
                    }
                }
                Button("Add App…") { model.addIgnoredApp(choosing: chooseApp) }
            }
            Section("Ignored types") {
                ForEach(model.sortedIgnoredTypes, id: \.self) { type in
                    HStack {
                        Text(type).font(.system(.body, design: .monospaced))
                        Spacer()
                        removeButton("Remove \(type)") { model.removeIgnoredType(type) }
                    }
                }
                HStack {
                    TextField("Pasteboard type", text: $newType).onSubmit(addType)
                    Button("Add", action: addType).disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section("Ignored patterns") {
                ForEach(model.values.ignoreRegexes, id: \.self) { pattern in
                    HStack {
                        Text(pattern).font(.system(.body, design: .monospaced))
                        Spacer()
                        removeButton("Remove \(pattern)") { model.removeIgnoreRegex(pattern) }
                    }
                }
                HStack {
                    TextField("Regular expression", text: $newRegex).onSubmit(addRegex)
                    Button("Add", action: addRegex).disabled(newRegex.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if regexError {
                    Text("That isn't a valid regular expression.").font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Toggle("Record copies from your other devices (Universal Clipboard)",
                       isOn: model.binding(\.recordUniversalClipboard))
            }
        }
        .formStyle(.grouped)
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text("−").frame(width: 16) }
            .buttonStyle(.borderless)
            .accessibilityLabel(label)
    }

    private func addType() {
        model.addIgnoredType(newType)
        newType = ""
    }

    private func addRegex() {
        regexError = !model.addIgnoreRegex(newRegex)
        if !regexError { newRegex = "" }
    }
}
