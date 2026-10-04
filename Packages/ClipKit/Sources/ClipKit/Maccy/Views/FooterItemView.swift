// Adapted from Maccy@c376789: Maccy/Views/FooterItemView.swift
import SwiftUI

struct FooterItemView: View {
  @Bindable var item: FooterItem
  @Environment(AppState.self) private var appState

  var body: some View {
    ConfirmationView(item: item) {
      ListItemView(
        id: item.id,
        selectionId: item.id,
        shortcuts: item.shortcuts,
        isSelected: item.isSelected,
        accessibilityLabel: NSLocalizedString(item.title, bundle: .module, comment: "")
      ) {
        Text(LocalizedStringKey(item.title), bundle: .module)
      }
    }
    .onHover { hovering in
      if hovering && appState.preview.state.isOpen {
        appState.preview.togglePreview()
      }
    }
  }
}
