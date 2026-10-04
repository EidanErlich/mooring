// Adapted from Maccy@c376789: Maccy/Views/ConfirmationView.swift
import SwiftUI

struct ConfirmationView<Content: View>: View {
  @Bindable var item: FooterItem
  @ViewBuilder let content: () -> Content

  var body: some View {
    if let confirmation = item.confirmation, let suppressConfirmation = item.suppressConfirmation {
      content()
        .buttonAction {
          if suppressConfirmation.wrappedValue {
            item.action()
          } else {
            item.showConfirmation = true
          }
        }
        .confirmationDialog(Text(confirmation.message, bundle: .module), isPresented: $item.showConfirmation) {
          Text(confirmation.comment, bundle: .module)
          Button(role: .destructive) {
            item.action()
          } label: {
            Text(confirmation.confirm, bundle: .module)
          }
          .accessibilityIdentifier("confirmation-confirm")
          Button(role: .cancel) {} label: { Text(confirmation.cancel, bundle: .module) }
        }
        .dialogSuppressionToggle(isSuppressed: suppressConfirmation)
    } else {
      content()
        .buttonAction {
          item.action()
        }
    }
  }
}
