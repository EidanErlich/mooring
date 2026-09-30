import AppKit
import AwakeKit
import SwiftUI

/// Owns the one dropdown panel and opens it under the status item.
@MainActor
final class DropdownController {
    private let model = DropdownModel()
    private let panel: FloatingPanel<DropdownView>

    init(engine: AwakeEngine, openSettings: @escaping () -> Void) {
        let model = model
        var close: () -> Void = {}
        panel = FloatingPanel(onClose: { model.didClose() }, content: {
            DropdownView(engine: engine, model: model, openSettings: { close(); openSettings() })
        })
        close = { [weak panel] in panel?.close() }
    }

    func toggle(below button: NSStatusBarButton) {
        if panel.isPresented {
            panel.close()
            return
        }
        let visibleFrame = button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        model.didOpen(maxHeight: PanelPlacement.maxHeight(in: visibleFrame))
        panel.open(below: button)
    }
}
