import AppKit
import SwiftUI

// MARK: Hosted rows

/// SwiftUI rows hosted in menu items, for the dropdown and its Windows and Clipboard submenus.
extension DropdownMenu {
    /// `title` is the row's visible text, for VoiceOver and tests; the hosted view draws the row.
    static func hostedItem(id: String, title: String, enabled: Bool = true,
                           @ViewBuilder _ content: @escaping () -> some View) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = enabled
        item.identifier = NSUserInterfaceItemIdentifier(id)
        let host = NSHostingView(rootView: LiveContent(content: content).frame(width: width, alignment: .leading))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        item.view = host
        setTitle(title, of: item)
        return item
    }

    /// Sets a hosted row's title and its view's accessibility label, which VoiceOver reads.
    static func setTitle(_ title: String, of item: NSMenuItem) {
        guard item.title != title else { return }
        item.title = title
        item.view?.setAccessibilityLabel(title)
    }
}

/// Evaluates its content in its own body, so reads of observable state are tracked per row.
private struct LiveContent<Content: View>: View {
    let content: () -> Content

    var body: some View {
        content()
    }
}
