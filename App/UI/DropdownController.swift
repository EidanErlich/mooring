import AppKit
import AwakeKit

/// Owns the one dropdown menu and opens it under the status item.
@MainActor
final class DropdownController {
    private let dropdownMenu: DropdownMenu

    init(engine: AwakeEngine, openSettings: @escaping () -> Void) {
        dropdownMenu = DropdownMenu(
            engine: engine, model: DropdownModel(),
            helperEnabled: { HelperClient.shared.status == .enabled },
            runningApps: DropdownMenu.regularApps, openSettings: openSettings
        )
    }

    func open(from controller: StatusItemController) {
        dropdownMenu.onClose = { [weak controller] in controller?.clearMenu() }
        controller.show(dropdownMenu.root)
    }
}
