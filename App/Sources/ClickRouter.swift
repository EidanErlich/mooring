/// What a click on the menu-bar icon does (docs/SPEC.md, "Clicking the icon").
enum StatusClick: Equatable {
    case toggle
    case openMenu
}

enum ClickRouter {
    /// Left click toggles and right or Control-click opens the dropdown, unless the user swapped them.
    static func action(isRightMouse: Bool, controlDown: Bool, swapped: Bool) -> StatusClick {
        let secondary = isRightMouse || controlDown
        return secondary != swapped ? .openMenu : .toggle
    }
}
